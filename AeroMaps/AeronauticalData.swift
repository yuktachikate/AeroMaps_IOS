import Foundation
import CoreLocation
import Combine

// MARK: - Decoded records

/// The on-disk shape of the bundled dataset. Keys are short because the file ships
/// in the app and is re-downloaded on refresh; see tools/build_airport_data.py.
struct AeroFile: Codable {
    struct Runway: Codable {
        let d: String        // "10L/28R"
        let l: Int           // length ft
        let w: Int           // width ft
        let s: String        // surface
        let g: Bool          // lighted
        let hl: Double?      // low-end true heading
        let hh: Double?      // high-end true heading
    }
    struct Frequency: Codable {
        let t: String        // "TWR", "ATIS"
        let f: String        // MHz
    }
    struct Airport: Codable {
        let i: String        // ident
        let n: String        // name
        let m: String        // municipality
        let r: String        // region
        let c: String        // ISO country
        let t: Int           // 3 large, 2 medium, 1 small
        let y: Double
        let x: Double
        let e: Int           // elevation ft
        let a: String        // IATA
        // Filled in a second pass by the on-device updater, which reads runways and
        // frequencies from separate source files.
        var R: [Runway]
        var F: [Frequency]
    }
    struct Navaid: Codable {
        let i: String
        let n: String
        let t: String
        let y: Double
        let x: Double
        let c: String
        let f: Double?
    }

    let version: Int
    let generated: String
    let source: String
    let airports: [Airport]
    let navaids: [Navaid]
}

// MARK: - Catalog

/// Read-only access to the aeronautical database.
///
/// Deliberately shaped like the dictionary it replaced (`subscript` by ident) so
/// existing call sites read the same, but everything else goes through indexed
/// queries. The old catalog was 52 hand-typed international airports; this one is
/// ~29,000 fields worldwide, so iterating it per keystroke is not an option.
struct AirportCatalog {
    fileprivate let records: [AeroFile.Airport]
    fileprivate let byIdent: [String: Int]
    fileprivate let byIATA: [String: Int]
    /// 1°×1° buckets of record indices, for "what is near here" without a full scan.
    fileprivate let grid: [GridKey: [Int]]
    let navaids: [Navaid]
    let generated: Date?
    let source: String

    struct GridKey: Hashable { let lat: Int; let lon: Int }

    struct Navaid: Identifiable, Hashable {
        var id: String { "\(ident)-\(latitude)-\(longitude)" }
        let ident: String
        let name: String
        let type: String
        let latitude: Double
        let longitude: Double
        let frequencyMHz: Double?
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    static let empty = AirportCatalog(records: [], byIdent: [:], byIATA: [:], grid: [:],
                                      navaids: [], generated: nil, source: "")

    var count: Int { records.count }
    var isEmpty: Bool { records.isEmpty }

    // MARK: Lookup

    subscript(ident: String) -> Airport? {
        let key = ident.uppercased()
        if let index = byIdent[key] { return airport(at: index) }
        if let index = byIATA[key] { return airport(at: index) }
        return nil
    }

    /// Airports within `limitNM`, nearest first. Grid-indexed, so a local-area query
    /// touches a handful of buckets rather than the whole world.
    func nearby(_ coordinate: CLLocationCoordinate2D,
                withinNM limitNM: Double,
                limit: Int = 25,
                minimumType: Int = 1) -> [Airport] {
        let span = Int((limitNM / 60).rounded(.up)) + 1
        let centreLat = Int(floor(coordinate.latitude))
        let centreLon = Int(floor(coordinate.longitude))

        var scored: [(index: Int, distance: Double)] = []
        for dLat in -span...span {
            for dLon in -span...span {
                let key = GridKey(lat: centreLat + dLat, lon: centreLon + dLon)
                guard let bucket = grid[key] else { continue }
                for index in bucket {
                    let record = records[index]
                    guard record.t >= minimumType else { continue }
                    let d = AltitudePlanner.distanceNM(coordinate,
                                                       CLLocationCoordinate2D(latitude: record.y, longitude: record.x))
                    if d <= limitNM { scored.append((index, d)) }
                }
            }
        }
        return scored.sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map { airport(at: $0.index) }
    }

    /// Ident and name search, ranked so an exact ident wins, then prefix matches,
    /// then name/city matches — with distance from `near` breaking ties so a pilot
    /// searching "SPRING" gets the field down the road, not one across the world.
    func search(_ rawQuery: String,
                near: CLLocationCoordinate2D? = nil,
                limit: Int = 10) -> [Airport] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard query.count >= 2 else { return [] }

        var scored: [(index: Int, rank: Int, distance: Double)] = []
        var seen = Set<Int>()

        func consider(_ index: Int, _ rank: Int) {
            guard seen.insert(index).inserted else { return }
            let record = records[index]
            let distance = near.map {
                AltitudePlanner.distanceNM($0, CLLocationCoordinate2D(latitude: record.y, longitude: record.x))
            } ?? 0
            scored.append((index, rank, distance))
        }

        if let index = byIdent[query] { consider(index, 0) }
        if let index = byIdent["K" + query] { consider(index, 0) }
        if let index = byIATA[query] { consider(index, 1) }

        for (index, record) in records.enumerated() {
            if scored.count > 400 { break }
            if record.i.hasPrefix(query) { consider(index, 2) }
            else if record.n.uppercased().contains(query) { consider(index, 3) }
            else if !record.m.isEmpty, record.m.uppercased().contains(query) { consider(index, 4) }
        }

        return scored
            .sorted { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                if near != nil, a.distance != b.distance { return a.distance < b.distance }
                // Bigger fields first when nothing else separates them.
                return records[a.index].t > records[b.index].t
            }
            .prefix(limit)
            .map { airport(at: $0.index) }
    }

    /// Materialises the app's `Airport` value for one record. Kept lazy: holding
    /// 29,000 of these with their runway and frequency arrays would be wasteful when
    /// a session touches a few dozen.
    fileprivate func airport(at index: Int) -> Airport {
        let r = records[index]
        return Airport(
            icao: r.i,
            iataCode: r.a,
            name: r.n,
            city: r.m,
            state: r.r,
            coordinate: CLLocationCoordinate2D(latitude: r.y, longitude: r.x),
            elevation: r.e,
            runways: r.R.map {
                Runway(designation: $0.d, length: $0.l, width: $0.w,
                       surface: $0.s, lighted: $0.g,
                       trueHeadingLow: $0.hl, trueHeadingHigh: $0.hh)
            },
            frequencies: r.F.map {
                Frequency(type: $0.t, frequency: $0.f, description: $0.t)
            },
            services: [],
            isVerified: true
        )
    }

    /// Nearest navaid, for naming a generated waypoint after something a pilot can
    /// tune rather than a string of coordinates.
    func nearestNavaid(to coordinate: CLLocationCoordinate2D, withinNM limitNM: Double) -> Navaid? {
        var best: (Navaid, Double)?
        for navaid in navaids {
            let d = AltitudePlanner.distanceNM(coordinate, navaid.coordinate)
            if d <= limitNM, best == nil || d < best!.1 { best = (navaid, d) }
        }
        return best?.0
    }
}

// MARK: - Database

/// Loads the aeronautical dataset and keeps it current.
///
/// Offline is the normal case, not the error case: this is used in a cockpit. A
/// copy always ships in the app bundle, refreshes are written to Application
/// Support and preferred when newer, and a failed refresh changes nothing.
final class AeronauticalDatabase: ObservableObject {

    enum Status: Equatable {
        case loading
        case ready(source: Source, generated: Date?)
        case failed(String)

        enum Source: String { case bundled = "bundled", downloaded = "updated" }
    }

    @Published private(set) var catalog = AirportCatalog.empty
    @Published private(set) var status: Status = .loading
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshStage: String?
    @Published private(set) var refreshProgress: Double = 0
    @Published private(set) var lastRefreshAttempt: Date?

    /// Refresh at most this often. OurAirports rebuilds nightly, but airports do not
    /// move, so weekly is generous.
    static let refreshInterval: TimeInterval = 7 * 24 * 3600

    private static let cacheFileName = "aerodata.json"
    private static let lastRefreshKey = "AeroMaps_LastAeroDataRefresh"

    private var cacheURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent(Self.cacheFileName)
    }

    init() {
        load()
    }

    // MARK: Loading

    /// Reads the newest copy available. Never touches the network — startup must
    /// work with the device in airplane mode.
    func load() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            var loaded: (AirportCatalog, Status.Source)?
            if let cacheURL, let data = try? Data(contentsOf: cacheURL),
               let catalog = Self.decode(data) {
                loaded = (catalog, .downloaded)
            }
            if loaded == nil,
               let url = Bundle.main.url(forResource: "aerodata", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let catalog = Self.decode(data) {
                loaded = (catalog, .bundled)
            }

            DispatchQueue.main.async {
                if let (catalog, source) = loaded {
                    self.catalog = catalog
                    self.status = .ready(source: source, generated: catalog.generated)
                } else {
                    self.status = .failed("Aeronautical data could not be read.")
                }
            }
        }
    }

    private static func decode(_ data: Data) -> AirportCatalog? {
        guard let file = try? JSONDecoder().decode(AeroFile.self, from: data) else { return nil }

        var byIdent: [String: Int] = [:]
        var byIATA: [String: Int] = [:]
        var grid: [AirportCatalog.GridKey: [Int]] = [:]
        byIdent.reserveCapacity(file.airports.count)

        for (index, a) in file.airports.enumerated() {
            byIdent[a.i] = index
            if !a.a.isEmpty, byIATA[a.a] == nil { byIATA[a.a] = index }
            let key = AirportCatalog.GridKey(lat: Int(floor(a.y)), lon: Int(floor(a.x)))
            grid[key, default: []].append(index)
        }

        let formatter = ISO8601DateFormatter()
        return AirportCatalog(
            records: file.airports,
            byIdent: byIdent,
            byIATA: byIATA,
            grid: grid,
            navaids: file.navaids.map {
                AirportCatalog.Navaid(ident: $0.i, name: $0.n, type: $0.t,
                                      latitude: $0.y, longitude: $0.x, frequencyMHz: $0.f)
            },
            generated: formatter.date(from: file.generated),
            source: file.source
        )
    }

    // MARK: Refreshing

    var isRefreshDue: Bool {
        guard let last = UserDefaults.standard.object(forKey: Self.lastRefreshKey) as? Date else { return true }
        return Date().timeIntervalSince(last) > Self.refreshInterval
    }

    /// Rebuilds the dataset on the device when one is due.
    ///
    /// There is no server behind this. The phone fetches the same public-domain CSVs
    /// the build script uses and runs the identical transform, so the app depends on
    /// nothing that has to be hosted or kept alive. Silent by design: a refresh that
    /// fails leaves the working copy untouched and is retried another day.
    func refreshIfDue(force: Bool = false) {
        guard force || isRefreshDue, !isRefreshing else { return }
        isRefreshing = true
        refreshProgress = 0
        lastRefreshAttempt = Date()

        Task { [weak self] in
            defer {
                Task { @MainActor in
                    self?.isRefreshing = false
                    self?.refreshStage = nil
                }
            }
            do {
                let data = try await AeronauticalDataUpdater.buildDataset { progress in
                    Task { @MainActor in
                        self?.refreshStage = progress.stage
                        self?.refreshProgress = progress.fraction
                    }
                }
                guard let catalog = Self.decode(data), !catalog.isEmpty else { return }

                // Written atomically: a half-built file must never become the copy
                // the app boots from next flight.
                if let cacheURL = self?.cacheURL {
                    try? data.write(to: cacheURL, options: .atomic)
                }
                UserDefaults.standard.set(Date(), forKey: Self.lastRefreshKey)

                await MainActor.run {
                    self?.catalog = catalog
                    self?.status = .ready(source: .downloaded, generated: catalog.generated)
                }
            } catch {
                // Offline, on cellular, or the source was unreachable: keep what we
                // have and try again next cycle.
            }
        }
    }
}
