import Foundation
import CoreLocation

/// The record of a flight actually flown.
///
/// A plan describes what you intended; this describes what happened. They diverge
/// constantly — ATC turns you, weather pushes you, a runway assignment changes the
/// arrival — and the difference is the part worth keeping. A route on its own gets
/// edited afterwards and the history is gone, so the plan is snapshotted here at
/// the moment the flight starts and never touched again.
///
/// Everything is `Codable` and stored as plain JSON on disk. There is no server:
/// the log belongs to the pilot and stays on their device.

// MARK: - Track

/// One fix along the path actually flown.
struct TrackPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let altitudeFT: Double
    let groundSpeedKT: Double
    let time: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A waypoint frozen at the moment the flight began.
///
/// Separate from `Waypoint` because that type carries a fresh `UUID` and a
/// `CLLocationCoordinate2D`, neither of which round-trips through JSON usefully,
/// and because a record must not change when the live route is edited later.
struct PlannedPoint: Codable, Hashable, Identifiable {
    var id: String { ident + "\(latitude)" }
    let ident: String
    let name: String
    let latitude: Double
    let longitude: Double
    let plannedAltitudeFT: Int?
    let isStop: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ waypoint: Waypoint, altitudeFT: Int?) {
        ident = waypoint.ident
        name = waypoint.name
        latitude = waypoint.coordinate.latitude
        longitude = waypoint.coordinate.longitude
        plannedAltitudeFT = altitudeFT
        isStop = waypoint.isStop
    }
}

// MARK: - Amendments

/// A change made to the route after the flight had already started.
///
/// Recorded rather than applied silently, because "why did we end up going that
/// way?" is a question worth being able to answer on the ground afterwards — and
/// because an amendment is the thing that invalidates the fuel plan.
struct RouteAmendment: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case runwayAssigned
        case destinationChanged
        case waypointAdded
        case waypointRemoved
        case fuelStopAdded

        var label: String {
            switch self {
            case .runwayAssigned:     return "Runway assigned"
            case .destinationChanged: return "Destination changed"
            case .waypointAdded:      return "Waypoint added"
            case .waypointRemoved:    return "Waypoint removed"
            case .fuelStopAdded:      return "Fuel stop added"
            }
        }

        var symbolName: String {
            switch self {
            case .runwayAssigned:     return "airplane.arrival"
            case .destinationChanged: return "arrow.triangle.branch"
            case .waypointAdded:      return "plus.circle"
            case .waypointRemoved:    return "minus.circle"
            case .fuelStopAdded:      return "fuelpump"
            }
        }
    }

    var id = UUID()
    let kind: Kind
    let time: Date
    let summary: String
    /// Remaining distance and fuel as re-estimated at the moment of the change.
    var remainingNM: Double?
    var remainingFuelGal: Double?
}

// MARK: - The record

struct FlightRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date?

    var aircraftID: String
    var aircraftName: String

    /// The plan as filed, frozen.
    var plannedPoints: [PlannedPoint]
    var plannedCruiseFT: Int
    var plannedDistanceNM: Double
    var plannedTimeMinutes: Double
    var plannedFuelGallons: Double
    var fuelOnBoardAtStartGal: Double

    var track: [TrackPoint] = []
    /// Checklist items ticked during this flight, by item id.
    var checklistCompleted: [String] = []
    var amendments: [RouteAmendment] = []
    var notes: String = ""

    var routeName: String {
        guard let first = plannedPoints.first, let last = plannedPoints.last else { return "Flight" }
        return plannedPoints.count == 1 ? first.ident : "\(first.ident) → \(last.ident)"
    }

    var isComplete: Bool { endedAt != nil }

    /// Wall-clock time from start to finish, or to now if still airborne.
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }

    /// Distance actually covered over the ground, summed fix to fix.
    var actualDistanceNM: Double {
        guard track.count >= 2 else { return 0 }
        return (1..<track.count).reduce(0.0) {
            $0 + AltitudePlanner.distanceNM(track[$1 - 1].coordinate, track[$1].coordinate)
        }
    }

    var maxAltitudeFT: Double { track.map(\.altitudeFT).max() ?? 0 }

    /// How far the flight strayed from the planned track, measured as the
    /// perpendicular distance from each fix to the nearest planned leg.
    var deviation: (max: Double, mean: Double) {
        guard plannedPoints.count >= 2, !track.isEmpty else { return (0, 0) }
        var worst = 0.0
        var total = 0.0
        for point in track {
            var best = Double.greatestFiniteMagnitude
            for i in 1..<plannedPoints.count {
                best = min(best, Self.crossTrackNM(point: point.coordinate,
                                                   from: plannedPoints[i - 1].coordinate,
                                                   to: plannedPoints[i].coordinate))
            }
            worst = max(worst, best)
            total += best
        }
        return (worst, total / Double(track.count))
    }

    /// Perpendicular distance from a point to a leg, clamped to the leg's ends so a
    /// fix beyond the last waypoint measures to that waypoint rather than to an
    /// imaginary extension of the track.
    static func crossTrackNM(point: CLLocationCoordinate2D,
                             from a: CLLocationCoordinate2D,
                             to b: CLLocationCoordinate2D) -> Double {
        // Flat-earth projection: over a single leg the error is far below the
        // precision this figure is ever read at.
        let latScale = 60.0
        let lonScale = 60.0 * cos(a.latitude * .pi / 180)
        let ax = 0.0, ay = 0.0
        let bx = (b.longitude - a.longitude) * lonScale
        let by = (b.latitude - a.latitude) * latScale
        let px = (point.longitude - a.longitude) * lonScale
        let py = (point.latitude - a.latitude) * latScale

        let dx = bx - ax, dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return sqrt(px * px + py * py) }
        let t = max(0, min(1, (px * dx + py * dy) / lengthSquared))
        let cx = t * dx, cy = t * dy
        return sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
    }
}

// MARK: - Fuel in flight

/// Re-estimates fuel from how long the engine has actually been running.
///
/// Deliberately simple and deliberately labelled as an estimate: it burns the
/// aircraft's planned rate against elapsed time. It is not a fuel totaliser and
/// cannot see the mixture, so it is a planning aid for the question "can I still
/// make it after that reroute?" — not an authority on what is in the tanks.
enum FuelEstimator {
    struct Estimate {
        let burnedGal: Double
        let remainingGal: Double
        let requiredGal: Double
        let reserveGal: Double
        /// Fuel left once the rest of the route and its reserve are flown.
        var marginGal: Double { remainingGal - requiredGal - reserveGal }
        var isSufficient: Bool { marginGal >= 0 }
        /// Endurance left at the planned burn, in minutes.
        let enduranceMinutes: Double
    }

    static func estimate(elapsed: TimeInterval,
                         startedWithGal: Double,
                         burnGPH: Double,
                         remainingRouteFuelGal: Double,
                         reserveMinutes: Double = 30) -> Estimate {
        let hours = max(elapsed, 0) / 3600
        let burned = hours * burnGPH
        let remaining = max(startedWithGal - burned, 0)
        let reserve = (reserveMinutes / 60) * burnGPH
        return Estimate(burnedGal: burned,
                        remainingGal: remaining,
                        requiredGal: remainingRouteFuelGal,
                        reserveGal: reserve,
                        enduranceMinutes: burnGPH > 0 ? (remaining / burnGPH) * 60 : 0)
    }
}

// MARK: - The log

/// Every flight this device has recorded, persisted as JSON.
final class FlightLog: ObservableObject {
    @Published private(set) var records: [FlightRecord] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("AeroMaps-flights.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([FlightRecord].self, from: data) else { return }
        records = decoded.sorted { $0.startedAt > $1.startedAt }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func upsert(_ record: FlightRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.insert(record, at: 0)
        }
        save()
    }

    func delete(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    var totalHours: Double {
        records.filter(\.isComplete).reduce(0) { $0 + $1.duration } / 3600
    }
}
