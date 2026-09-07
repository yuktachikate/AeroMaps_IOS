import SwiftUI
import MapKit
import CoreLocation

/// One search field for the whole app, and the card a result opens into.
///
/// There used to be two search fields: one at the top of the sheet that searched
/// only airports and dead-ended by opening a detail panel, and a second one buried
/// inside the expanded route builder that searched airports, places *and*
/// coordinates and could actually add a waypoint. The more capable field was the
/// one you could not see, and the visible one could not build a route — so the
/// first thing a pilot searched for was usually in the wrong box.
///
/// This follows the shape people already know from consumer map apps: search,
/// look at what you found, then decide to route to it. The difference here is that
/// aviation routes are rarely two points, so "add" stays one tap from the results
/// list once a route is under way rather than making every stop a trip through the
/// card.

// MARK: - Suggestions

/// A candidate the search field can turn into a waypoint. Coordinates resolve
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

    /// Named `location` rather than `coordinate` because a case is already called
    /// that, and `suggestion.coordinate` would resolve to the case, not the position.
    var location: CLLocationCoordinate2D {
        switch self {
        case .airport(let a):    return a.coordinate
        case .coordinate(let c): return c
        case .place(let item):   return item.placemark.coordinate
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
    /// Run once per typing pause, for work too expensive to do per keystroke —
    /// the global airport lookup, which publishes to shared state as it starts.
    var onDebounced: ((String) -> Void)?

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

        // A typed coordinate resolves instantly — it is pure parsing, no scan.
        var immediate: [WaypointSuggestion] = []
        if let coord = CoordinateParser.parse(trimmed) {
            immediate.append(.coordinate(coord))
        }
        // The airport scan is debounced with the place search rather than run on
        // every keystroke. Scanning ~29,000 records per character was enough to
        // make typing an ident stutter.
        suggestions = immediate + suggestions.filter {
            if case .airport = $0 { return true } else { return false }
        }
        isSearching = true

        // Places lag behind a short debounce so typing does not fire a request per key.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let airportHits = self.matchingAirports(trimmed, airports: airports, live: liveResults)
                .prefix(8).map(WaypointSuggestion.airport)
            let base = immediate + airportHits
            self.suggestions = base
            self.onDebounced?(trimmed)
            self.runPlaceSearch(trimmed, region: region, keeping: base)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
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

// MARK: - Result rows

/// A single hit in the unified results list.
///
/// Tapping the row opens the card; the `+` adds it to the route directly. Both are
/// offered because the two are genuinely different tasks — deciding *whether* to fly
/// somewhere versus adding the fourth stop to a route you have already decided on —
/// and forcing the second through the first is what makes route entry tedious.
struct SearchResultRow: View {
    let suggestion: WaypointSuggestion
    let onOpen: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
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

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(suggestion.title) to route")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Result card

/// What a search result opens into: enough to decide, and the actions to act on it.
///
/// The primary action is labelled for the route's actual state — "Set as departure"
/// on an empty route, "Add as destination" on a route of one, "Add stop" after that
/// — because "Add to route" leaves the pilot to work out where in the sequence it
/// landed.
struct SearchResultCard: View {
    @ObservedObject var mapState: MapState
    let suggestion: WaypointSuggestion
    let onAdd: () -> Void
    let onDismiss: () -> Void

    private var waypointCount: Int { mapState.route.waypoints.count }

    private var primaryLabel: String {
        switch waypointCount {
        case 0:  return "Set as departure"
        case 1:  return "Add as destination"
        default: return "Add stop"
        }
    }

    /// Distance and true bearing from where the pilot is, falling back to the map's
    /// centre when there is no fix. Stated relative to a named origin either way, so
    /// the figure is never ambiguous about what it is measured from.
    private var relativePosition: (text: String, from: String)? {
        let target = suggestion.location
        let origin: (CLLocationCoordinate2D, String)
        if let here = mapState.locationManager?.lastLocation?.coordinate {
            origin = (here, "you")
        } else {
            origin = (mapState.camera.centerCoordinate, "map centre")
        }
        let nm = AltitudePlanner.distanceNM(origin.0, target)
        guard nm > 0.5 else { return nil }
        let brg = Int(AltitudePlanner.bearingDegrees(from: origin.0, to: target).rounded()) % 360
        return (String(format: "%.0f NM · %03d°T", nm, brg), origin.1)
    }

    private var airport: Airport? {
        if case .airport(let a) = suggestion { return a }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: suggestion.iconName)
                    .font(.title3)
                    .foregroundColor(suggestion.tint)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(suggestion.subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                    if let rel = relativePosition {
                        Text("\(rel.text) from \(rel.from)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            if let airport, !airport.isVerified {
                // Map hits that the aeronautical database does not know are usable as
                // a point to fly over, but nothing is published about them, so they
                // must not read like a field with fuel and a frequency.
                Label("Not in the aeronautical database — position only",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            HStack(spacing: 8) {
                Button(action: onAdd) {
                    Label(primaryLabel, systemImage: "plus")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                if let airport {
                    Button {
                        mapState.selectedAirport = airport
                        mapState.showingAirportDetail = true
                    } label: {
                        Label("Details", systemImage: "info.circle")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        mapState.camera = MKMapCamera(lookingAtCenter: suggestion.location,
                                                      fromDistance: 45_000, pitch: 0, heading: 0)
                        mapState.shouldCenterCamera = true
                    }
                } label: {
                    Image(systemName: "scope")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show on map")
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(suggestion.tint.opacity(0.35), lineWidth: 1)
        )
    }
}
