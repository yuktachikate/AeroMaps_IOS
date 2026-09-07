import Foundation
import CoreLocation

// MARK: - Aircraft performance

/// The performance numbers the vertical profile is built from. Defaults are a
/// C172-class trainer, matching the aircraft the flight planner ships with.
struct AircraftPerformance: Equatable {
    var cruiseKTAS: Double = 120
    var climbRateFPM: Double = 700
    var climbKTAS: Double = 80
    var descentRateFPM: Double = 500
    var descentKTAS: Double = 130
    var fuelBurnGPH: Double = 8.5
    var serviceCeilingFT: Int = 14_000

    /// Highest altitude worth planning: VFR cruising tops out at 17,500 ft, and the
    /// airframe stops climbing before that.
    var maxPlanningAltitudeFT: Int { min(serviceCeilingFT, 17_500) }
}

// MARK: - Vertical profile

enum FlightPhase: String {
    case climb = "Climb"
    case cruise = "Cruise"
    case descent = "Descent"
    /// A leg long enough to climb, level off and come back down inside itself.
    case climbCruise = "Climb then cruise"
    case cruiseDescent = "Cruise then descent"
    case mixed = "Climb–cruise–descent"

    var symbolName: String {
        switch self {
        case .climb:         return "arrow.up.right"
        case .cruise:        return "arrow.right"
        case .descent:       return "arrow.down.right"
        case .climbCruise:   return "arrow.up.forward"
        case .cruiseDescent: return "arrow.down.forward"
        case .mixed:         return "arrow.up.and.down"
        }
    }

    var shortLabel: String {
        switch self {
        case .climb:         return "CLIMB"
        case .cruise:        return "CRUISE"
        case .descent:       return "DESCENT"
        case .climbCruise:   return "CLB/CRZ"
        case .cruiseDescent: return "CRZ/DES"
        case .mixed:         return "CLB/CRZ/DES"
        }
    }
}

/// One flown segment between two consecutive waypoints.
struct RouteLeg: Identifiable {
    var id: UUID { fromID }
    let fromID: UUID
    let fromIdent: String
    let toIdent: String
    let startDistanceNM: Double
    let distanceNM: Double
    let courseTrue: Double
    let startAltitudeFT: Int
    let endAltitudeFT: Int
    let phase: FlightPhase
    let timeMinutes: Double
    let fuelGallons: Double
    /// Average ground speed actually used to time this leg. Equal to TAS only when
    /// no forecast covered the leg — `windApplied` says which.
    var groundSpeedKT: Double = 0
    /// Distance-weighted mean headwind: positive into wind, negative with it.
    var headwindKT: Double = 0
    /// The mean wind the leg was flown against, for display.
    var windDirectionTrue: Double?
    var windSpeedKT: Double?
    /// False when the leg was timed in still air because no forecast covered it.
    /// Surfaced rather than hidden, so a still-air estimate is never shown as
    /// though it were wind-corrected.
    var windApplied: Bool = false
    /// Highest terrain sampled under this leg, when terrain data has loaded.
    let maxTerrainFT: Int?
    /// Smallest gap between the planned altitude and the ground anywhere along the
    /// leg, measured sample by sample and ignoring the few miles either side of an
    /// airport — an aircraft is *meant* to be at field elevation there, so counting
    /// those points would flag every normal departure and arrival.
    let minClearanceFT: Int?

    func hasTerrainConflict(minClearanceFT limit: Int) -> Bool {
        guard let clearance = minClearanceFT else { return false }
        return clearance < limit
    }
}

/// A point on the altitude-vs-distance graph.
struct ProfileSample {
    let distanceNM: Double
    let altitudeFT: Double
    let terrainFT: Double?
}

/// The computed vertical plan for a route: where the aircraft climbs, levels off
/// and descends, plus the per-leg numbers shown in the route list.
struct AltitudeProfile {
    var legs: [RouteLeg] = []
    var samples: [ProfileSample] = []
    /// Altitude assigned to each waypoint, keyed by waypoint id.
    var waypointAltitudes: [UUID: Int] = [:]
    /// Lowest altitude that still clears the terrain around each waypoint, keyed by
    /// waypoint id. Only present where terrain data has loaded.
    var waypointMinimumSafe: [UUID: Int] = [:]
    /// Waypoints whose suggested altitude had to be raised off the straight
    /// climb/descent line to clear terrain beneath them.
    var terrainRaisedWaypoints: Set<UUID> = []
    /// Whether each waypoint is crossed climbing, level or descending. A point early
    /// in the climb sits well below cruise no matter what cruise is set to, which is
    /// otherwise a confusing thing to read off a list of altitudes.
    var waypointPhases: [UUID: FlightPhase] = [:]
    var cruiseAltitudeFT: Int = 0
    var topOfClimbNM: Double = 0
    var topOfDescentNM: Double = 0
    var totalDistanceNM: Double = 0
    var totalTimeMinutes: Double = 0
    var totalFuelGallons: Double = 0
    var maxTerrainFT: Int?
    /// Highest altitude the profile actually reaches. Lower than the requested
    /// cruise when the route is too short to climb that high.
    var achievedAltitudeFT: Int = 0

    var isEmpty: Bool { legs.isEmpty }

    var conflictedLegs: [RouteLeg] {
        legs.filter { $0.hasTerrainConflict(minClearanceFT: AltitudeProfile.minimumClearanceFT) }
    }

    /// 1,000 ft is the VFR minimum over congested areas; the planner uses it as the
    /// floor for a terrain warning.
    static let minimumClearanceFT = 1_000
    /// What the auto-suggestion aims for — a comfortable pad over the highest rock.
    static let preferredClearanceFT = 2_000
}

// MARK: - Profile computation

enum AltitudePlanner {

    /// Builds the vertical profile for a route.
    ///
    /// Waypoints carrying a pilot-entered altitude act as hard anchors; everything
    /// between two anchors is flown as climb → (optional cruise plateau) → descent,
    /// which is how a real leg is flown when a crossing restriction is in play.
    static func computeProfile(waypoints: [Waypoint],
                               cruiseAltitudeFT: Int,
                               performance: AircraftPerformance,
                               terrain: TerrainSampler? = nil,
                               wind: WindField? = nil) -> AltitudeProfile {
        guard waypoints.count >= 2 else { return AltitudeProfile() }

        var profile = AltitudeProfile()
        profile.cruiseAltitudeFT = cruiseAltitudeFT

        // Cumulative along-track distance for every waypoint.
        var cumulative: [Double] = [0]
        for i in 1..<waypoints.count {
            cumulative.append(cumulative[i - 1] + distanceNM(waypoints[i - 1].coordinate, waypoints[i].coordinate))
        }
        let total = cumulative.last ?? 0
        profile.totalDistanceNM = total
        guard total > 0 else { return profile }

        // Anchors: the two ends always, plus any waypoint the pilot pinned.
        let departureFT = groundElevation(waypoints[0], terrain: terrain)
        let destinationFT = groundElevation(waypoints[waypoints.count - 1], terrain: terrain)

        var anchors: [(distance: Double, altitude: Double)] = [(0, Double(departureFT))]
        for (i, wp) in waypoints.enumerated() where i > 0 && i < waypoints.count - 1 {
            if let manual = wp.plannedAltitudeFT {
                anchors.append((cumulative[i], Double(manual)))
            }
        }
        anchors.append((total, Double(destinationFT)))

        // Expand each anchor-to-anchor span into climb / plateau / descent.
        func buildCurve(_ anchors: [(distance: Double, altitude: Double)]) -> [(distance: Double, altitude: Double)] {
            var curve: [(distance: Double, altitude: Double)] = []
            for i in 0..<(anchors.count - 1) {
                let a = anchors[i], b = anchors[i + 1]
                curve.append(a)
                let span = b.distance - a.distance
                guard span > 0 else { continue }

                let ceiling = Double(min(cruiseAltitudeFT, performance.maxPlanningAltitudeFT))
                guard ceiling > max(a.altitude, b.altitude) else { continue }

                let climbNM = horizontalDistance(deltaFT: ceiling - a.altitude,
                                                 rateFPM: performance.climbRateFPM,
                                                 speedKT: performance.climbKTAS)
                let descentNM = horizontalDistance(deltaFT: ceiling - b.altitude,
                                                   rateFPM: performance.descentRateFPM,
                                                   speedKT: performance.descentKTAS)

                if climbNM + descentNM <= span {
                    curve.append((a.distance + climbNM, ceiling))
                    curve.append((b.distance - descentNM, ceiling))
                } else {
                    // Too short to reach cruise: fly a peak where climb and descent meet.
                    let gradientUp = (ceiling - a.altitude) / max(climbNM, 0.001)
                    let gradientDown = (ceiling - b.altitude) / max(descentNM, 0.001)
                    let peakOffset = (gradientDown * span + a.altitude - b.altitude) / (gradientUp + gradientDown)
                    let clamped = min(max(peakOffset, 0), span)
                    let peakAltitude = a.altitude + gradientUp * clamped
                    if peakAltitude > max(a.altitude, b.altitude) + 50 {
                        curve.append((a.distance + clamped, peakAltitude))
                    }
                }
            }
            curve.append(anchors[anchors.count - 1])
            return curve.sorted { $0.distance < $1.distance }
        }

        var curve = buildCurve(anchors)

        // Each waypoint gets its own minimum safe altitude from the terrain around
        // it. Where the straight climb/descent line would cross a waypoint below
        // that floor, the waypoint is promoted to an anchor at its minimum and the
        // curve is rebuilt — so a fix sitting on a ridge raises the profile locally
        // rather than being quietly flown into the hill.
        if let terrain {
            for (i, wp) in waypoints.enumerated() {
                guard let ground = localTerrainCeilingFT(around: cumulative[i],
                                                         waypoints: waypoints,
                                                         cumulative: cumulative,
                                                         terrain: terrain) else { continue }
                let floor = wp.kind == .airport && (i == 0 || i == waypoints.count - 1)
                    ? Double(wp.fieldElevationFT ?? Int(ground))
                    : ground + Double(AltitudeProfile.preferredClearanceFT)
                profile.waypointMinimumSafe[wp.id] = Int(floor.rounded())
            }

            var promoted = anchors
            var changed = false
            for (i, wp) in waypoints.enumerated() where i > 0 && i < waypoints.count - 1 {
                guard wp.plannedAltitudeFT == nil,
                      let floor = profile.waypointMinimumSafe[wp.id] else { continue }
                let planned = interpolate(curve, at: cumulative[i])
                if planned < Double(floor) - 1 {
                    promoted.append((cumulative[i], Double(min(floor, performance.maxPlanningAltitudeFT))))
                    profile.terrainRaisedWaypoints.insert(wp.id)
                    changed = true
                }
            }
            if changed {
                promoted.sort { $0.distance < $1.distance }
                curve = buildCurve(promoted)
            }
        }

        func altitude(at d: Double) -> Double { interpolate(curve, at: d) }

        // Top of climb / top of descent, taken from the altitude the profile actually
        // reaches. A route too short to make the requested cruise still has a real
        // level-off point, and reporting the requested altitude's (never reached)
        // crossing would put both markers at the destination.
        let peakAltitude = curve.map(\.altitude).max() ?? 0
        profile.topOfClimbNM = curve.first(where: { $0.altitude >= peakAltitude - 1 })?.distance ?? 0
        profile.topOfDescentNM = curve.last(where: { $0.altitude >= peakAltitude - 1 })?.distance ?? total
        profile.achievedAltitudeFT = Int(peakAltitude.rounded())

        // Assign each waypoint its altitude, and record whether it is crossed on the
        // way up, level, or on the way down.
        for (i, wp) in waypoints.enumerated() {
            profile.waypointAltitudes[wp.id] = wp.plannedAltitudeFT ?? Int(altitude(at: cumulative[i]).rounded())
            let d = cumulative[i]
            let before = altitude(at: max(d - 1, 0))
            let after = altitude(at: min(d + 1, total))
            if after - before > 30 { profile.waypointPhases[wp.id] = .climb }
            else if before - after > 30 { profile.waypointPhases[wp.id] = .descent }
            else { profile.waypointPhases[wp.id] = .cruise }
        }

        // Sample the curve (and terrain under it) for the profile chart.
        let sampleCount = 160
        var maxTerrain: Double = -.greatestFiniteMagnitude
        for i in 0...sampleCount {
            let d = total * Double(i) / Double(sampleCount)
            let coord = coordinate(along: waypoints, cumulative: cumulative, atDistance: d)
            let ground = terrain?.elevationFT(at: coord)
            if let ground { maxTerrain = max(maxTerrain, ground) }
            profile.samples.append(ProfileSample(distanceNM: d, altitudeFT: altitude(at: d), terrainFT: ground))
        }
        if maxTerrain > -.greatestFiniteMagnitude { profile.maxTerrainFT = Int(maxTerrain.rounded()) }

        // Per-leg numbers.
        for i in 0..<(waypoints.count - 1) {
            let start = cumulative[i], end = cumulative[i + 1]
            let legDistance = end - start
            let startAlt = profile.waypointAltitudes[waypoints[i].id] ?? 0
            let endAlt = profile.waypointAltitudes[waypoints[i + 1].id] ?? 0

            // Integrate time and fuel over the leg rather than pricing the whole
            // thing at one speed. A 300 NM leg climbs for the first few minutes and
            // cruises for the rest; charging all of it at climb speed overstated the
            // time by a third.
            let steps = 24
            var minutes = 0.0
            var fuel = 0.0
            var climbNM = 0.0, cruiseNM = 0.0, descentNM = 0.0
            // Wind accumulators, distance-weighted so a short climb segment in a
            // different layer cannot outvote the long cruise segment.
            var headwindNM = 0.0, windVectorX = 0.0, windVectorY = 0.0, windedNM = 0.0
            let legCourse = bearingDegrees(from: waypoints[i].coordinate,
                                           to: waypoints[i + 1].coordinate)
            for step in 0..<steps {
                let d0 = start + legDistance * Double(step) / Double(steps)
                let d1 = start + legDistance * Double(step + 1) / Double(steps)
                let segmentNM = d1 - d0
                guard segmentNM > 0 else { continue }
                let deltaFT = altitude(at: d1) - altitude(at: d0)

                let segmentPhase: FlightPhase
                if deltaFT > 20 { segmentPhase = .climb; climbNM += segmentNM }
                else if deltaFT < -20 { segmentPhase = .descent; descentNM += segmentNM }
                else { segmentPhase = .cruise; cruiseNM += segmentNM }

                let speed: Double
                let burnFactor: Double
                switch segmentPhase {
                case .climb:   speed = performance.climbKTAS;   burnFactor = 1.25
                case .descent: speed = performance.descentKTAS; burnFactor = 0.70
                default:       speed = performance.cruiseKTAS;  burnFactor = 1.00
                }
                guard speed > 0 else { continue }

                // Fuel burns per hour in the air, so wind cannot change the rate —
                // but it changes how many hours the leg takes, and the fuel follows
                // from that. Timing on ground speed is the whole correction.
                var groundSpeed = speed
                if let wind {
                    let midAltitude = (altitude(at: d0) + altitude(at: d1)) / 2
                    let midCoord = coordinate(along: waypoints, cumulative: cumulative,
                                              atDistance: (d0 + d1) / 2)
                    if let w = wind.wind(at: midCoord, altitudeFT: midAltitude) {
                        let solution = WindTriangle.solve(courseTrue: legCourse,
                                                          trueAirspeedKT: speed,
                                                          windFromTrue: w.directionTrue,
                                                          windSpeedKT: w.speedKT)
                        // A ground speed at or near zero means the aircraft cannot
                        // make the track at all. Floor it so the leg reports an
                        // enormous time rather than dividing by zero; the validator
                        // is what turns that into a readable warning.
                        groundSpeed = max(solution.groundSpeedKT, 1)
                        headwindNM += solution.headwindKT * segmentNM
                        let r = w.directionTrue * .pi / 180
                        windVectorX += cos(r) * w.speedKT * segmentNM
                        windVectorY += sin(r) * w.speedKT * segmentNM
                        windedNM += segmentNM
                    }
                }

                let segmentMinutes = (segmentNM / groundSpeed) * 60
                minutes += segmentMinutes
                fuel += (segmentMinutes / 60) * performance.fuelBurnGPH * burnFactor
            }

            // Name every phase the leg actually contains. Labelling only the
            // dominant one hid the climb inside a long leg that was mostly cruise,
            // which read as though the aircraft never left field elevation.
            let threshold = max(legDistance * 0.02, 0.5)
            let phase: FlightPhase
            switch (climbNM > threshold, cruiseNM > threshold, descentNM > threshold) {
            case (true, _, true):      phase = .mixed
            case (true, true, false):  phase = .climbCruise
            case (false, true, true):  phase = .cruiseDescent
            case (true, false, false): phase = .climb
            case (false, false, true): phase = .descent
            default:                   phase = .cruise
            }

            var legTerrain: Int?
            var legClearance: Int?
            if let terrain {
                var peak = -Double.greatestFiniteMagnitude
                var worstClearance = Double.greatestFiniteMagnitude
                for step in 0...24 {
                    let d = start + legDistance * Double(step) / 24
                    let coord = coordinate(along: waypoints, cumulative: cumulative, atDistance: d)
                    guard let ground = terrain.elevationFT(at: coord) else { continue }
                    peak = max(peak, ground)
                    // Skip the airport environment at either end of the leg.
                    if isNearAirport(distance: d, waypoints: waypoints, cumulative: cumulative) { continue }
                    worstClearance = min(worstClearance, altitude(at: d) - ground)
                }
                if peak > -.greatestFiniteMagnitude { legTerrain = Int(peak.rounded()) }
                if worstClearance < .greatestFiniteMagnitude { legClearance = Int(worstClearance.rounded()) }
            }

            profile.legs.append(RouteLeg(
                fromID: waypoints[i].id,
                fromIdent: waypoints[i].ident,
                toIdent: waypoints[i + 1].ident,
                startDistanceNM: start,
                distanceNM: legDistance,
                courseTrue: legCourse,
                startAltitudeFT: startAlt,
                endAltitudeFT: endAlt,
                phase: phase,
                timeMinutes: minutes,
                fuelGallons: fuel,
                groundSpeedKT: minutes > 0 ? legDistance / (minutes / 60) : 0,
                headwindKT: windedNM > 0 ? headwindNM / windedNM : 0,
                windDirectionTrue: windedNM > 0
                    ? WindTriangle.normalized(atan2(windVectorY, windVectorX) * 180 / .pi) : nil,
                windSpeedKT: windedNM > 0
                    ? sqrt(windVectorX * windVectorX + windVectorY * windVectorY) / windedNM : nil,
                windApplied: windedNM > 0,
                maxTerrainFT: legTerrain,
                minClearanceFT: legClearance
            ))
        }

        profile.totalTimeMinutes = profile.legs.reduce(0) { $0 + $1.timeMinutes }
        profile.totalFuelGallons = profile.legs.reduce(0) { $0 + $1.fuelGallons }
        return profile
    }

    // MARK: Cruise altitude suggestion

    struct CruiseSuggestion {
        let altitudeFT: Int
        let rationale: String
    }

    /// Picks a cruise altitude the way a pilot would: clear the terrain by a
    /// comfortable margin, stay inside the aircraft's usable range, keep short hops
    /// low, and land on a VFR hemispherical cruising level for the route's course.
    static func suggestCruiseAltitude(waypoints: [Waypoint],
                                      performance: AircraftPerformance,
                                      terrain: TerrainSampler?) -> CruiseSuggestion? {
        guard waypoints.count >= 2 else { return nil }

        let distance = totalDistanceNM(waypoints)
        var reasons: [String] = []

        // Terrain floor.
        var floor = Double(AltitudeProfile.preferredClearanceFT)
        if let terrain, let peak = terrain.peakElevationFT(along: waypoints) {
            floor = peak + Double(AltitudeProfile.preferredClearanceFT)
            reasons.append("\(Int(peak).formatted()) ft peak terrain + \(AltitudeProfile.preferredClearanceFT.formatted()) ft clearance")
        } else {
            let fieldPeak = waypoints.compactMap { $0.fieldElevationFT }.max() ?? 0
            floor = Double(fieldPeak + AltitudeProfile.preferredClearanceFT)
            reasons.append("field elevations + \(AltitudeProfile.preferredClearanceFT.formatted()) ft clearance")
        }

        // Efficiency floor: climbing high for a short hop wastes more than it saves.
        let efficient: Double
        switch distance {
        case ..<25:   efficient = 2_500;  reasons.append("short \(Int(distance)) NM hop stays low")
        case ..<75:   efficient = 4_500
        case ..<150:  efficient = 6_500
        case ..<300:  efficient = 8_500
        default:      efficient = 10_500
        }

        var target = max(floor, efficient)
        target = min(target, Double(performance.maxPlanningAltitudeFT))

        // The hemispherical rule keys off the course being flown. On a route that
        // returns to where it started, first-to-last is a zero-length line and its
        // "course" is noise — so key off the longest leg, which is the altitude the
        // aircraft spends most of its time at.
        let course = dominantLegCourse(waypoints)
        let altitude = hemisphericalAltitude(atLeast: target, courseDegrees: course,
                                             ceiling: performance.maxPlanningAltitudeFT)
        reasons.append(String(format: "VFR hemispherical rule for the longest leg's %03.0f° course", course))

        return CruiseSuggestion(altitudeFT: altitude, rationale: reasons.joined(separator: ", "))
    }

    /// Course of the longest leg — the one that governs the cruising altitude.
    static func dominantLegCourse(_ waypoints: [Waypoint]) -> Double {
        guard waypoints.count >= 2 else { return 0 }
        var best = (distance: -1.0, course: 0.0)
        for i in 1..<waypoints.count {
            let d = distanceNM(waypoints[i - 1].coordinate, waypoints[i].coordinate)
            if d > best.distance {
                best = (d, bearingDegrees(from: waypoints[i - 1].coordinate, to: waypoints[i].coordinate))
            }
        }
        return best.course
    }

    /// VFR cruising altitudes: easterly courses (0–179°) fly odd thousands + 500,
    /// westerly courses (180–359°) fly even thousands + 500. Courses are true here;
    /// the regulation is written against magnetic, so the UI says so.
    static func hemisphericalAltitude(atLeast minimum: Double, courseDegrees: Double, ceiling: Int) -> Int {
        let eastbound = courseDegrees < 180
        // Start below the target, not at ceil(target): for a floor of 11,268 ft the
        // legal 11,500 ft level sits inside the 11,000s, and starting at 12 skipped
        // straight past it to 13,500 — 2,000 ft higher than the route needed.
        var thousands = max(Int(floor(max(minimum, 3_500) / 1_000)), 3)
        for _ in 0..<40 {
            let isOdd = thousands % 2 != 0
            if isOdd == eastbound {
                let candidate = thousands * 1_000 + 500
                if Double(candidate) >= minimum && candidate <= ceiling { return candidate }
                if candidate > ceiling { break }
            }
            thousands += 1
        }
        // Nothing legal fits under the ceiling — fall back to the highest that does.
        return max(1_500, (ceiling / 1_000) * 1_000 + 500 - 1_000)
    }

    // MARK: Geometry helpers

    static func totalDistanceNM(_ waypoints: [Waypoint]) -> Double {
        guard waypoints.count >= 2 else { return 0 }
        return (1..<waypoints.count).reduce(0.0) {
            $0 + distanceNM(waypoints[$1 - 1].coordinate, waypoints[$1].coordinate)
        }
    }

    static func distanceNM(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let earthRadiusNM = 3_440.065
        func rad(_ d: Double) -> Double { d * .pi / 180 }
        let dLat = rad(b.latitude - a.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let la1 = rad(a.latitude), la2 = rad(b.latitude)
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadiusNM * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    static func bearingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        func rad(_ d: Double) -> Double { d * .pi / 180 }
        let lat1 = rad(from.latitude), lat2 = rad(to.latitude)
        let dLon = rad(to.longitude - from.longitude)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi).truncatingRemainder(dividingBy: 360) + (atan2(y, x) < 0 ? 360 : 0)
    }

    /// Horizontal distance covered while changing altitude by `deltaFT`.
    private static func horizontalDistance(deltaFT: Double, rateFPM: Double, speedKT: Double) -> Double {
        guard deltaFT > 0, rateFPM > 0 else { return 0 }
        return (deltaFT / rateFPM) * (speedKT / 60)
    }

    /// Highest ground within 5 NM either side of a point on the route — the terrain
    /// a waypoint has to clear, rather than the single sample directly beneath it.
    private static func localTerrainCeilingFT(around distance: Double,
                                              waypoints: [Waypoint],
                                              cumulative: [Double],
                                              terrain: TerrainSampler) -> Double? {
        var peak = -Double.greatestFiniteMagnitude
        for offset in stride(from: -5.0, through: 5.0, by: 1.0) {
            let d = distance + offset
            guard d >= 0, d <= (cumulative.last ?? 0) else { continue }
            let coord = coordinate(along: waypoints, cumulative: cumulative, atDistance: d)
            if let g = terrain.elevationFT(at: coord) { peak = max(peak, g) }
        }
        return peak > -.greatestFiniteMagnitude ? peak : nil
    }

    /// True within 4 NM of a waypoint that is an airport — the departure, arrival
    /// and any en-route field, where being close to the ground is the point.
    private static func isNearAirport(distance: Double,
                                      waypoints: [Waypoint],
                                      cumulative: [Double]) -> Bool {
        for (i, wp) in waypoints.enumerated() where wp.kind == .airport {
            if abs(cumulative[i] - distance) < 4 { return true }
        }
        // Both ends always count, airport or not: you start and finish on the ground.
        if distance < 4 { return true }
        if let total = cumulative.last, total - distance < 4 { return true }
        return false
    }

    private static func groundElevation(_ wp: Waypoint, terrain: TerrainSampler?) -> Int {
        if let field = wp.fieldElevationFT { return field }
        if let ground = terrain?.elevationFT(at: wp.coordinate) { return Int(ground.rounded()) }
        return 0
    }

    private static func interpolate(_ curve: [(distance: Double, altitude: Double)], at d: Double) -> Double {
        guard let first = curve.first, let last = curve.last else { return 0 }
        if d <= first.distance { return first.altitude }
        if d >= last.distance { return last.altitude }
        for i in 1..<curve.count where curve[i].distance >= d {
            let a = curve[i - 1], b = curve[i]
            let span = b.distance - a.distance
            guard span > 0 else { return b.altitude }
            let t = (d - a.distance) / span
            return a.altitude + (b.altitude - a.altitude) * t
        }
        return last.altitude
    }

    /// The coordinate `distance` NM along the route, interpolated within its leg.
    static func coordinate(along waypoints: [Waypoint],
                           cumulative: [Double],
                           atDistance distance: Double) -> CLLocationCoordinate2D {
        guard let first = waypoints.first else { return CLLocationCoordinate2D() }
        if distance <= 0 { return first.coordinate }
        for i in 1..<waypoints.count where cumulative[i] >= distance {
            let span = cumulative[i] - cumulative[i - 1]
            guard span > 0 else { return waypoints[i].coordinate }
            let t = (distance - cumulative[i - 1]) / span
            let a = waypoints[i - 1].coordinate, b = waypoints[i].coordinate
            return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                          longitude: a.longitude + (b.longitude - a.longitude) * t)
        }
        return waypoints[waypoints.count - 1].coordinate
    }
}
