import SwiftUI
import MapKit

// MARK: - Candidate generation

/// An alternative routing the advisor can offer, together with why it exists and
/// what it costs relative to what the pilot has already built.
struct RouteCandidate: Identifiable {
    let id = UUID()
    let title: String
    let reason: String
    let iconName: String
    let tint: Color
    let waypoints: [Waypoint]

    var distanceNM: Double { AltitudePlanner.totalDistanceNM(waypoints) }

    func timeMinutes(performance: AircraftPerformance) -> Double {
        performance.cruiseKTAS > 0 ? (distanceNM / performance.cruiseKTAS) * 60 : 0
    }

    func fuelGallons(performance: AircraftPerformance) -> Double {
        (timeMinutes(performance: performance) / 60) * performance.fuelBurnGPH
    }

    /// Whether this routing can be flown on the fuel aboard with a day-VFR reserve.
    /// A shorter route is not automatically a better one if it cannot be reached.
    func isWithinFuelRange(performance: AircraftPerformance, fuelOnBoardGal: Double) -> Bool {
        let reserve = 0.5 * performance.fuelBurnGPH
        return fuelGallons(performance: performance) + reserve <= fuelOnBoardGal
    }
}

/// Builds routing alternatives from the route the pilot already has.
///
/// Everything here is derived from the route's own geometry and the bundled
/// airport table — no published airway or ATC-preferred-route data is available to
/// the app, so the advisor sticks to claims it can actually support: shortest
/// track, best visiting order, and a sensible en-route stop.
enum RouteAdvisor {

    static func candidates(for route: RoutePlan, airports: AirportCatalog) -> [RouteCandidate] {
        let waypoints = route.waypoints
        guard waypoints.count >= 2, let origin = waypoints.first, let destination = waypoints.last else {
            return []
        }

        var out: [RouteCandidate] = []

        out.append(RouteCandidate(
            title: "As planned",
            reason: "The route exactly as you built it.",
            iconName: "checkmark.circle.fill",
            tint: .green,
            waypoints: waypoints
        ))

        // Direct — drop every intermediate point. Skipped on an out-and-back, where
        // collapsing to the two ends leaves a zero-length route.
        let endsCoincide = AltitudePlanner.distanceNM(origin.coordinate, destination.coordinate) < 1
        if waypoints.count > 2 && !endsCoincide {
            out.append(RouteCandidate(
                title: "Direct",
                reason: "Straight from \(origin.ident) to \(destination.ident), skipping every intermediate point.",
                iconName: "arrow.right.to.line",
                tint: .blue,
                waypoints: [origin, destination]
            ))
        }

        // Best visiting order for the intermediate points, ends held fixed.
        if waypoints.count > 3 {
            let optimised = optimiseOrder(waypoints)
            let saving = AltitudePlanner.totalDistanceNM(waypoints) - AltitudePlanner.totalDistanceNM(optimised)
            if saving > 1, optimised.map(\.id) != waypoints.map(\.id) {
                out.append(RouteCandidate(
                    title: "Best order",
                    reason: String(format: "Same points, reordered — saves %.0f NM.", saving),
                    iconName: "arrow.triangle.swap",
                    tint: .purple,
                    waypoints: optimised
                ))
            }
        }

        // A fuel or comfort stop close to the existing track.
        if !endsCoincide,
           let stop = bestEnRouteStop(origin: origin, destination: destination,
                                      existing: waypoints, airports: airports) {
            var withStop = waypoints
            withStop.insert(stop.waypoint, at: stop.insertIndex)
            let added = AltitudePlanner.totalDistanceNM(withStop) - AltitudePlanner.totalDistanceNM(waypoints)
            out.append(RouteCandidate(
                title: "Via \(stop.waypoint.ident)",
                reason: String(format: "%@ sits %.0f NM off track — adds %.0f NM as a fuel or rest stop.",
                               stop.waypoint.name, stop.offTrackNM, max(added, 0)),
                iconName: "fuelpump.fill",
                tint: .orange,
                waypoints: withStop
            ))
        }

        // The return trip.
        out.append(RouteCandidate(
            title: "Reverse",
            reason: "Same route flown \(destination.ident) back to \(origin.ident).",
            iconName: "arrow.uturn.backward",
            tint: .cyan,
            waypoints: waypoints.reversed().map { wp in
                var copy = wp
                copy.id = UUID()   // fresh identity so the map redraws them as new points
                return copy
            }
        ))

        return out
    }

    /// Nearest-neighbour ordering of the intermediate points followed by a 2-opt
    /// pass. Both ends stay pinned — a route's departure and destination are not
    /// negotiable.
    private static func optimiseOrder(_ waypoints: [Waypoint]) -> [Waypoint] {
        guard waypoints.count > 3 else { return waypoints }
        let start = waypoints[0]
        let end = waypoints[waypoints.count - 1]
        var remaining = Array(waypoints[1..<(waypoints.count - 1)])

        var ordered: [Waypoint] = []
        var current = start
        while !remaining.isEmpty {
            var bestIndex = 0
            var bestDistance = Double.greatestFiniteMagnitude
            for (i, candidate) in remaining.enumerated() {
                let d = AltitudePlanner.distanceNM(current.coordinate, candidate.coordinate)
                if d < bestDistance { bestDistance = d; bestIndex = i }
            }
            current = remaining.remove(at: bestIndex)
            ordered.append(current)
        }

        var route = [start] + ordered + [end]
        var improved = true
        var guardCounter = 0
        while improved && guardCounter < 60 {
            improved = false
            guardCounter += 1
            for i in 1..<(route.count - 2) {
                for j in (i + 1)..<(route.count - 1) {
                    let before = AltitudePlanner.distanceNM(route[i - 1].coordinate, route[i].coordinate)
                        + AltitudePlanner.distanceNM(route[j].coordinate, route[j + 1].coordinate)
                    let after = AltitudePlanner.distanceNM(route[i - 1].coordinate, route[j].coordinate)
                        + AltitudePlanner.distanceNM(route[i].coordinate, route[j + 1].coordinate)
                    if after < before - 0.01 {
                        route[i...j].reverse()
                        improved = true
                    }
                }
            }
        }
        return route
    }

    private struct StopCandidate {
        let waypoint: Waypoint
        let offTrackNM: Double
        let insertIndex: Int
    }

    /// The airport closest to the existing track that is not already on the route
    /// and sits comfortably between the ends rather than beside one of them.
    private static func bestEnRouteStop(origin: Waypoint,
                                        destination: Waypoint,
                                        existing: [Waypoint],
                                        airports: AirportCatalog) -> StopCandidate? {
        let totalDistance = AltitudePlanner.distanceNM(origin.coordinate, destination.coordinate)
        guard totalDistance > 60 else { return nil }

        let used = Set(existing.compactMap(\.airportICAO))
        var best: StopCandidate?

        // Search a corridor around the midpoint instead of the whole database.
        let midpoint = CLLocationCoordinate2D(
            latitude: (origin.coordinate.latitude + destination.coordinate.latitude) / 2,
            longitude: (origin.coordinate.longitude + destination.coordinate.longitude) / 2)
        for airport in airports.nearby(midpoint, withinNM: totalDistance * 0.4,
                                       limit: 60, minimumType: 2)
        where !used.contains(airport.icao) {
            let toOrigin = AltitudePlanner.distanceNM(airport.coordinate, origin.coordinate)
            let toDest = AltitudePlanner.distanceNM(airport.coordinate, destination.coordinate)
            // Detour length stands in for perpendicular offset — cheap and adequate.
            let offTrack = (toOrigin + toDest) - totalDistance
            guard offTrack < totalDistance * 0.25 else { continue }
            // Keep it genuinely en route rather than in the circuit of either end.
            guard toOrigin > totalDistance * 0.25, toDest > totalDistance * 0.25 else { continue }

            if best == nil || offTrack < best!.offTrackNM {
                // Insert before whichever existing point it is closest to following.
                var insertIndex = existing.count - 1
                for (i, wp) in existing.enumerated() where i > 0 {
                    if AltitudePlanner.distanceNM(origin.coordinate, wp.coordinate) > toOrigin {
                        insertIndex = i
                        break
                    }
                }
                best = StopCandidate(waypoint: Waypoint(airport: airport),
                                     offTrackNM: offTrack,
                                     insertIndex: insertIndex)
            }
        }
        return best
    }
}
