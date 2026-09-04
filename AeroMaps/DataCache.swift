import Foundation

/// Disk-and-memory cache for everything fetched from the network.
///
/// This app is used in the air, where the connection is intermittent at best. The
/// rule throughout is: fetch when you can, keep what you got, and always be able to
/// say how old it is. Nothing here ever throws away a usable answer because a later
/// request failed.
final class DataCache {
    static let shared = DataCache()

    struct Entry<Value> {
        let value: Value
        let stored: Date
        var age: TimeInterval { Date().timeIntervalSince(stored) }
    }

    private let directory: URL
    private let queue = DispatchQueue(label: "aeromaps.datacache", attributes: .concurrent)
    private var memory: [String: (data: Data, stored: Date)] = [:]

    private init() {
        let base = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("AeroData", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(_ key: String) -> URL {
        // Keys carry slashes and coordinates; hash to something a filesystem accepts.
        let safe = key.unicodeScalars.reduce(into: UInt64(5381)) { $0 = $0 &* 33 &+ UInt64($1.value) }
        return directory.appendingPathComponent("\(safe).cache")
    }

    /// Returns cached data and how old it is, regardless of freshness. The caller
    /// decides whether an old answer is still worth using — which is usually is,
    /// offline.
    func load(_ key: String) -> Entry<Data>? {
        if let hit = queue.sync(execute: { memory[key] }) {
            return Entry(value: hit.data, stored: hit.stored)
        }
        let url = fileURL(key)
        guard let data = try? Data(contentsOf: url),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let stored = attrs[.modificationDate] as? Date else { return nil }
        queue.async(flags: .barrier) { self.memory[key] = (data, stored) }
        return Entry(value: data, stored: stored)
    }

    func store(_ data: Data, for key: String) {
        queue.async(flags: .barrier) { self.memory[key] = (data, Date()) }
        try? data.write(to: fileURL(key), options: .atomic)
    }

    /// Decoded convenience wrapper.
    func load<T: Decodable>(_ type: T.Type, for key: String) -> Entry<T>? {
        guard let entry = load(key),
              let value = try? JSONDecoder().decode(type, from: entry.value) else { return nil }
        return Entry(value: value, stored: entry.stored)
    }

    /// Fetches `url`, caching the result. On any failure — offline, timeout, server
    /// error — the last cached copy is returned with its age, so callers degrade to
    /// stale-but-real rather than to nothing.
    ///
    /// - Parameter freshFor: skip the network entirely if the cached copy is younger.
    /// - Parameter validate: rejects a payload that arrived with a 200 but is not
    ///   actually the data asked for. Some services — ArcGIS among them — report
    ///   rate limits and errors in a JSON body with a 200 status; caching one of
    ///   those poisons the entry for its whole freshness window.
    func fetch(_ url: URL,
               key: String? = nil,
               freshFor: TimeInterval,
               timeout: TimeInterval = 15,
               validate: ((Data) -> Bool)? = nil) async -> (data: Data, age: TimeInterval, fromCache: Bool)? {
        let cacheKey = key ?? url.absoluteString

        if let cached = load(cacheKey), cached.age < freshFor {
            return (cached.value, cached.age, true)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  !data.isEmpty else { throw URLError(.badServerResponse) }
            // A 200 is not proof of success; let the caller inspect the payload
            // before it is written to disk.
            if let validate, !validate(data) { throw URLError(.badServerResponse) }
            store(data, for: cacheKey)
            return (data, 0, false)
        } catch {
            if let cached = load(cacheKey) {
                return (cached.value, cached.age, true)
            }
            return nil
        }
    }

    /// Drops cached entries older than `maxAge`. Called occasionally; this is a
    /// convenience store, not a database.
    func prune(olderThan maxAge: TimeInterval = 7 * 24 * 3600) {
        queue.async(flags: .barrier) {
            self.memory = self.memory.filter { Date().timeIntervalSince($0.value.stored) < maxAge }
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let stored = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(stored) > maxAge {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

/// How current a piece of fetched data is — shown wherever it is displayed, because
/// a pilot needs to know whether they are reading an observation from four minutes
/// ago or four hours ago.
enum DataFreshness: Equatable {
    case live                       // just fetched
    case cached(age: TimeInterval)  // served from cache
    case unavailable

    init(age: TimeInterval, fromCache: Bool) {
        self = fromCache && age > 60 ? .cached(age: age) : .live
    }

    var isUsable: Bool { self != .unavailable }

    var shortLabel: String {
        switch self {
        case .live: return "current"
        case .cached(let age):
            let minutes = Int(age / 60)
            if minutes < 60 { return "\(max(minutes, 1)) min old" }
            let hours = minutes / 60
            return hours < 24 ? "\(hours) h old" : "\(hours / 24) d old"
        case .unavailable: return "unavailable"
        }
    }
}
