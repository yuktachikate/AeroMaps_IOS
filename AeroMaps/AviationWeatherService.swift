import Foundation
import CoreLocation
import Combine

// MARK: - Models

/// A decoded METAR from the Aviation Weather Center.
struct Metar: Identifiable, Codable {
    var id: String { icaoId + rawOb }
    let icaoId: String
    let name: String?
    let rawOb: String
    let obsTime: Int?
    let temp: Double?
    let dewp: Double?
    let wdir: WindDirection?
    let wspd: Double?
    let wgst: Double?
    let visib: Visibility?
    let altim: Double?
    let fltCat: String?
    let lat: Double?
    let lon: Double?
    let clouds: [Cloud]?

    struct Cloud: Codable { let cover: String?; let base: Int? }

    /// AWC sends wind direction as a number, or the string "VRB" when variable.
    enum WindDirection: Codable {
        case degrees(Int), variable
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let value = try? c.decode(Int.self) { self = .degrees(value) }
            else { self = .variable }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .degrees(let d): try c.encode(d)
            case .variable: try c.encode("VRB")
            }
        }
        var value: Int? { if case .degrees(let d) = self { return d }; return nil }
    }

    /// Visibility arrives as a number or as "10+".
    enum Visibility: Codable {
        case statuteMiles(Double), unlimited
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let value = try? c.decode(Double.self) { self = .statuteMiles(value) }
            else if let text = try? c.decode(String.self) {
                self = text.contains("+") ? .unlimited : .statuteMiles(Double(text.filter { $0.isNumber || $0 == "." }) ?? 0)
            } else { self = .unlimited }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .statuteMiles(let v): try c.encode(v)
            case .unlimited: try c.encode("10+")
            }
        }
        var miles: Double { if case .statuteMiles(let v) = self { return v }; return 10 }
    }

    var observedAt: Date? { obsTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    var ceilingFT: Int? {
        clouds?.first { ["BKN", "OVC", "OVX"].contains($0.cover ?? "") }?.base
    }
    /// Flight category as reported by AWC (VFR / MVFR / IFR / LIFR).
    var category: String { fltCat ?? "UNK" }
}

struct Taf: Codable {
    let icaoId: String
    let rawTAF: String?
}

/// An AIRMET or SIGMET — the app's only real source of turbulence, icing and
/// convective hazard information.
struct AirSigmet: Identifiable, Codable {
    var id: String { "\(icaoId ?? "")-\(validTimeFrom ?? 0)-\(hazard ?? "")" }
    let icaoId: String?
    let airSigmetType: String?
    let hazard: String?          // TURB, ICE, IFR, MTN OBSCN, CONVECTIVE
    let severity: String?
    let altitudeLow1: Int?
    let altitudeHi1: Int?
    let validTimeFrom: Int?
    let validTimeTo: Int?
    let rawAirSigmet: String?
    let coords: [Coord]?

    struct Coord: Codable { let lat: Double?; let lon: Double? }

    var polygon: [CLLocationCoordinate2D] {
        (coords ?? []).compactMap {
            guard let lat = $0.lat, let lon = $0.lon else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    var validTo: Date? { validTimeTo.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var isActive: Bool { (validTo ?? .distantFuture) > Date() }

    /// True when this hazard overlaps a planned altitude band.
    func affects(altitudeFT: Int) -> Bool {
        let low = altitudeLow1 ?? 0
        let high = altitudeHi1 ?? 60_000
        return altitudeFT >= low && altitudeFT <= high
    }

    var title: String {
        let kind = airSigmetType ?? "ADVISORY"
        return "\(kind) · \(hazard ?? "HAZARD")"
    }
}

// MARK: - Service

/// Real aviation weather from the NOAA Aviation Weather Center.
///
/// Chosen because it is the official FAA/NWS source, needs no API key or account,
/// and — despite the name — carries stations worldwide, not just the US. Everything
/// is cached to disk, so a briefing obtained on the ground is still readable in the
/// air with its age shown.
final class AviationWeatherService: ObservableObject {

    private static let base = "https://aviationweather.gov/api/data"

    /// METARs are issued hourly with SPECIs between; re-fetching more often than
    /// this spends bandwidth for no new information.
    private static let metarFreshness: TimeInterval = 10 * 60
    private static let tafFreshness: TimeInterval = 45 * 60
    private static let sigmetFreshness: TimeInterval = 15 * 60
    /// Beyond this an observation is too old to base a decision on, though it is
    /// still shown — labelled — rather than hidden.
    static let staleAfter: TimeInterval = 3 * 3600

    @Published private(set) var metars: [String: Metar] = [:]
    @Published private(set) var freshness: [String: DataFreshness] = [:]
    @Published private(set) var tafs: [String: String] = [:]
    @Published private(set) var hazards: [AirSigmet] = []
    @Published private(set) var hazardFreshness: DataFreshness = .unavailable
    @Published private(set) var isFetching = false

    private var inFlight: Set<String> = []

    // MARK: METAR

    /// Fetches observations for several stations in one request — AWC accepts a
    /// comma-separated list, so a whole route costs one call.
    @MainActor
    func loadMetars(for idents: [String]) async {
        let wanted = idents.map { $0.uppercased() }.filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return }

        let key = "metar-" + wanted.sorted().joined(separator: ",")
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        var components = URLComponents(string: "\(Self.base)/metar")!
        components.queryItems = [
            URLQueryItem(name: "ids", value: wanted.joined(separator: ",")),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { return }

        isFetching = true
        defer { isFetching = false }

        guard let result = await DataCache.shared.fetch(url, key: key, freshFor: Self.metarFreshness),
              let decoded = try? JSONDecoder().decode([Metar].self, from: result.data) else {
            for ident in wanted where freshness[ident] == nil { freshness[ident] = .unavailable }
            return
        }

        let state = DataFreshness(age: result.age, fromCache: result.fromCache)
        for metar in decoded {
            metars[metar.icaoId] = metar
            freshness[metar.icaoId] = state
        }
        // Stations the service had nothing for — many small fields have no reporting
        // equipment, which is a fact worth showing rather than an error.
        for ident in wanted where metars[ident] == nil { freshness[ident] = .unavailable }
    }

    func metar(for ident: String) -> Metar? { metars[ident.uppercased()] }
    func freshness(for ident: String) -> DataFreshness { freshness[ident.uppercased()] ?? .unavailable }

    // MARK: TAF

    @MainActor
    func loadTaf(for ident: String) async {
        let key = "taf-\(ident.uppercased())"
        var components = URLComponents(string: "\(Self.base)/taf")!
        components.queryItems = [
            URLQueryItem(name: "ids", value: ident.uppercased()),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url,
              let result = await DataCache.shared.fetch(url, key: key, freshFor: Self.tafFreshness),
              let decoded = try? JSONDecoder().decode([Taf].self, from: result.data),
              let taf = decoded.first, let raw = taf.rawTAF else { return }
        tafs[ident.uppercased()] = raw
    }

    // MARK: Hazards

    /// AIRMETs and SIGMETs — turbulence, icing, IFR conditions and convection.
    @MainActor
    func loadHazards() async {
        var components = URLComponents(string: "\(Self.base)/airsigmet")!
        components.queryItems = [URLQueryItem(name: "format", value: "json")]
        guard let url = components.url else { return }

        guard let result = await DataCache.shared.fetch(url, key: "airsigmet",
                                                        freshFor: Self.sigmetFreshness, timeout: 25),
              let decoded = try? JSONDecoder().decode([AirSigmet].self, from: result.data) else {
            hazardFreshness = .unavailable
            return
        }
        hazards = decoded.filter(\.isActive)
        hazardFreshness = DataFreshness(age: result.age, fromCache: result.fromCache)
    }

    /// Hazards whose area contains a point at a given altitude — what the route
    /// validator asks about each leg.
    func hazards(near coordinate: CLLocationCoordinate2D,
                 altitudeFT: Int,
                 withinNM: Double = 40) -> [AirSigmet] {
        hazards.filter { hazard in
            guard hazard.affects(altitudeFT: altitudeFT) else { return false }
            let polygon = hazard.polygon
            guard !polygon.isEmpty else { return false }
            if Self.contains(polygon: polygon, point: coordinate) { return true }
            return polygon.contains { AltitudePlanner.distanceNM($0, coordinate) < withinNM }
        }
    }

    /// Standard ray-casting point-in-polygon.
    private static func contains(polygon: [CLLocationCoordinate2D], point: CLLocationCoordinate2D) -> Bool {
        guard polygon.count > 2 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.longitude > point.longitude) != (b.longitude > point.longitude) {
                let slope = (b.latitude - a.latitude) / (b.longitude - a.longitude)
                if point.latitude < a.latitude + slope * (point.longitude - a.longitude) { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    // MARK: Wind

    /// Observed surface wind at the station nearest a point.
    ///
    /// Returns nil when nothing is reporting nearby, which is the caller's cue to
    /// say so rather than substitute a guess.
    func surfaceWind(near coordinate: CLLocationCoordinate2D,
                     withinNM: Double = 60) -> (direction: Int, speedKT: Int, gustKT: Int?, station: String, age: DataFreshness)? {
        var best: (Metar, Double)?
        for metar in metars.values {
            guard let position = metar.coordinate, metar.wspd != nil else { continue }
            let d = AltitudePlanner.distanceNM(coordinate, position)
            if d <= withinNM, best == nil || d < best!.1 { best = (metar, d) }
        }
        guard let (metar, _) = best else { return nil }
        // A variable wind has no usable direction for runway selection.
        guard let direction = metar.wdir?.value else { return nil }
        return (direction,
                Int((metar.wspd ?? 0).rounded()),
                metar.wgst.map { Int($0.rounded()) },
                metar.icaoId,
                freshness(for: metar.icaoId))
    }
}
