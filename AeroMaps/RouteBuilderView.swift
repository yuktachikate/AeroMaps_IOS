import SwiftUI
import MapKit

// MARK: - Route builder

/// The route-editing surface inside the bottom sheet: add waypoints by ident,
/// coordinate, place or pasted route string; reorder and delete them; and set the
/// altitude for each point.
struct RouteBuilderView: View {
    @ObservedObject var mapState: MapState
    /// Hidden when the host already titles the section, as the flight planner does.
    var showsHeader: Bool = true
    @State private var routeStringText: String = ""
    @State private var showRouteStringField = false
    @State private var routeStringError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader { header }

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
            Text("Search at the top of the sheet, or press and hold anywhere on the map to drop a waypoint.")
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
                    LegRowView(leg: mapState.altitudeProfile.legs[index],
                               profile: mapState.altitudeProfile)
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

                    if let stop = waypoint.stop {
                        Label(stop.refuels
                                ? "\(stop.kind.label) · \(stop.groundMinutes) min · to \(Int(stop.refuelToGal ?? 0)) gal"
                                : "\(stop.kind.label) · \(stop.groundMinutes) min",
                              systemImage: stop.kind.symbolName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green)
                    }

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

                // Only interior airports: you cannot stop at your own departure or
                // destination, and a coordinate in the middle of a valley is not a
                // place to land.
                if !isDeparture, !isDestination, waypoint.kind == .airport {
                    Divider()
                    if waypoint.isStop {
                        Button {
                            mapState.setStop(id: waypoint.id, stop: nil)
                        } label: { Label("Don't stop — overfly", systemImage: "arrow.up.right") }
                        Menu("Change stop") { stopOptions }
                    } else {
                        Menu {
                            stopOptions
                        } label: { Label("Stop here", systemImage: "pause.circle") }
                    }
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

    /// Presets rather than a form: on the ground before a flight these get tapped
    /// once, and the numbers are editable afterwards from the same menu.
    @ViewBuilder
    private var stopOptions: some View {
        Button {
            mapState.setStop(id: waypoint.id,
                             stop: StopPlan(kind: .fuel, groundMinutes: 45,
                                            refuelToGal: mapState.route.aircraft.usableFuelGal))
        } label: { Label("Fuel stop — 45 min, fill tanks", systemImage: "fuelpump.fill") }

        Button {
            mapState.setStop(id: waypoint.id,
                             stop: StopPlan(kind: .rest, groundMinutes: 30, refuelToGal: nil))
        } label: { Label("Rest stop — 30 min, no fuel", systemImage: "cup.and.saucer.fill") }

        Button {
            mapState.setStop(id: waypoint.id,
                             stop: StopPlan(kind: .overnight, groundMinutes: 12 * 60,
                                            refuelToGal: mapState.route.aircraft.usableFuelGal))
        } label: { Label("Overnight — fill tanks", systemImage: "moon.stars.fill") }
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
    /// Needed for top of climb and top of descent, which are properties of the whole
    /// profile rather than of one leg.
    var profile: AltitudeProfile = AltitudeProfile()

    private var conflict: Bool {
        leg.hasTerrainConflict(minClearanceFT: AltitudeProfile.minimumClearanceFT)
    }

    /// Where the level-off and the descent fall inside this leg, if they do.
    ///
    /// The profile has always known both — it computes them to draw the altitude
    /// graph — but the route list only ever showed the phase name. "CLB/CRZ" tells a
    /// pilot the leg contains a climb somewhere; it does not tell them the thing they
    /// actually need, which is how far along to stop climbing and when to start down.
    private var topOfClimbNM: Double? {
        let offset = profile.topOfClimbNM - leg.startDistanceNM
        guard offset > 0.5, offset < leg.distanceNM - 0.5 else { return nil }
        return offset
    }

    private var topOfDescentNM: Double? {
        let offset = profile.topOfDescentNM - leg.startDistanceNM
        guard offset > 0.5, offset < leg.distanceNM - 0.5 else { return nil }
        return offset
    }

    /// True when the profile tops out at a peak rather than holding a cruise — the
    /// route is too short to reach the planned level and start down from it.
    private var neverCruises: Bool {
        profile.topOfDescentNM - profile.topOfClimbNM < 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            legLine
            // Stated as a distance from the start of the leg, because that is how it
            // gets flown: level off N miles after the last waypoint, start down N
            // miles after it.
            if neverCruises, let nm = topOfClimbNM {
                // Climb and descent meet: the leg is too short to level off at all,
                // so there is one turning point, not two. Printing "level off" and
                // "start down" at the same mile would be worse than saying nothing.
                cue("Top of climb \(Int(nm.rounded())) NM after \(leg.fromIdent) — straight back down",
                    "triangle.fill", .yellow,
                    "\(profile.achievedAltitudeFT.formatted()) ft peak")
            } else {
                if let nm = topOfClimbNM {
                    cue("Level off \(Int(nm.rounded())) NM after \(leg.fromIdent)",
                        "arrow.up.right.circle.fill", .green,
                        "\(profile.achievedAltitudeFT.formatted()) ft")
                }
                if let nm = topOfDescentNM {
                    cue("Start down \(Int(nm.rounded())) NM after \(leg.fromIdent)",
                        "arrow.down.right.circle.fill", .orange,
                        "\(Int(leg.distanceNM - nm)) NM to \(leg.toIdent)")
                }
            }
        }
    }

    /// One cue on the descent or level-off point.
    private func cue(_ text: String, _ icon: String, _ tint: Color, _ trailing: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 14)
                .padding(.leading, 22)
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(tint)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint)
            Spacer(minLength: 4)
            Text(trailing)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private var legLine: some View {
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
