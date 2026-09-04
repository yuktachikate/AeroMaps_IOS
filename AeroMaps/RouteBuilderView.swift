import SwiftUI
import MapKit

// MARK: - Suggestions

/// A candidate the entry field can turn into a waypoint. Coordinates resolve
/// locally and instantly; airports come from the bundled table plus the live
/// lookup; places come from MapKit's local search.
enum WaypointSuggestion: Identifiable {
    case airport(Airport)
    case coordinate(CLLocationCoordinate2D)
    case place(MKMapItem)

    var id: String {
        switch self {
        case .airport(let a):    return "apt-\(a.icao)"
        case .coordinate(let c): return "crd-\(c.latitude),\(c.longitude)"
        case .place(let item):   return "plc-\(item.name ?? "")-\(item.placemark.coordinate.latitude)"
        }
    }

    var title: String {
        switch self {
        case .airport(let a):    return a.icao
        case .coordinate(let c): return Waypoint.formatCoordinate(c)
        case .place(let item):   return item.name ?? "Place"
        }
    }

    var subtitle: String {
        switch self {
        case .airport(let a):
            let place = [a.city, a.state].filter { !$0.isEmpty }.joined(separator: ", ")
            return place.isEmpty ? a.name : "\(a.name) · \(place)"
        case .coordinate(let c):
            return String(format: "%.5f, %.5f", c.latitude, c.longitude)
        case .place(let item):
            return item.placemark.title ?? Waypoint.formatCoordinate(item.placemark.coordinate)
        }
    }

    var iconName: String {
        switch self {
        case .airport:    return WaypointKind.airport.symbolName
        case .coordinate: return WaypointKind.coordinate.symbolName
        case .place:      return WaypointKind.place.symbolName
        }
    }

    var tint: Color {
        switch self {
        case .airport:    return .cyan
        case .coordinate: return .orange
        case .place:      return .purple
        }
    }

    func makeWaypoint() -> Waypoint {
        switch self {
        case .airport(let a):
            return Waypoint(airport: a)
        case .coordinate(let c):
            return Waypoint(ident: Waypoint.formatCoordinate(c), name: "Coordinate",
                            coordinate: c, kind: .coordinate)
        case .place(let item):
            let name = item.name ?? "Place"
            return Waypoint(ident: name, name: item.placemark.title ?? name,
                            coordinate: item.placemark.coordinate, kind: .place)
        }
    }
}

/// Debounced lookup behind the "add a waypoint" field.
///
/// Coordinates are parsed synchronously so a typed lat/long offers itself
/// immediately; airports and places resolve as results arrive.
final class WaypointSearchModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var suggestions: [WaypointSuggestion] = []
    @Published private(set) var isSearching = false

    private var placeSearch: MKLocalSearch?
    /// Where the pilot is looking, used to rank results by proximity.
    private var nearCoordinate: CLLocationCoordinate2D?
    private var pendingWork: DispatchWorkItem?

    func update(query: String, airports: AirportCatalog, liveResults: [Airport], near region: MKCoordinateRegion?) {
        self.query = query
        nearCoordinate = region?.center
        pendingWork?.cancel()
        placeSearch?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            isSearching = false
            return
        }

        // Immediate, offline matches first.
        var immediate: [WaypointSuggestion] = []
        if let coord = CoordinateParser.parse(trimmed) {
            immediate.append(.coordinate(coord))
        }
        immediate.append(contentsOf: matchingAirports(trimmed, airports: airports, live: liveResults)
            .prefix(8).map(WaypointSuggestion.airport))
        suggestions = immediate
        isSearching = true

        // Places lag behind a short debounce so typing does not fire a request per key.
        let work = DispatchWorkItem { [weak self] in
            self?.runPlaceSearch(trimmed, region: region, keeping: immediate)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func matchingAirports(_ query: String, airports: AirportCatalog, live: [Airport]) -> [Airport] {
        // The catalog ranks exact idents first, then prefixes, then names — with
        // distance from the map's centre breaking ties, so a local field wins over a
        // similarly-named one on another continent.
        var out = airports.search(query, near: nearCoordinate, limit: 8)
        var seen = Set(out.map(\.icao))
        // Unverified map hits fill in behind anything the database knows.
        for airport in live where seen.insert(airport.icao).inserted { out.append(airport) }
        return out
    }

    private func runPlaceSearch(_ query: String, region: MKCoordinateRegion?, keeping existing: [WaypointSuggestion]) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region { request.region = region }

        let search = MKLocalSearch(request: request)
        placeSearch = search
        search.start { [weak self] response, _ in
            DispatchQueue.main.async {
                guard let self, self.query.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                let places = (response?.mapItems ?? []).prefix(5).map(WaypointSuggestion.place)
                self.suggestions = existing + places
                self.isSearching = false
            }
        }
    }

    func clear() {
        pendingWork?.cancel()
        placeSearch?.cancel()
        query = ""
        suggestions = []
        isSearching = false
    }
}

// MARK: - Route builder

/// The route-editing surface inside the bottom sheet: add waypoints by ident,
/// coordinate, place or pasted route string; reorder and delete them; and set the
/// altitude for each point.
struct RouteBuilderView: View {
    @ObservedObject var mapState: MapState
    /// Hidden when the host already titles the section, as the flight planner does.
    var showsHeader: Bool = true
    @StateObject private var search = WaypointSearchModel()
    @State private var entryText: String = ""
    @State private var routeStringText: String = ""
    @State private var showRouteStringField = false
    @State private var routeStringError: String?
    @FocusState private var entryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader { header }

            entryField

            if !search.suggestions.isEmpty {
                suggestionList
            }

            if showRouteStringField {
                routeStringEntry
            }

            if mapState.route.waypoints.isEmpty {
                emptyState
            } else {
                waypointList

                if mapState.route.waypoints.count >= 2 {
                    RouteAltitudeFooter(mapState: mapState)
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .foregroundColor(.cyan)
            Text("Route")
                .font(.subheadline).fontWeight(.bold)
                .foregroundColor(.white)

            if !mapState.route.waypoints.isEmpty {
                Text("\(mapState.route.waypoints.count) point\(mapState.route.waypoints.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showRouteStringField.toggle() }
            } label: {
                Label("Paste route", systemImage: "text.badge.plus")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(showRouteStringField ? .cyan : .white.opacity(0.75))
            }
            .buttonStyle(.plain)

            if !mapState.route.waypoints.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { mapState.clearRoute() }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Entry

    private var entryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.magnifyingglass")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))

            TextField("Airport, coordinates, or place", text: $entryText)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .focused($entryFocused)
                .submitLabel(.go)
                .onSubmit { commitTopSuggestion() }
                .onChange(of: entryText) { _, value in
                    mapState.performLiveAirportSearch(query: value)
                    search.update(query: value,
                                  airports: mapState.airports,
                                  liveResults: mapState.liveSearchResults,
                                  near: currentRegion)
                }

            if !entryText.isEmpty {
                Button {
                    entryText = ""
                    search.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            Button(action: commitTopSuggestion) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(canCommit ? .blue : .white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(entryFocused ? Color.blue.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var canCommit: Bool { !search.suggestions.isEmpty }

    private func commitTopSuggestion() {
        guard let first = search.suggestions.first else { return }
        add(first)
    }

    private func add(_ suggestion: WaypointSuggestion) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            mapState.appendWaypoint(suggestion.makeWaypoint())
        }
        entryText = ""
        search.clear()
        entryFocused = false
        hideKeyboard()
        if mapState.route.waypoints.count >= 2 { mapState.zoomToRoute() }
    }

    private var suggestionList: some View {
        VStack(spacing: 4) {
            ForEach(search.suggestions) { suggestion in
                Button { add(suggestion) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.iconName)
                            .font(.subheadline)
                            .foregroundColor(suggestion.tint)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title)
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(suggestion.subtitle)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "plus")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity)
    }

    // MARK: Pasted route string

    private var routeStringEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("KSFO KSJC 3730N12210W KLAS", text: $routeStringText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.go)
                    .onSubmit(applyRouteString)

                Button("Load", action: applyRouteString)
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.blue)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let routeStringError {
                Text(routeStringError)
                    .font(.caption2)
                    .foregroundColor(.orange)
            } else {
                Text("Space-separated idents and coordinates. Replaces the current route.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private func applyRouteString() {
        let tokens = RouteStringParser.parse(routeStringText, airports: mapState.airports)
        let resolved = tokens.compactMap(\.waypoint)
        let failed = tokens.filter { $0.waypoint == nil }.map(\.text)

        guard resolved.count >= 1 else {
            routeStringError = "Nothing recognised in that route."
            return
        }
        routeStringError = failed.isEmpty ? nil : "Skipped: \(failed.joined(separator: ", "))"
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            mapState.route.waypoints = resolved
            mapState.routeBuilderRevealCount += 1
        }
        hideKeyboard()
        mapState.zoomToRoute()
    }

    // MARK: Waypoint list

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap")
                .foregroundColor(.white.opacity(0.5))
            Text("Type above, or press and hold anywhere on the map to drop a waypoint.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var waypointList: some View {
        VStack(spacing: 0) {
            ForEach(Array(mapState.route.waypoints.enumerated()), id: \.element.id) { index, waypoint in
                WaypointRowView(
                    mapState: mapState,
                    waypoint: waypoint,
                    index: index,
                    total: mapState.route.waypoints.count
                )
                // Drag to reorder. The row menu keeps Move up/down for anyone who
                // would rather not drag, and for accessibility.
                .draggable(waypoint.id.uuidString) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal")
                        Text(waypoint.ident).fontWeight(.bold)
                    }
                    .font(.caption)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.blue.opacity(0.85))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let draggedID = UUID(uuidString: raw),
                          let from = mapState.route.waypoints.firstIndex(where: { $0.id == draggedID }),
                          from != index else { return false }
                    // SwiftUI's move offset counts the removal, so a downward move
                    // targets one past the row it was dropped on.
                    mapState.moveWaypoints(from: IndexSet(integer: from),
                                           to: index > from ? index + 1 : index)
                    return true
                }

                if index < mapState.route.waypoints.count - 1,
                   index < mapState.altitudeProfile.legs.count {
                    LegRowView(leg: mapState.altitudeProfile.legs[index])
                }
            }
        }
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var currentRegion: MKCoordinateRegion? {
        let center = mapState.camera.centerCoordinate
        guard CLLocationCoordinate2DIsValid(center) else { return nil }
        return MKCoordinateRegion(center: center,
                                  latitudinalMeters: 200_000,
                                  longitudinalMeters: 200_000)
    }
}

// MARK: - Waypoint row

struct WaypointRowView: View {
    @ObservedObject var mapState: MapState
    let waypoint: Waypoint
    let index: Int
    let total: Int

    private var isDeparture: Bool { index == 0 }
    private var isDestination: Bool { total > 1 && index == total - 1 }

    private var altitudeFT: Int? { mapState.altitudeProfile.waypointAltitudes[waypoint.id] }
    private var minimumSafeFT: Int? { mapState.altitudeProfile.waypointMinimumSafe[waypoint.id] }
    private var raisedForTerrain: Bool { mapState.altitudeProfile.terrainRaisedWaypoints.contains(waypoint.id) }

    /// Set when the pilot has pinned an altitude that sits under the terrain floor
    /// for this point — worth saying out loud rather than silently accepting.
    private var belowMinimum: Bool {
        guard waypoint.isAltitudeManual, let altitude = altitudeFT, let floor = minimumSafeFT else { return false }
        return altitude < floor
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.28))

            ZStack {
                Circle()
                    .fill(markerColor.opacity(0.22))
                    .frame(width: 26, height: 26)
                if isDeparture {
                    Image(systemName: "airplane.departure").font(.caption2).foregroundColor(markerColor)
                } else if isDestination {
                    Image(systemName: "airplane.arrival").font(.caption2).foregroundColor(markerColor)
                } else {
                    Text("\(index + 1)").font(.caption2).fontWeight(.heavy).foregroundColor(markerColor)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(waypoint.ident)
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Image(systemName: waypoint.kind.symbolName)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.45))
                }
                HStack(spacing: 5) {
                    Text(waypoint.reason ?? waypoint.subtitle)
                        .font(.caption2)
                        .foregroundColor(waypoint.reason == nil ? .white.opacity(0.55) : .orange.opacity(0.85))
                        .lineLimit(1)

                    if belowMinimum, let floor = minimumSafeFT {
                        Label("min \(floor.formatted()) ft", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                    } else if raisedForTerrain {
                        Label("raised for terrain", systemImage: "mountain.2.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange.opacity(0.85))
                    }
                }
            }

            Spacer(minLength: 6)

            altitudeControl

            Menu {
                Button {
                    mapState.camera = MKMapCamera(lookingAtCenter: waypoint.coordinate,
                                                  fromDistance: 40_000, pitch: 0, heading: 0)
                    mapState.shouldCenterCamera = true
                } label: { Label("Centre on map", systemImage: "scope") }

                if index > 0 {
                    Button {
                        mapState.moveWaypoints(from: IndexSet(integer: index), to: index - 1)
                    } label: { Label("Move up", systemImage: "arrow.up") }
                }
                if index < total - 1 {
                    Button {
                        mapState.moveWaypoints(from: IndexSet(integer: index), to: index + 2)
                    } label: { Label("Move down", systemImage: "arrow.down") }
                }
                if waypoint.isAltitudeManual {
                    Button {
                        mapState.setWaypointAltitude(id: waypoint.id, altitudeFT: nil)
                    } label: { Label("Use suggested altitude", systemImage: "wand.and.stars") }
                }
                if let floor = minimumSafeFT {
                    Button {
                        mapState.setWaypointAltitude(id: waypoint.id, altitudeFT: floor)
                    } label: {
                        Label("Set minimum safe \(floor.formatted()) ft", systemImage: "mountain.2")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    withAnimation { mapState.removeWaypoint(id: waypoint.id) }
                } label: { Label("Remove", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    /// Altitude for this point, with steppers. Auto values show dimmed; touching a
    /// stepper pins the altitude so the profile flies through it.
    private var altitudeControl: some View {
        HStack(spacing: 4) {
            Button {
                adjustAltitude(by: -500)
            } label: {
                Image(systemName: "minus").font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.1)).clipShape(Circle())
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                Text(altitudeFT.map { "\($0.formatted())" } ?? "—")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(altitudeTint)
                Text(altitudeSourceLabel)
                    .font(.system(size: 8))
                    .foregroundColor(altitudeTint.opacity(0.7))
            }
            .frame(width: 46)

            Button {
                adjustAltitude(by: 500)
            } label: {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.1)).clipShape(Circle())
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }

    /// Distinguishes a pilot-set altitude from one the planner chose, and from one
    /// the planner had to lift to clear terrain.
    private var altitudeSourceLabel: String {
        if belowMinimum { return "LOW" }
        if waypoint.isAltitudeManual { return "SET" }
        if raisedForTerrain { return "TERR" }
        // Naming the phase explains why a point sits below the cruise level: it is
        // still climbing to it, or already coming down from it.
        switch mapState.altitudeProfile.waypointPhases[waypoint.id] {
        case .climb:   return "CLIMB"
        case .descent: return "DESC"
        default:       return isDeparture || isDestination ? "FIELD" : "CRUISE"
        }
    }

    private var altitudeTint: Color {
        if belowMinimum { return .orange }
        if waypoint.isAltitudeManual { return .cyan }
        if raisedForTerrain { return .orange.opacity(0.9) }
        return .white.opacity(0.75)
    }

    private func adjustAltitude(by delta: Int) {
        let base = waypoint.plannedAltitudeFT ?? altitudeFT ?? mapState.route.altitudeFT
        let floor = waypoint.fieldElevationFT ?? 0
        let ceiling = mapState.route.performance.maxPlanningAltitudeFT
        mapState.setWaypointAltitude(id: waypoint.id,
                                     altitudeFT: min(max(base + delta, floor), ceiling))
    }

    private var markerColor: Color {
        if isDeparture { return .green }
        if isDestination { return .red }
        return .blue
    }
}

// MARK: - Leg row

/// The nav-log line between two waypoints: distance, course, vertical phase, time
/// and fuel, plus a terrain warning when the planned altitude is too low.
struct LegRowView: View {
    let leg: RouteLeg

    private var conflict: Bool {
        leg.hasTerrainConflict(minClearanceFT: AltitudeProfile.minimumClearanceFT)
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 18)
                .padding(.leading, 22)

            Image(systemName: leg.phase.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(phaseColor)

            Text(leg.phase.shortLabel)
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(phaseColor)

            Text("\(Int(leg.distanceNM.rounded())) NM")
                .font(.caption2).foregroundColor(.white.opacity(0.7))

            Text(String(format: "%03.0f°T", leg.courseTrue))
                .font(.caption2).foregroundColor(.white.opacity(0.55))

            Text("\(Int(leg.timeMinutes.rounded())) min")
                .font(.caption2).foregroundColor(.white.opacity(0.55))

            Spacer()

            if conflict {
                Label("Terrain", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange)
            } else {
                Text(String(format: "%.1f gal", leg.fuelGallons))
                    .font(.caption2).foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }

    private var phaseColor: Color {
        switch leg.phase {
        case .climb:   return .green
        case .cruise:  return .cyan
        case .descent: return .orange
        case .climbCruise, .cruiseDescent, .mixed: return .purple
        }
    }
}

// MARK: - Route altitude footer

/// Just the one route-wide control that belongs next to the waypoints: the cruise
/// level, which moves every altitude above it.
///
/// Top of climb, the suggestion's reasoning and the terrain verdict used to live
/// here too. They are analysis rather than editing, they repeated what Check Route
/// already reports with a one-tap fix, and the card resizing as they came and went
/// shifted the buttons below it. They now live in Route Advisor and the profile.
struct RouteAltitudeFooter: View {
    @ObservedObject var mapState: MapState

    private var profile: AltitudeProfile { mapState.altitudeProfile }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().background(Color.white.opacity(0.12))

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cruise level").font(.caption2).foregroundColor(.white.opacity(0.6))
                    HStack(spacing: 6) {
                        Button {
                            mapState.route.altitudeFT = max(1_500, mapState.route.altitudeFT - 500)
                        } label: { Image(systemName: "minus.circle.fill").foregroundColor(.blue) }
                        .buttonStyle(.plain)

                        Text("\(mapState.route.altitudeFT.formatted()) ft")
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                            .frame(minWidth: 68)

                        Button {
                            mapState.route.altitudeFT = min(mapState.route.performance.maxPlanningAltitudeFT,
                                                            mapState.route.altitudeFT + 500)
                        } label: { Image(systemName: "plus.circle.fill").foregroundColor(.blue) }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                status
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// One line on whether the level is sound, pointing at Check Route for the why.
    @ViewBuilder
    private var status: some View {
        let conflicts = profile.conflictedLegs
        if mapState.terrain.isLoading {
            Label("checking terrain", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2).foregroundColor(.white.opacity(0.55))
        } else if !conflicts.isEmpty {
            Label("\(conflicts.count) leg\(conflicts.count == 1 ? "" : "s") too low",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).fontWeight(.semibold).foregroundColor(.orange)
        } else if let suggestion = mapState.cruiseSuggestion,
                  suggestion.altitudeFT != mapState.route.altitudeFT {
            Label("\(suggestion.altitudeFT.formatted()) ft suggested",
                  systemImage: "wand.and.stars")
                .font(.caption2).fontWeight(.semibold).foregroundColor(.yellow)
        } else if profile.maxTerrainFT != nil {
            Label("clearance OK", systemImage: "checkmark.shield.fill")
                .font(.caption2).foregroundColor(.green.opacity(0.9))
        }
    }
}
