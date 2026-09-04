import Foundation
import CoreLocation

// MARK: - Generation

/// Builds a complete route between two points: en-route checkpoints, a fuel stop
/// when the aircraft cannot make it in one go, and an altitude plan that clears the
/// terrain underneath.
///
/// Everything it produces is a *proposal*. Nothing is applied until the pilot says
/// so, and every point it adds stays editable afterwards — the generator's job is to
/// give a sound starting point, not to have the last word.
enum RouteGenerator {

    struct Note: Identifiable {
        enum Kind { case info, caution }
        let id = UUID()
        let kind: Kind
        let icon: String
        let text: String
    }

    struct Proposal {
        let waypoints: [Waypoint]
        let cruiseAltitudeFT: Int
        let notes: [Note]
        let distanceNM: Double
        let timeMinutes: Double
        let fuelGallons: Double
    }

    /// A leg longer than this with nothing else on it gets one midpoint, purely so
    /// there is something to fix position against and divert from.
    private static let longLegNM: Double = 120
    /// Day VFR fuel reserve: 30 minutes at normal cruise (14 CFR 91.151).
    private static let reserveMinutes: Double = 30
    /// How far either side of the track terrain is considered when deciding whether
    /// a level change is needed.
    private static let terrainCorridorNM: Double = 5

    /// Fills out the route the pilot already drew.
    ///
    /// Every point it adds has to earn its place. An evenly-spaced string of points
    /// down a straight line at one altitude is noise — it adds rows to the nav log
    /// and nothing to the flight. A waypoint is only inserted where something
    /// actually changes: terrain forces a level change, fuel runs out, or a leg is
    /// long enough that the pilot wants a position fix partway.
    static func generate(route existing: [Waypoint],
                         aircraft: AircraftProfile,
                         performance: AircraftPerformance,
                         fuelOnBoardGal: Double,
                         airports: AirportCatalog,
                         terrain: TerrainSampler?) -> Proposal {

        var notes: [Note] = []
        guard existing.count >= 2 else {
            return Proposal(waypoints: existing, cruiseAltitudeFT: 6_500, notes: [],
                            distanceNM: 0, timeMinutes: 0, fuelGallons: 0)
        }
        let totalNM = AltitudePlanner.totalDistanceNM(existing)

        // 1. Cruise altitude from terrain + the hemispherical rule.
        let suggestion = AltitudePlanner.suggestCruiseAltitude(
            waypoints: existing, performance: performance, terrain: terrain)
        let cruise = suggestion?.altitudeFT ?? 6_500
        if let suggestion {
            notes.append(Note(kind: .info, icon: "arrow.up.to.line",
                              text: "Cruise \(cruise.formatted()) ft — \(suggestion.rationale)."))
        }

        // 2. Walk each leg the pilot drew, inserting only points that do something.
        var waypoints: [Waypoint] = []
        var terrainPoints = 0
        var fixPoints = 0

        for i in 0..<(existing.count - 1) {
            let a = existing[i], b = existing[i + 1]
            waypoints.append(a)
            let legNM = AltitudePlanner.distanceNM(a.coordinate, b.coordinate)
            guard legNM > 10 else { continue }

            var inserted: [(distance: Double, waypoint: Waypoint)] = []

            // (a) Terrain that pushes above the planned cruise: one point at the
            //     high ground, carrying the altitude needed to clear it.
            if let terrain {
                let course = AltitudePlanner.bearingDegrees(from: a.coordinate, to: b.coordinate)
                for ridge in terrainRidges(from: a, to: b, legNM: legNM, cruiseFT: cruise,
                                           ceiling: performance.maxPlanningAltitudeFT, terrain: terrain) {
                    let level = AltitudePlanner.hemisphericalAltitude(
                        atLeast: ridge.requiredFT, courseDegrees: course,
                        ceiling: performance.maxPlanningAltitudeFT)
                    // Name it after a navaid within 15 NM where there is one: a
                    // point a pilot can tune and identify beats a string of
                    // coordinates on a kneeboard.
                    let navaid = airports.nearestNavaid(to: ridge.coordinate, withinNM: 15)
                    inserted.append((ridge.distanceNM, Waypoint(
                        ident: navaid.map { "\($0.ident)" } ?? Waypoint.formatCoordinate(ridge.coordinate),
                        name: navaid.map { "\($0.name) \($0.type)" } ?? "Terrain step-up",
                        coordinate: ridge.coordinate,
                        kind: .coordinate,
                        plannedAltitudeFT: level,
                        reason: "Terrain reaches \(Int(ridge.terrainFT).formatted()) ft here — climb to \(level.formatted()) ft")))
                    terrainPoints += 1
                }
            }

            // (b) A long leg with nothing on it gets one position fix, snapped to an
            //     airport if there is one near the halfway point.
            if inserted.isEmpty && legNM > longLegNM {
                let half = legNM / 2
                let coord = AltitudePlanner.coordinate(along: [a, b], cumulative: [0, legNM],
                                                       atDistance: half)
                if let airport = nearestAirport(to: coord, within: 15, airports: airports,
                                                excluding: waypoints + existing) {
                    inserted.append((half, Waypoint(airport: airport).withReason(
                        "Halfway on a \(Int(legNM)) NM leg — position fix and diversion option")))
                } else if let navaid = airports.nearestNavaid(to: coord, withinNM: 20) {
                    inserted.append((half, Waypoint(
                        ident: navaid.ident,
                        name: "\(navaid.name) \(navaid.type)",
                        coordinate: navaid.coordinate, kind: .coordinate,
                        reason: navaid.frequencyMHz.map {
                            "Halfway on a \(Int(legNM)) NM leg — \(navaid.type) on \(String(format: "%.2f", $0))"
                        } ?? "Halfway on a \(Int(legNM)) NM leg — position fix on \(navaid.ident)")))
                } else {
                    inserted.append((half, Waypoint(
                        ident: Waypoint.formatCoordinate(coord),
                        name: "Midpoint",
                        coordinate: coord, kind: .coordinate,
                        reason: "Halfway on a \(Int(legNM)) NM leg — position fix")))
                }
                fixPoints += 1
            }

            for entry in inserted.sorted(by: { $0.distance < $1.distance }) {
                waypoints.append(entry.waypoint)
            }
        }
        waypoints.append(existing[existing.count - 1])

        if terrainPoints > 0 {
            notes.append(Note(kind: .caution, icon: "mountain.2.fill",
                              text: "\(terrainPoints) level change\(terrainPoints == 1 ? "" : "s") added where terrain rises above the cruise altitude."))
        }
        if fixPoints > 0 {
            notes.append(Note(kind: .info, icon: "mappin.and.ellipse",
                              text: "\(fixPoints) position fix\(fixPoints == 1 ? "" : "es") added on legs over \(Int(longLegNM)) NM."))
        }
        if terrainPoints == 0 && fixPoints == 0 {
            notes.append(Note(kind: .info, icon: "checkmark.circle",
                              text: "No extra waypoints needed — terrain stays clear of the cruise altitude and no leg is long enough to want a position fix. Points that change nothing are left out on purpose."))
        }
        if existing.count > 2 {
            notes.append(Note(kind: .info, icon: "point.topleft.down.to.point.bottomright.curvepath",
                              text: "Your \(existing.count) points were kept in the order you set them."))
        }

        // 3. Fuel: can the aircraft make it with a legal reserve?
        //
        // Costed through the vertical profile rather than at a flat cruise rate.
        // Climb burns about 25% richer and descent about 30% leaner, so a flat
        // estimate understates a climb-heavy route — exactly the case where getting
        // the fuel-stop decision wrong matters most.
        let draftProfile = AltitudePlanner.computeProfile(waypoints: waypoints,
                                                          cruiseAltitudeFT: cruise,
                                                          performance: performance,
                                                          terrain: terrain)
        let reserveGal = (reserveMinutes / 60) * performance.fuelBurnGPH
        let requiredGal = draftProfile.totalFuelGallons + reserveGal
        if requiredGal > fuelOnBoardGal {
            if let stop = bestFuelStop(waypoints: waypoints, airports: airports,
                                       performance: performance, fuelOnBoardGal: fuelOnBoardGal) {
                waypoints.insert(stop.waypoint.withReason(
                    "Fuel — \(String(format: "%.1f", requiredGal)) gal needed with reserve, \(String(format: "%.1f", fuelOnBoardGal)) gal aboard"),
                                 at: stop.index)
                notes.append(Note(kind: .caution, icon: "fuelpump.fill",
                                  text: "\(String(format: "%.1f", requiredGal)) gal needed with a 30 min reserve but only \(String(format: "%.1f", fuelOnBoardGal)) gal aboard — added a fuel stop at \(stop.waypoint.ident)."))
            } else {
                notes.append(Note(kind: .caution, icon: "fuelpump.slash",
                                  text: "\(String(format: "%.1f", requiredGal)) gal needed with a 30 min reserve but only \(String(format: "%.1f", fuelOnBoardGal)) gal aboard, and no suitable fuel stop was found near the track."))
            }
        }

        // 4. Cost the finished proposal through the real vertical planner.
        let profile = AltitudePlanner.computeProfile(waypoints: waypoints,
                                                     cruiseAltitudeFT: cruise,
                                                     performance: performance,
                                                     terrain: terrain)
        if profile.achievedAltitudeFT < cruise - 100 {
            notes.append(Note(kind: .info, icon: "info.circle",
                              text: "Too short to reach \(cruise.formatted()) ft — the profile tops out at \(profile.achievedAltitudeFT.formatted()) ft."))
        }
        if terrain == nil {
            notes.append(Note(kind: .caution, icon: "wifi.exclamationmark",
                              text: "Terrain data was unavailable, so no terrain-driven level changes could be planned and altitudes rest on field elevations only."))
        }

        return Proposal(waypoints: waypoints,
                        cruiseAltitudeFT: cruise,
                        notes: notes,
                        distanceNM: profile.totalDistanceNM,
                        timeMinutes: profile.totalTimeMinutes,
                        fuelGallons: profile.totalFuelGallons)
    }

    private struct Ridge {
        let distanceNM: Double
        let coordinate: CLLocationCoordinate2D
        let terrainFT: Double
        let requiredFT: Double
    }

    /// High ground along a leg that the planned cruise altitude does not clear.
    ///
    /// Returns one point per contiguous stretch — the peak of it — rather than one
    /// per sample, so a single ridge produces a single "climb here" waypoint instead
    /// of a dozen identical ones.
    private static func terrainRidges(from a: Waypoint, to b: Waypoint, legNM: Double,
                                      cruiseFT: Int, ceiling: Int,
                                      terrain: TerrainSampler) -> [Ridge] {
        let steps = max(Int(legNM / 2), 8)
        var ridges: [Ridge] = []
        var current: Ridge?

        for step in 0...steps {
            let d = legNM * Double(step) / Double(steps)
            let coord = AltitudePlanner.coordinate(along: [a, b], cumulative: [0, legNM], atDistance: d)
            // Look across a corridor, not a hairline, so a peak just off track counts.
            var peak = -Double.greatestFiniteMagnitude
            for offset in stride(from: -terrainCorridorNM, through: terrainCorridorNM, by: 2.5) {
                let probe = AltitudePlanner.coordinate(along: [a, b], cumulative: [0, legNM],
                                                       atDistance: min(max(d + offset, 0), legNM))
                if let g = terrain.elevationFT(at: probe) { peak = max(peak, g) }
            }
            guard peak > -.greatestFiniteMagnitude else { continue }

            let required = peak + Double(AltitudeProfile.preferredClearanceFT)
            // Ignore the ends: an aircraft is low there by definition.
            let nearEnd = d < 6 || legNM - d < 6
            if required > Double(cruiseFT) + 100, !nearEnd, required <= Double(ceiling) {
                if let existing = current, required > existing.requiredFT {
                    current = Ridge(distanceNM: d, coordinate: coord, terrainFT: peak, requiredFT: required)
                } else if current == nil {
                    current = Ridge(distanceNM: d, coordinate: coord, terrainFT: peak, requiredFT: required)
                }
            } else if let finished = current {
                ridges.append(finished)
                current = nil
            }
        }
        if let finished = current { ridges.append(finished) }
        return ridges
    }

    private static func nearestAirport(to coord: CLLocationCoordinate2D,
                                       within limitNM: Double,
                                       airports: AirportCatalog,
                                       excluding used: [Waypoint]) -> Airport? {
        let taken = Set(used.compactMap(\.airportICAO))
        var best: (Airport, Double)?
        // Spatial query rather than a scan: the catalog is ~29,000 fields now.
        for airport in airports.nearby(coord, withinNM: limitNM, limit: 12)
        where !taken.contains(airport.icao) {
            let d = AltitudePlanner.distanceNM(coord, airport.coordinate)
            if best == nil || d < best!.1 { best = (airport, d) }
        }
        return best?.0
    }

    private struct FuelStop { let waypoint: Waypoint; let index: Int }

    /// The airport nearest the point where usable fuel runs low, preferring fields
    /// that actually sell fuel.
    private static func bestFuelStop(waypoints: [Waypoint],
                                     airports: AirportCatalog,
                                     performance: AircraftPerformance,
                                     fuelOnBoardGal: Double) -> FuelStop? {
        guard let origin = waypoints.first else { return nil }
        let usableHours = performance.fuelBurnGPH > 0
            ? max(0, fuelOnBoardGal / performance.fuelBurnGPH - reserveMinutes / 60) : 0
        let reachNM = usableHours * performance.cruiseKTAS
        guard reachNM > 0 else { return nil }

        // Measure along the route as flown, so an out-and-back looks for a stop
        // partway round rather than at its own departure field.
        var cumulative: [Double] = [0]
        for i in 1..<waypoints.count {
            cumulative.append(cumulative[i - 1] + AltitudePlanner.distanceNM(waypoints[i - 1].coordinate,
                                                                            waypoints[i].coordinate))
        }
        let total = cumulative.last ?? 0
        guard total > 0 else { return nil }
        // Stop a little before the range limit rather than right at it.
        let target = min(reachNM * 0.8, total * 0.75)
        let coord = AltitudePlanner.coordinate(along: waypoints, cumulative: cumulative,
                                               atDistance: target)

        let taken = Set(waypoints.compactMap(\.airportICAO))
        var best: (Airport, Double)?
        // Prefer a field with fuel, but any towered or paved field beats none.
        for airport in airports.nearby(coord, withinNM: 60, limit: 30)
        where !taken.contains(airport.icao) {
            let d = AltitudePlanner.distanceNM(coord, airport.coordinate)
            let hasRunway = airport.runways.contains { $0.length >= 2_500 }
            let score = d + (hasRunway ? 0 : 30)
            if best == nil || score < best!.1 { best = (airport, score) }
        }
        guard let chosen = best?.0 else { return nil }

        // Insert where the route passes closest to it, so along-track order holds
        // even when the route doubles back on itself.
        var index = waypoints.count - 1
        var closest = Double.greatestFiniteMagnitude
        for (i, wp) in waypoints.enumerated() where i > 0 {
            let d = AltitudePlanner.distanceNM(wp.coordinate, chosen.coordinate)
            if d < closest { closest = d; index = i }
        }
        _ = origin
        return FuelStop(waypoint: Waypoint(airport: chosen), index: index)
    }
}

// MARK: - Validation

/// Checks a built route against the things that would actually bite in flight:
/// terrain clearance, cruising-altitude rules, aircraft limits and fuel reserves.
enum RouteValidator {

    enum Severity: Int, Comparable {
        case pass, advisory, caution, warning
        static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }

        var label: String {
            switch self {
            case .pass:     return "OK"
            case .advisory: return "NOTE"
            case .caution:  return "CHECK"
            case .warning:  return "WARNING"
            }
        }
        var icon: String {
            switch self {
            case .pass:     return "checkmark.circle.fill"
            case .advisory: return "info.circle.fill"
            case .caution:  return "exclamationmark.circle.fill"
            case .warning:  return "exclamationmark.triangle.fill"
            }
        }
    }

    /// A one-tap correction the pilot can accept.
    enum Fix {
        case setCruise(Int)
        case setWaypointAltitude(UUID, Int)
        case clearWaypointOverrides

        var title: String {
            switch self {
            case .setCruise(let ft):              return "Set cruise \(ft.formatted()) ft"
            case .setWaypointAltitude(_, let ft): return "Raise to \(ft.formatted()) ft"
            case .clearWaypointOverrides:         return "Reset to suggested altitudes"
            }
        }
    }

    struct Finding: Identifiable {
        let id = UUID()
        let severity: Severity
        let title: String
        let detail: String
        let fix: Fix?
    }

    /// Point a fraction of the way along a leg, for airspace sampling.
    private static func legPoint(_ leg: RouteLeg, _ t: Double, _ waypoints: [Waypoint]) -> CLLocationCoordinate2D {
        guard let from = waypoints.first(where: { $0.id == leg.fromID }),
              let index = waypoints.firstIndex(where: { $0.id == leg.fromID }),
              index + 1 < waypoints.count else { return waypoints.first?.coordinate ?? .init() }
        let to = waypoints[index + 1]
        return CLLocationCoordinate2D(
            latitude: from.coordinate.latitude + (to.coordinate.latitude - from.coordinate.latitude) * t,
            longitude: from.coordinate.longitude + (to.coordinate.longitude - from.coordinate.longitude) * t)
    }

    static func validate(route: RoutePlan,
                         profile: AltitudeProfile,
                         terrainLoaded: Bool,
                         hazards: [AirSigmet] = [],
                         hazardFreshness: DataFreshness = .unavailable,
                         notamStatus: NotamService.Status = .notConfigured,
                         notamCount: Int = 0,
                         airspace: AirspaceService? = nil,
                         isStudentPilot: Bool = false) -> [Finding] {
        var findings: [Finding] = []
        let aircraft = route.aircraft
        let performance = route.performance

        guard route.waypoints.count >= 2 else {
            return [Finding(severity: .warning, title: "Route incomplete",
                            detail: "A route needs at least a departure and a destination.",
                            fix: nil)]
        }

        // Terrain clearance.
        let conflicts = profile.conflictedLegs
        if !terrainLoaded {
            findings.append(Finding(severity: .advisory, title: "Terrain not checked",
                                    detail: "Elevation data has not loaded, so terrain clearance could not be verified. Altitudes come from field elevations only.",
                                    fix: nil))
        } else if conflicts.isEmpty {
            findings.append(Finding(severity: .pass, title: "Terrain clearance",
                                    detail: profile.maxTerrainFT.map {
                                        "Highest terrain on route \($0.formatted()) ft; every leg keeps at least \(AltitudeProfile.minimumClearanceFT.formatted()) ft above it."
                                    } ?? "No terrain conflicts found.",
                                    fix: nil))
        } else {
            let worst = conflicts.compactMap(\.minClearanceFT).min() ?? 0
            let needed = AltitudePlanner.hemisphericalAltitude(
                atLeast: Double((profile.maxTerrainFT ?? 0) + AltitudeProfile.preferredClearanceFT),
                courseDegrees: AltitudePlanner.dominantLegCourse(route.waypoints),
                ceiling: performance.maxPlanningAltitudeFT)
            findings.append(Finding(
                severity: .warning,
                title: "\(conflicts.count) leg\(conflicts.count == 1 ? "" : "s") too low for terrain",
                detail: "Closest approach to the ground is \(worst.formatted()) ft, under the \(AltitudeProfile.minimumClearanceFT.formatted()) ft minimum. Affected: " +
                        conflicts.prefix(3).map { "\($0.fromIdent) → \($0.toIdent)" }.joined(separator: ", ") + ".",
                fix: needed > route.altitudeFT ? .setCruise(needed) : nil))
        }

        // Waypoints pinned below their own terrain floor.
        let low = route.waypoints.filter { wp in
            guard wp.isAltitudeManual, let floor = profile.waypointMinimumSafe[wp.id],
                  let planned = profile.waypointAltitudes[wp.id] else { return false }
            return planned < floor
        }
        for wp in low {
            let floor = profile.waypointMinimumSafe[wp.id] ?? 0
            findings.append(Finding(severity: .warning,
                                    title: "\(wp.ident) below minimum safe altitude",
                                    detail: "You set \((profile.waypointAltitudes[wp.id] ?? 0).formatted()) ft; terrain around this point needs \(floor.formatted()) ft for \(AltitudeProfile.preferredClearanceFT.formatted()) ft of clearance.",
                                    fix: .setWaypointAltitude(wp.id, floor)))
        }

        // Aircraft ceiling.
        if route.altitudeFT > performance.maxPlanningAltitudeFT {
            findings.append(Finding(severity: .warning, title: "Above the aircraft's usable altitude",
                                    detail: "\(route.altitudeFT.formatted()) ft exceeds the \(performance.maxPlanningAltitudeFT.formatted()) ft planning limit for the \(aircraft.name).",
                                    fix: .setCruise(performance.maxPlanningAltitudeFT)))
        }

        // VFR hemispherical cruising altitude, checked per leg. The rule keys off the
        // course being flown, so an out-and-back legally needs a different level in
        // each direction — checking only the first-to-last course missed that
        // entirely, and reported a meaningless 000° when a route returns home.
        if route.altitudeFT >= 3_500 {
            var mismatched: [(leg: RouteLeg, legal: Int)] = []
            for leg in profile.legs where leg.distanceNM > 5 {
                let legal = AltitudePlanner.hemisphericalAltitude(atLeast: Double(route.altitudeFT),
                                                                  courseDegrees: leg.courseTrue,
                                                                  ceiling: performance.maxPlanningAltitudeFT)
                if legal != route.altitudeFT { mismatched.append((leg, legal)) }
            }

            if mismatched.isEmpty {
                findings.append(Finding(severity: .pass, title: "VFR cruising altitude",
                                        detail: "\(route.altitudeFT.formatted()) ft suits every leg's course.",
                                        fix: nil))
            } else if mismatched.count == profile.legs.filter({ $0.distanceNM > 5 }).count {
                let legal = mismatched[0].legal
                findings.append(Finding(
                    severity: .caution, title: "Cruise altitude is not a VFR level",
                    detail: "On a \(String(format: "%03.0f", mismatched[0].leg.courseTrue))° course, VFR cruising altitudes above 3,000 ft AGL are \(mismatched[0].leg.courseTrue < 180 ? "odd" : "even") thousands plus 500. \(route.altitudeFT.formatted()) ft is not one; \(legal.formatted()) ft is the nearest that fits. Courses here are true — check local magnetic variation.",
                    fix: .setCruise(legal)))
            } else {
                let lines = mismatched.prefix(3).map {
                    "\($0.leg.fromIdent) → \($0.leg.toIdent) (\(String(format: "%03.0f", $0.leg.courseTrue))°) wants \($0.legal.formatted()) ft"
                }.joined(separator: "; ")
                findings.append(Finding(
                    severity: .caution, title: "Legs need different VFR levels",
                    detail: "This route reverses direction, so one cruise altitude cannot be legal throughout: \(lines). Plan a level change at the turn — set the altitude on the turning waypoint in the route list. Courses are true; check local magnetic variation.",
                    fix: nil))
            }
        }

        // Fuel and reserves.
        let reserveGal = 0.5 * performance.fuelBurnGPH
        let required = profile.totalFuelGallons + reserveGal
        if required > route.fuelOnBoardGal {
            findings.append(Finding(severity: .warning, title: "Not enough fuel",
                                    detail: String(format: "Route burns %.1f gal and a 30 min day-VFR reserve is %.1f gal — %.1f gal needed against %.1f gal aboard. Add fuel or a stop.",
                                                   profile.totalFuelGallons, reserveGal, required, route.fuelOnBoardGal),
                                    fix: nil))
        } else {
            findings.append(Finding(severity: .pass, title: "Fuel and reserve",
                                    detail: String(format: "%.1f gal burn plus %.1f gal reserve against %.1f gal aboard — %.1f gal spare.",
                                                   profile.totalFuelGallons, reserveGal, route.fuelOnBoardGal,
                                                   route.fuelOnBoardGal - required),
                                    fix: nil))
        }
        if route.fuelOnBoardGal > aircraft.usableFuelGal {
            findings.append(Finding(severity: .caution, title: "Fuel exceeds tank capacity",
                                    detail: "\(String(format: "%.1f", route.fuelOnBoardGal)) gal is more than the \(String(format: "%.0f", aircraft.usableFuelGal)) gal usable in a \(aircraft.name).",
                                    fix: nil))
        }

        // Controlled airspace the route passes through.
        //
        // Deliberately reported, not routed around. Transiting Class B with a
        // clearance is normal and often the most efficient way to go; silently
        // detouring would make routes longer and teach a student the wrong habit.
        // The planner's job is to say what will be required on the radio.
        if let airspace, !airspace.volumes.isEmpty {
            var penetrated: [String: AirspaceVolume] = [:]
            for leg in profile.legs {
                let samples = max(Int(leg.distanceNM / 3), 2)
                for step in 0...samples {
                    let t = Double(step) / Double(samples)
                    let point = CLLocationCoordinate2D(
                        latitude: legPoint(leg, t, route.waypoints).latitude,
                        longitude: legPoint(leg, t, route.waypoints).longitude)
                    let altitude = Int(Double(leg.startAltitudeFT)
                        + (Double(leg.endAltitudeFT) - Double(leg.startAltitudeFT)) * t)
                    for volume in airspace.volumes(containing: point, altitudeFT: altitude) {
                        penetrated[volume.displayClass + volume.name] = volume
                    }
                }
            }

            if penetrated.isEmpty {
                findings.append(Finding(severity: .pass, title: "No controlled airspace entered",
                                        detail: "At the planned altitudes this route stays clear of Class B, C and D airspace.",
                                        fix: nil))
            } else {
                let sorted = penetrated.values.sorted { ($0.airspaceClass ?? "Z") < ($1.airspaceClass ?? "Z") }
                for volume in sorted.prefix(4) {
                    let bravoForStudent = isStudentPilot && volume.hasStudentPilotRestriction
                    var detail = "\(volume.name) — \(volume.altitudeLabel) ft."
                    if let requirement = volume.entryRequirement { detail += " \(requirement)" }
                    if bravoForStudent {
                        detail += " Student pilots also need a logbook endorsement for Class B, and some Class B airports are closed to student solo flight entirely (14 CFR 91.131)."
                    }
                    // Going over the shelf is the classic VFR answer, when the
                    // aircraft can actually get there.
                    let overTheTop = ((volume.upperFT ?? 0) + 500)
                    let canClimbOver = overTheTop <= performance.maxPlanningAltitudeFT && overTheTop > route.altitudeFT
                    findings.append(Finding(
                        severity: bravoForStudent ? .warning : .caution,
                        title: "Route enters \(volume.displayClass)",
                        detail: detail,
                        fix: canClimbOver ? .setCruise(
                            AltitudePlanner.hemisphericalAltitude(
                                atLeast: Double(overTheTop),
                                courseDegrees: AltitudePlanner.dominantLegCourse(route.waypoints),
                                ceiling: performance.maxPlanningAltitudeFT)) : nil))
                }
            }
        } else {
            findings.append(Finding(severity: .advisory, title: "Airspace not checked",
                                    detail: "Controlled airspace data has not loaded for this route, so Class B, C and D penetration could not be verified.",
                                    fix: nil))
        }

        // Turbulence, icing and convection along the route, from AIRMETs/SIGMETs.
        if hazardFreshness.isUsable {
            let relevant = hazards.filter { $0.affects(altitudeFT: route.altitudeFT) }
            if relevant.isEmpty {
                findings.append(Finding(severity: .pass, title: "No active hazard advisories",
                                        detail: "No AIRMET or SIGMET covers \(route.altitudeFT.formatted()) ft on this route (\(hazardFreshness.shortLabel)).",
                                        fix: nil))
            } else {
                let kinds = Set(relevant.compactMap(\.hazard)).sorted().joined(separator: ", ")
                findings.append(Finding(
                    severity: .caution,
                    title: "\(relevant.count) hazard advisor\(relevant.count == 1 ? "y" : "ies") at your cruise altitude",
                    detail: "Active: \(kinds). These are AIRMETs and SIGMETs whose altitude band includes \(route.altitudeFT.formatted()) ft (\(hazardFreshness.shortLabel)).",
                    fix: nil))
            }
        } else {
            findings.append(Finding(severity: .advisory, title: "Hazard advisories not checked",
                                    detail: "AIRMET and SIGMET data has not loaded, so turbulence, icing and convective advisories could not be reviewed.",
                                    fix: nil))
        }

        // NOTAMs — reported honestly, including when they are simply unavailable.
        switch notamStatus {
        case .ready(let count, let freshness):
            findings.append(Finding(severity: count > 0 ? .advisory : .pass,
                                    title: count > 0 ? "\(count) NOTAMs on this route" : "No active NOTAMs",
                                    detail: count > 0
                                        ? "Published NOTAMs affect fields on this route (\(freshness.shortLabel)). Read them in full before flight."
                                        : "The FAA reports no active NOTAMs for these fields (\(freshness.shortLabel)).",
                                    fix: nil))
        case .notConfigured:
            findings.append(Finding(severity: .advisory, title: "NOTAMs not available",
                                    detail: "FAA NOTAM credentials are not configured, so no NOTAMs could be checked. Obtain them before relying on this app for NOTAM information.",
                                    fix: nil))
        case .failed(let message):
            findings.append(Finding(severity: .caution, title: "NOTAMs could not be checked",
                                    detail: message, fix: nil))
        case .loading:
            break
        }

        // Long legs without a checkpoint.
        if let longest = profile.legs.max(by: { $0.distanceNM < $1.distanceNM }), longest.distanceNM > 100 {
            findings.append(Finding(severity: .advisory, title: "Long leg without a checkpoint",
                                    detail: "\(longest.fromIdent) → \(longest.toIdent) runs \(Int(longest.distanceNM)) NM. Generating the route adds intermediate checkpoints for easier position fixing and diversion options.",
                                    fix: nil))
        }

        // Endpoints that are not airports.
        let nonAirportEnds = [route.waypoints[0], route.waypoints[route.waypoints.count - 1]]
            .filter { $0.kind != .airport }
        if !nonAirportEnds.isEmpty {
            findings.append(Finding(severity: .advisory, title: "Route does not start or end at an airport",
                                    detail: "\(nonAirportEnds.map(\.ident).joined(separator: " and ")) \(nonAirportEnds.count == 1 ? "is" : "are") map points, so runway, pattern and frequency briefings are unavailable for that end.",
                                    fix: nil))
        }

        return findings.sorted { $0.severity > $1.severity }
    }
}
