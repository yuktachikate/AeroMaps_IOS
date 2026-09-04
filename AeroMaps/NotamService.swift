import Foundation
import CoreLocation
import Combine

/// One NOTAM as published by the FAA.
struct Notam: Identifiable {
    let id: String
    let number: String
    let icaoLocation: String
    let text: String
    let effectiveStart: Date?
    let effectiveEnd: Date?
    let classification: String?
    let coordinate: CLLocationCoordinate2D?

    var isActive: Bool {
        let now = Date()
        if let start = effectiveStart, start > now { return false }
        if let end = effectiveEnd, end < now { return false }
        return true
    }

    /// Rough severity read off the text, used only for ordering and icon choice —
    /// never to decide anything on the pilot's behalf.
    var isRunwayOrApproach: Bool {
        let upper = text.uppercased()
        return upper.contains("RWY") || upper.contains("RUNWAY")
            || upper.contains("ILS") || upper.contains("APCH") || upper.contains("CLSD")
    }
}

/// Real NOTAMs from the FAA NOTAM API.
///
/// The API is gated: it needs a client ID and secret from api.faa.gov, and returns
/// 401 without them. Those credentials are read from configuration and are never
/// committed — see `Info.plist` keys `FAANotamClientID` / `FAANotamClientSecret`.
///
/// When they are absent the service reports `.notConfigured` and the app says
/// NOTAMs are unavailable. It does **not** invent any. This class replaced six
/// hardcoded fake NOTAMs — including "KSFO RWY 28R closed for resurfacing" and an
/// unlit crane — that were displayed as though they were real, plus two more
/// generated at whatever coordinates the map happened to be showing.
final class NotamService: ObservableObject {

    enum Status: Equatable {
        case notConfigured
        case loading
        case ready(count: Int, freshness: DataFreshness)
        case failed(String)
    }

    private static let endpoint = "https://external-api.faa.gov/notamapi/v1/notams"
    /// NOTAMs are issued continuously; an hour old is still useful, and being able
    /// to read the last set offline matters more than being minutes-current.
    private static let freshnessWindow: TimeInterval = 30 * 60

    @Published private(set) var notams: [Notam] = []
    @Published private(set) var status: Status = .notConfigured

    private var loadedLocations: Set<String> = []

    /// Credentials come from the app's configuration, not from source.
    private var credentials: (id: String, secret: String)? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "FAANotamClientID") as? String,
              let secret = Bundle.main.object(forInfoDictionaryKey: "FAANotamClientSecret") as? String,
              !id.isEmpty, !secret.isEmpty,
              !id.hasPrefix("$(") else { return nil }
        return (id, secret)
    }

    var isConfigured: Bool { credentials != nil }

    /// Human-readable explanation for the UI when there is nothing to show.
    var unavailableReason: String {
        switch status {
        case .notConfigured:
            return "NOTAMs need free FAA API credentials. Add FAANotamClientID and FAANotamClientSecret to the app configuration to enable them."
        case .failed(let message):
            return message
        default:
            return "No NOTAMs for this area."
        }
    }

    @MainActor
    func load(for icaoLocations: [String]) async {
        let wanted = Set(icaoLocations.map { $0.uppercased() }.filter { $0.count == 4 })
        guard !wanted.isEmpty else { return }

        guard let credentials else {
            status = .notConfigured
            notams = []
            return
        }

        status = .loading
        var collected: [Notam] = []
        var newest = DataFreshness.unavailable

        for location in wanted.sorted() {
            var components = URLComponents(string: Self.endpoint)!
            components.queryItems = [
                URLQueryItem(name: "icaoLocation", value: location),
                URLQueryItem(name: "pageSize", value: "50")
            ]
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(credentials.id, forHTTPHeaderField: "client_id")
            request.setValue(credentials.secret, forHTTPHeaderField: "client_secret")

            let key = "notam-\(location)"
            // Cached copy first — NOTAMs read on the ground must still be readable
            // in the air.
            if let cached = DataCache.shared.load(key), cached.age < Self.freshnessWindow {
                collected.append(contentsOf: Self.decode(cached.value, location: location))
                newest = DataFreshness(age: cached.age, fromCache: true)
                continue
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                if http.statusCode == 401 || http.statusCode == 403 {
                    status = .failed("FAA NOTAM credentials were rejected.")
                    return
                }
                guard (200..<300).contains(http.statusCode) else { continue }
                DataCache.shared.store(data, for: key)
                collected.append(contentsOf: Self.decode(data, location: location))
                newest = .live
            } catch {
                // Offline: fall back to whatever was last stored for this field.
                if let cached = DataCache.shared.load(key) {
                    collected.append(contentsOf: Self.decode(cached.value, location: location))
                    newest = DataFreshness(age: cached.age, fromCache: true)
                }
            }
        }

        notams = collected.filter(\.isActive).sorted {
            ($0.isRunwayOrApproach ? 0 : 1, $0.icaoLocation) < ($1.isRunwayOrApproach ? 0 : 1, $1.icaoLocation)
        }
        status = notams.isEmpty && newest == .unavailable
            ? .failed("Could not reach the FAA NOTAM service.")
            : .ready(count: notams.count, freshness: newest)
        loadedLocations = wanted
    }

    // MARK: Decoding

    /// The FAA response wraps each NOTAM in an AIXM-ish envelope; only a few fields
    /// are needed here and every one of them is optional in practice.
    private static func decode(_ data: Data, location: String) -> [Notam] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return [] }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()

        func date(_ raw: Any?) -> Date? {
            guard let text = raw as? String else { return nil }
            return formatter.date(from: text) ?? plainFormatter.date(from: text)
        }

        return items.compactMap { item in
            let properties = (item["properties"] as? [String: Any]) ?? item
            let core = (properties["coreNOTAMData"] as? [String: Any]) ?? properties
            guard let notam = (core["notam"] as? [String: Any]) else { return nil }

            let text = (notam["text"] as? String)
                ?? (notam["simpleText"] as? String)
                ?? ""
            guard !text.isEmpty else { return nil }

            var coordinate: CLLocationCoordinate2D?
            if let geometry = item["geometry"] as? [String: Any],
               let coords = geometry["coordinates"] as? [Double], coords.count >= 2 {
                coordinate = CLLocationCoordinate2D(latitude: coords[1], longitude: coords[0])
            }

            let number = (notam["number"] as? String) ?? (notam["id"] as? String) ?? UUID().uuidString
            return Notam(
                id: "\(location)-\(number)",
                number: number,
                icaoLocation: (notam["location"] as? String) ?? location,
                text: text,
                effectiveStart: date(notam["effectiveStart"]),
                effectiveEnd: date(notam["effectiveEnd"]),
                classification: notam["classification"] as? String,
                coordinate: coordinate)
        }
    }
}
