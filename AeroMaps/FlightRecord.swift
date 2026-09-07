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
    /// Tail number. A logbook entry without it identifies a *type*, not the
    /// aircraft that was flown, which is most of the point of keeping one.
    var registration: String = ""

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

    // MARK: Decoding

    /// Decoded field by field, tolerating anything the key is missing for.
    ///
    /// Swift's synthesised Codable does *not* fall back to a property's default
    /// value — it calls `decode` and throws `keyNotFound`. So adding one new
    /// non-optional property, even with a default, makes every previously saved
    /// record fail to decode. That happened: adding `registration` silently emptied
    /// the whole logbook, while the flights sat intact on disk and unreadable.
    ///
    /// A log has to survive its own schema changing, so every field here is
    /// optional at the boundary and falls back to the value a new record would have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        // The one genuinely required field: a flight with no start time is not a
        // record of anything.
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        aircraftID = try c.decodeIfPresent(String.self, forKey: .aircraftID) ?? ""
        aircraftName = try c.decodeIfPresent(String.self, forKey: .aircraftName) ?? "Unknown aircraft"
        registration = try c.decodeIfPresent(String.self, forKey: .registration) ?? ""
        plannedPoints = try c.decodeIfPresent([PlannedPoint].self, forKey: .plannedPoints) ?? []
        plannedCruiseFT = try c.decodeIfPresent(Int.self, forKey: .plannedCruiseFT) ?? 0
        plannedDistanceNM = try c.decodeIfPresent(Double.self, forKey: .plannedDistanceNM) ?? 0
        plannedTimeMinutes = try c.decodeIfPresent(Double.self, forKey: .plannedTimeMinutes) ?? 0
        plannedFuelGallons = try c.decodeIfPresent(Double.self, forKey: .plannedFuelGallons) ?? 0
        fuelOnBoardAtStartGal = try c.decodeIfPresent(Double.self, forKey: .fuelOnBoardAtStartGal) ?? 0
        track = try c.decodeIfPresent([TrackPoint].self, forKey: .track) ?? []
        checklistCompleted = try c.decodeIfPresent([String].self, forKey: .checklistCompleted) ?? []
        amendments = try c.decodeIfPresent([RouteAmendment].self, forKey: .amendments) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil,
         aircraftID: String, aircraftName: String, registration: String = "",
         plannedPoints: [PlannedPoint], plannedCruiseFT: Int,
         plannedDistanceNM: Double, plannedTimeMinutes: Double,
         plannedFuelGallons: Double, fuelOnBoardAtStartGal: Double,
         track: [TrackPoint] = [], checklistCompleted: [String] = [],
         amendments: [RouteAmendment] = [], notes: String = "") {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.aircraftID = aircraftID
        self.aircraftName = aircraftName
        self.registration = registration
        self.plannedPoints = plannedPoints
        self.plannedCruiseFT = plannedCruiseFT
        self.plannedDistanceNM = plannedDistanceNM
        self.plannedTimeMinutes = plannedTimeMinutes
        self.plannedFuelGallons = plannedFuelGallons
        self.fuelOnBoardAtStartGal = fuelOnBoardAtStartGal
        self.track = track
        self.checklistCompleted = checklistCompleted
        self.amendments = amendments
        self.notes = notes
    }

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

    /// Landings made: one per planned stop, plus the arrival.
    ///
    /// Counted from the plan rather than detected from the track, because a
    /// touch-and-go and a low pass look identical in a 5-second GPS trace and
    /// guessing between them would put a wrong number in a logbook.
    var landings: Int {
        guard isComplete, plannedPoints.count >= 2 else { return 0 }
        return plannedPoints.dropFirst().dropLast().filter(\.isStop).count + 1
    }

    /// Time the aircraft was actually moving, as distinct from the wall-clock time
    /// the recording was open. Engine-on to engine-off includes taxi and any time
    /// sat at a stop; this counts only fixes with the aircraft in motion.
    var airborneMinutes: Double {
        guard track.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<track.count {
            let gap = track[i].time.timeIntervalSince(track[i - 1].time)
            // A long gap means the recording paused, not that the leg took an hour.
            guard gap > 0, gap < 120 else { continue }
            if track[i].groundSpeedKT > 30 { total += gap }
        }
        return total / 60
    }

    /// Ground speed actually achieved. Captured on every fix and, until now, never
    /// looked at — which is a shame, because the gap between this and the planned
    /// true airspeed is the wind, measured rather than forecast.
    var groundSpeed: (average: Double, max: Double)? {
        let moving = track.filter { $0.groundSpeedKT > 30 }
        guard !moving.isEmpty else { return nil }
        let speeds = moving.map(\.groundSpeedKT)
        return (speeds.reduce(0, +) / Double(speeds.count), speeds.max() ?? 0)
    }

    /// Altitude actually flown, sampled against distance along the track, for
    /// drawing beside the planned profile.
    var altitudeTrace: [(distanceNM: Double, altitudeFT: Double)] {
        guard track.count >= 2 else { return [] }
        var out: [(Double, Double)] = [(0, track[0].altitudeFT)]
        var run = 0.0
        for i in 1..<track.count {
            run += AltitudePlanner.distanceNM(track[i - 1].coordinate, track[i].coordinate)
            out.append((run, track[i].altitudeFT))
        }
        return out.map { (distanceNM: $0.0, altitudeFT: $0.1) }
    }

    /// How far the aircraft ever got from where recording started.
    ///
    /// Measured from the first fix rather than summed along the track, because GPS
    /// jitter on a stationary aircraft accumulates into a surprisingly large total
    /// distance while going nowhere at all.
    var trackSpreadNM: Double {
        guard let first = track.first else { return 0 }
        return track.reduce(0) { max($0, AltitudePlanner.distanceNM(first.coordinate, $1.coordinate)) }
    }

    /// True when a track exists but the aircraft never left the spot — testing on
    /// the ground, or a recording started and stopped without flying.
    ///
    /// Worth distinguishing, because such a track is a dot sitting wherever the
    /// device was, and measuring its distance from a planned route would report a
    /// large and completely meaningless "divergence".
    var neverMoved: Bool { !track.isEmpty && trackSpreadNM < 0.5 }

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

    /// True when the file held records that could not be read. Saving is blocked
    /// while it is set, so a decode problem cannot turn into data loss.
    private(set) var loadFailed = false

    func load() {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return }

        if let decoded = try? JSONDecoder().decode([FlightRecord].self, from: data) {
            records = decoded.sorted { $0.startedAt > $1.startedAt }
            loadFailed = false
            return
        }

        // Whole-array decoding failed, so try record by record: one unreadable
        // entry should cost that entry, not the entire logbook.
        var recovered: [FlightRecord] = []
        var lost = 0
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            for element in raw {
                guard let bytes = try? JSONSerialization.data(withJSONObject: element),
                      let record = try? JSONDecoder().decode(FlightRecord.self, from: bytes) else {
                    lost += 1
                    continue
                }
                recovered.append(record)
            }
        } else {
            lost = 1
        }

        records = recovered.sorted { $0.startedAt > $1.startedAt }
        loadFailed = lost > 0
        if loadFailed {
            // Keep the original bytes before anything can overwrite them.
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("AeroMaps-flights-unreadable.json")
            try? data.write(to: backup, options: .atomic)
        }
    }

    func save() {
        // Never write over a file whose contents could not be read. Without this,
        // an empty in-memory list — the result of a failed load — would silently
        // replace every flight on disk the next time anything was recorded.
        guard !loadFailed else { return }
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
