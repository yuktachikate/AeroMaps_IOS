import SwiftUI
import MapKit
import Foundation
import Combine

// MARK: - Live Flight Data Models
struct LiveFlight: Identifiable, Codable {
    let id: UUID
    let icao24: String
    let callsign: String?
    let origin: String?
    let destination: String?
    let coordinate: CLLocationCoordinate2D
    let altitude: Double?
    let speed: Double?
    let heading: Double?
    let verticalRate: Double?
    let squawk: String?
    let timestamp: Date
    var isTracked: Bool
    
    init(
        id: UUID = UUID(),
        icao24: String,
        callsign: String? = nil,
        origin: String? = nil,
        destination: String? = nil,
        coordinate: CLLocationCoordinate2D,
        altitude: Double? = nil,
        speed: Double? = nil,
        heading: Double? = nil,
        verticalRate: Double? = nil,
        squawk: String? = nil,
        timestamp: Date = Date(),
        isTracked: Bool = false
    ) {
        self.id = id
        self.icao24 = icao24
        self.callsign = callsign
        self.origin = origin
        self.destination = destination
        self.coordinate = coordinate
        self.altitude = altitude
        self.speed = speed
        self.heading = heading
        self.verticalRate = verticalRate
        self.squawk = squawk
        self.timestamp = timestamp
        self.isTracked = isTracked
    }
    
    enum CodingKeys: String, CodingKey {
        case icao24, callsign, origin, destination, latitude, longitude, altitude, speed, heading, verticalRate, squawk, timestamp, isTracked
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.icao24 = try container.decode(String.self, forKey: .icao24)
        self.callsign = try container.decodeIfPresent(String.self, forKey: .callsign)
        self.origin = try container.decodeIfPresent(String.self, forKey: .origin)
        self.destination = try container.decodeIfPresent(String.self, forKey: .destination)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        self.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        self.altitude = try container.decodeIfPresent(Double.self, forKey: .altitude)
        self.speed = try container.decodeIfPresent(Double.self, forKey: .speed)
        self.heading = try container.decodeIfPresent(Double.self, forKey: .heading)
        self.verticalRate = try container.decodeIfPresent(Double.self, forKey: .verticalRate)
        self.squawk = try container.decodeIfPresent(String.self, forKey: .squawk)
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        self.isTracked = try container.decodeIfPresent(Bool.self, forKey: .isTracked) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(icao24, forKey: .icao24)
        try container.encodeIfPresent(callsign, forKey: .callsign)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encodeIfPresent(destination, forKey: .destination)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encodeIfPresent(altitude, forKey: .altitude)
        try container.encodeIfPresent(speed, forKey: .speed)
        try container.encodeIfPresent(heading, forKey: .heading)
        try container.encodeIfPresent(verticalRate, forKey: .verticalRate)
        try container.encodeIfPresent(squawk, forKey: .squawk)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isTracked, forKey: .isTracked)
    }
}

// MARK: - Live Flight Service
class LiveFlightService: ObservableObject {
    @Published var flights: [LiveFlight] = []
    @Published var isLoading = false
    @Published var error: String?

    // Flightradar24-style flown-path trail for the currently selected flight.
    // Accumulated live from position ticks; only one flight is trailed at a time.
    @Published private(set) var trailPoints: [CLLocationCoordinate2D] = []
    private var trailIcao24: String?
    private let maxTrailPoints = 240

    private var timer: Timer?
    /// Wall-clock time of the last position advance. Positions move by the time that
    /// actually elapsed, not by the nominal tick — otherwise a delayed or coalesced
    /// timer under-advances, and a burst of catch-up ticks throws aircraft forward.
    private var lastPositionUpdate = Date()
    private var cancellables = Set<AnyCancellable>()

    // Position refresh interval. Real trackers like Flightradar24 do not push new
    // positions every second; ADS-B sources update every few seconds and the client
    // smooths between them. A longer interval here also cuts the SwiftUI re-render
    // churn that drives the navigation-bar observation warnings.
    let updateInterval: TimeInterval = 2.0
    
    var trackedFlights: [LiveFlight] {
        flights.filter { $0.isTracked }
    }
    
    func toggleTrackedFlight(
        callsign: String,
        origin: String? = nil,
        destination: String? = nil,
        altitude: Double? = nil,
        speed: Double? = nil,
        heading: Double? = nil,
        coordinate: CLLocationCoordinate2D? = nil
    ) {
        if let idx = flights.firstIndex(where: { $0.callsign == callsign }) {
            flights[idx].isTracked.toggle()
            // Mirror the change into activeFlights — the periodic live-traffic
            // refresh reseeds `flights` from `activeFlights.filter { isTracked }`,
            // so without this an untracked flight is revived on the next tick.
            setActiveFlightTracked(flights[idx], tracked: flights[idx].isTracked)
            if flights[idx].isTracked { trackedCallsigns.insert(callsign) } else { trackedCallsigns.remove(callsign) }
            persistTrackedCallsigns()
        } else {
            let newTrackedFlight = LiveFlight(
                id: UUID(),
                icao24: "TRK-\(callsign)",
                callsign: callsign,
                // A callsign the pilot added by hand, before the feed has found it.
                // It is a placeholder for a real aircraft, so it carries no invented
                // position or telemetry — those arrive when the feed does.
                origin: origin,
                destination: destination,
                coordinate: coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
                altitude: altitude,
                speed: speed,
                heading: heading,
                verticalRate: 0,
                squawk: "1200",
                timestamp: Date(),
                isTracked: true
            )
            flights.append(newTrackedFlight)
            setActiveFlightTracked(newTrackedFlight, tracked: true)
            trackedCallsigns.insert(callsign)
            persistTrackedCallsigns()
        }
        objectWillChange.send()
    }

    // Keeps activeFlights (the refresh source of truth) in sync with a track/untrack.
    private func setActiveFlightTracked(_ flight: LiveFlight, tracked: Bool) {
        if let i = activeFlights.firstIndex(where: { $0.callsign == flight.callsign }) {
            activeFlights[i].isTracked = tracked
        } else if tracked {
            var f = flight
            f.isTracked = true
            activeFlights.append(f)
        }
    }

    // MARK: - Tracked-flight persistence
    private func loadTrackedCallsigns() {
        if let saved = UserDefaults.standard.array(forKey: trackedKey) as? [String] {
            trackedCallsigns = Set(saved)
        } else {
            // First launch: the demo primary flights start tracked.
            trackedCallsigns = ["UAL1234", "SWA5678", "AAL9999", "N734SP"]
            persistTrackedCallsigns()
        }
    }

    private func persistTrackedCallsigns() {
        UserDefaults.standard.set(Array(trackedCallsigns), forKey: trackedKey)
    }

    // MARK: - Selected-flight trail
    // Begin recording a live flown-path trail for the tapped flight. Seeded with
    // its current position so the very first tick has an anchor; grows from there.
    func startTrail(icao24: String) {
        trailIcao24 = icao24
        if let f = activeFlights.first(where: { $0.icao24 == icao24 }) {
            trailPoints = [f.coordinate]
        } else {
            trailPoints = []
        }
    }

    // Stop trailing and clear the path (called when the flight is deselected).
    func stopTrail() {
        guard trailIcao24 != nil || !trailPoints.isEmpty else { return }
        trailIcao24 = nil
        trailPoints = []
    }
    
    // MARK: - OpenSky traffic feed
    //
    // Requests are anonymous on purpose. OpenSky's anonymous quota is bucketed by IP
    // address, so every device gets its own 400 credits a day and the budget scales
    // with the user base. A registered account would be the opposite: its 4,000
    // credits are per *account*, shared by everyone running the app, and the client
    // secret needed to use it cannot be kept safe inside a shipped binary.
    private let baseURL = "https://opensky-network.org/api"

    /// Where the traffic on screen came from — and, when there is none, why.
    ///
    /// There used to be a fourth state here: `simulated`, which drew about thirty
    /// invented aircraft with plausible callsigns, random positions, altitudes,
    /// speeds and squawk codes whenever the feed was unreachable. It is gone.
    /// Traffic is a see-and-avoid aid, and inventing it is worse than showing
    /// nothing: the symbols were indistinguishable from real returns, the only
    /// warning was a corner pill that is easy to miss in flight, and the habit it
    /// teaches — trusting a display that is sometimes fiction — is the dangerous
    /// part. An empty sky that says why is honest and more useful.
    enum TrafficSource: Equatable {
        case live
        case cached(age: TimeInterval)
        case unavailable(reason: String)

        var isReal: Bool {
            if case .unavailable = self { return false }
            return true
        }

        var label: String {
            switch self {
            case .live: return "Live traffic"
            case .cached(let age):
                let minutes = Int(age / 60)
                return minutes < 1 ? "Live traffic (cached)" : "Traffic \(minutes) min old"
            case .unavailable: return "Traffic unavailable"
            }
        }

        var detail: String? {
            if case .unavailable(let reason) = self { return reason }
            return nil
        }
    }

    @Published private(set) var trafficSource: TrafficSource = .unavailable(reason: "Starting up")
    /// Credits OpenSky says are left today, when it tells us.
    @Published private(set) var remainingCredits: Int?

    /// Cached responses keyed by a coarse grid cell, so panning back to somewhere
    /// just visited costs nothing and a spent budget still has something to show.
    private struct TileKey: Hashable { let lat: Int; let lon: Int }
    private struct CachedTile { let flights: [LiveFlight]; let fetched: Date }
    private var tileCache: [TileKey: CachedTile] = [:]
    /// Fresh enough to serve without re-fetching. OpenSky itself only resolves to
    /// 10 s for anonymous callers, so anything under this is not stale data.
    private static let tileFreshness: TimeInterval = 25
    /// How long a cached tile is still worth showing once it is no longer fresh.
    private static let tileUsableAge: TimeInterval = 15 * 60
    /// Below this many credits the app stops fetching and coasts on cache, keeping
    /// a reserve so the feed is not dead for the rest of the day.
    private static let creditReserve = 25
    private var quotaExhaustedUntil: Date?
    
    private var activeFlights: [LiveFlight] = []

    // Pauses the position simulation while the map is hidden (set from ContentView).
    var isActive = true

    // Persisted set of tracked callsigns so track/untrack survives an app restart.
    private let trackedKey = "AeroMaps.trackedCallsigns.v1"
    private var trackedCallsigns: Set<String> = []
    
    private var currentCenter = CLLocationCoordinate2D(latitude: 37.6213, longitude: -122.3790)
    private var currentLatDelta: Double = 1.0
    private var currentLonDelta: Double = 1.0
    
    init() {
        loadTrackedCallsigns()
        // Nothing is seeded. Until the feed answers, there is no traffic — which is
        // the truth, and the pill says so.
        trafficSource = .unavailable(reason: "Waiting for the traffic feed")
        startLiveUpdates()
    }
    
    deinit {
        stopLiveUpdates()
    }
    
    private var regionDebounceWorkItem: DispatchWorkItem?
    
    func updateMapRegion(center: CLLocationCoordinate2D, latDelta: Double, lonDelta: Double) {
        self.currentCenter = center
        self.currentLatDelta = latDelta
        self.currentLonDelta = lonDelta
        
        let isHighZoomOut = latDelta > 1.5
        if isHighZoomOut {
            DispatchQueue.main.async {
                self.isLoading = true
            }
        }
        
        regionDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.fetchOrGenerateRegionFleet(center: center, latDelta: latDelta, lonDelta: lonDelta)
        }
        regionDebounceWorkItem = workItem
        let delay = isHighZoomOut ? 0.6 : 0.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    private func calculateTargetFlightCount(latDelta: Double) -> Int {
        // Level-of-detail cap on rendered aircraft. Flightradar24 thins traffic by
        // zoom too: at wide zoom the client shows a representative subset, not every
        // plane on Earth. Individual (non-clustered) markers stay smooth and crash
        // free at these counts, and MapKit hides directly overlapping traffic on its
        // own, which reads as natural thinning.
        if latDelta < 0.5 {
            return 60
        } else if latDelta < 2.0 {
            return 140
        } else if latDelta < 10.0 {
            return 220
        } else if latDelta < 40.0 {
            return 300
        } else {
            return 400
        }
    }
    
// MARK: - Global Major Airport Hub Model
struct MajorAirportHub {
    let icao: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let region: String
    let airlines: [String]
}

private let globalHubs: [MajorAirportHub] = [
    // India
    MajorAirportHub(icao: "VIDP", name: "Delhi", coordinate: .init(latitude: 28.5562, longitude: 77.1000), region: "INDIA", airlines: ["IGO", "AIC", "VTI", "SEJ"]),
    MajorAirportHub(icao: "VABB", name: "Mumbai", coordinate: .init(latitude: 19.0896, longitude: 72.8656), region: "INDIA", airlines: ["IGO", "AIC", "VTI", "AKJ"]),
    MajorAirportHub(icao: "VOBL", name: "Bengaluru", coordinate: .init(latitude: 13.1986, longitude: 77.7066), region: "INDIA", airlines: ["IGO", "AIC", "SEJ"]),
    MajorAirportHub(icao: "VOMM", name: "Chennai", coordinate: .init(latitude: 12.9941, longitude: 80.1709), region: "INDIA", airlines: ["IGO", "AIC", "VTI"]),
    MajorAirportHub(icao: "VECC", name: "Kolkata", coordinate: .init(latitude: 22.6547, longitude: 88.4467), region: "INDIA", airlines: ["IGO", "AIC"]),
    MajorAirportHub(icao: "VOHS", name: "Hyderabad", coordinate: .init(latitude: 17.2403, longitude: 78.4294), region: "INDIA", airlines: ["IGO", "AIC", "VTI"]),
    MajorAirportHub(icao: "VOCI", name: "Cochin", coordinate: .init(latitude: 10.1520, longitude: 76.4019), region: "INDIA", airlines: ["IGO", "AIC"]),
    
    // US East & Midwest
    MajorAirportHub(icao: "KJFK", name: "New York JFK", coordinate: .init(latitude: 40.6413, longitude: -73.7781), region: "US", airlines: ["JBU", "DAL", "AAL"]),
    MajorAirportHub(icao: "KBOS", name: "Boston Logan", coordinate: .init(latitude: 42.3656, longitude: -71.0096), region: "US", airlines: ["JBU", "DAL", "AAL"]),
    MajorAirportHub(icao: "KORD", name: "Chicago O'Hare", coordinate: .init(latitude: 41.9742, longitude: -87.9073), region: "US", airlines: ["UAL", "AAL"]),
    MajorAirportHub(icao: "KATL", name: "Atlanta", coordinate: .init(latitude: 33.6407, longitude: -84.4277), region: "US", airlines: ["DAL"]),
    MajorAirportHub(icao: "KDFW", name: "Dallas Fort Worth", coordinate: .init(latitude: 32.8998, longitude: -97.0403), region: "US", airlines: ["AAL"]),
    MajorAirportHub(icao: "KDEN", name: "Denver", coordinate: .init(latitude: 39.8561, longitude: -104.6737), region: "US", airlines: ["UAL", "SWA"]),

    // US West
    MajorAirportHub(icao: "KSFO", name: "San Francisco", coordinate: .init(latitude: 37.6213, longitude: -122.3790), region: "US", airlines: ["UAL", "SWA", "ASA"]),
    MajorAirportHub(icao: "KLAX", name: "Los Angeles", coordinate: .init(latitude: 33.9416, longitude: -118.4085), region: "US", airlines: ["DAL", "AAL", "UAL"]),
    MajorAirportHub(icao: "KSEA", name: "Seattle", coordinate: .init(latitude: 47.4502, longitude: -122.3088), region: "US", airlines: ["ASA", "DAL"]),
    MajorAirportHub(icao: "KLAS", name: "Las Vegas", coordinate: .init(latitude: 36.0840, longitude: -115.1537), region: "US", airlines: ["SWA", "DAL"]),

    // Europe
    MajorAirportHub(icao: "EGLL", name: "London Heathrow", coordinate: .init(latitude: 51.4700, longitude: -0.4543), region: "EUROPE", airlines: ["BAW", "VIR"]),
    MajorAirportHub(icao: "LFPG", name: "Paris CDG", coordinate: .init(latitude: 49.0097, longitude: 2.5479), region: "EUROPE", airlines: ["AFR"]),
    MajorAirportHub(icao: "EDDF", name: "Frankfurt", coordinate: .init(latitude: 50.0379, longitude: 8.5622), region: "EUROPE", airlines: ["DLH"]),
    MajorAirportHub(icao: "EHAM", name: "Amsterdam", coordinate: .init(latitude: 52.3105, longitude: 4.7683), region: "EUROPE", airlines: ["KLM"]),

    // Asia & Middle East
    MajorAirportHub(icao: "OMDB", name: "Dubai", coordinate: .init(latitude: 25.2532, longitude: 55.3657), region: "MIDDLE_EAST", airlines: ["UAE"]),
    MajorAirportHub(icao: "RJTT", name: "Tokyo Haneda", coordinate: .init(latitude: 35.5494, longitude: 139.7798), region: "ASIA", airlines: ["ANA", "JAL"]),
    MajorAirportHub(icao: "VHHH", name: "Hong Kong", coordinate: .init(latitude: 22.3080, longitude: 113.9185), region: "ASIA", airlines: ["CPA"]),
    MajorAirportHub(icao: "WSSS", name: "Singapore", coordinate: .init(latitude: 1.3644, longitude: 103.9915), region: "ASIA", airlines: ["SIA"])
]

    private func fetchOrGenerateRegionFleet(center: CLLocationCoordinate2D, latDelta: Double, lonDelta: Double) {
        let targetCount = calculateTargetFlightCount(latDelta: latDelta)
        
        // OpenSky prices /states/all by bounding-box area: 1 credit up to 25 sq°,
        // rising to 4 above 400 sq°. The old ±15° box was 900 sq° — the top bracket,
        // burning four credits a call for far more sky than fits on a phone screen.
        // ±2.5° is 25 sq° (about 300 NM across) and costs one.
        let safeLatSpan = min(2.5, max(0.3, latDelta * 0.45))
        let safeLonSpan = min(2.5, max(0.3, lonDelta * 0.45))
        let minLat = center.latitude - safeLatSpan
        let maxLat = center.latitude + safeLatSpan
        let minLon = center.longitude - safeLonSpan
        let maxLon = center.longitude + safeLonSpan

        // Fallback ladder, best first: a fresh cached tile costs nothing, so serve
        // that before spending a credit.
        let tile = TileKey(lat: Int((center.latitude / 2).rounded()), lon: Int((center.longitude / 2).rounded()))
        if let cached = tileCache[tile] {
            let age = Date().timeIntervalSince(cached.fetched)
            if age < Self.tileFreshness {
                applyFleet(cached.flights, source: .live)
                return
            }
        }

        // Budget guard: stop before the quota is gone so the rest of the day still
        // has a working feed, and back off entirely once OpenSky refuses.
        if let until = quotaExhaustedUntil, Date() < until {
            serveCachedOrNothing(tile: tile, center: center, latDelta: latDelta,
                                 lonDelta: lonDelta, targetCount: targetCount,
                                 reason: "Daily traffic data limit reached")
            return
        }
        if let credits = remainingCredits, credits <= Self.creditReserve {
            serveCachedOrNothing(tile: tile, center: center, latDelta: latDelta,
                                 lonDelta: lonDelta, targetCount: targetCount,
                                 reason: "Traffic data budget low — holding a reserve")
            return
        }

        let urlString = "\(baseURL)/states/all?lamin=\(minLat)&lamax=\(maxLat)&lomin=\(minLon)&lomax=\(maxLon)"
        guard let url = URL(string: urlString) else {
            applyFleet(trackedOnly(), source: .unavailable(reason: "Could not build the traffic request"))
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }

            if let http = response as? HTTPURLResponse {
                self.recordQuota(from: http)
                // 429 too many requests / 403 quota gone: coast on cache rather than
                // hammering an endpoint that is refusing.
                if http.statusCode == 429 || http.statusCode == 403 {
                    DispatchQueue.main.async {
                        self.quotaExhaustedUntil = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
                        self.serveCachedOrNothing(tile: tile, center: center, latDelta: latDelta,
                                                  lonDelta: lonDelta, targetCount: targetCount,
                                                  reason: "Daily traffic data limit reached")
                    }
                    return
                }
            }

            guard let data, error == nil else {
                DispatchQueue.main.async {
                    self.serveCachedOrNothing(tile: tile, center: center, latDelta: latDelta,
                                              lonDelta: lonDelta, targetCount: targetCount,
                                              reason: "No connection to the traffic feed")
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let states = json["states"] as? [[Any]] {
                    var parsed: [LiveFlight] = self.activeFlights.filter { $0.isTracked }
                    var realFlightCount = 0
                    for state in states.prefix(targetCount) {
                        guard state.count > 10,
                              let icao = state[0] as? String,
                              let lat = state[6] as? Double,
                              let lon = state[5] as? Double else { continue }
                        
                        let csRaw = (state[1] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let callsign = (csRaw?.isEmpty == false) ? csRaw! : "FLT\(icao.prefix(4).uppercased())"
                        let geoAltMeters = state[7] as? Double ?? 3000
                        let altFt = geoAltMeters * 3.28084
                        let velMs = state[9] as? Double ?? 100
                        let spdKts = velMs * 1.94384
                        let hdg = state[10] as? Double ?? 180
                        
                        // Origin and destination are left nil on purpose. OpenSky's
                        // state vectors do not carry a flight plan, and this used to
                        // fill them from a per-region list of plausible airports
                        // picked at random — so a real aircraft was shown flying a
                        // route it had nothing to do with, on the *live* path, with
                        // the pill still reading "Live traffic".
                        //
                        // Squawk and vertical rate, by contrast, are genuinely in the
                        // state vector (indices 14 and 11) and were being discarded
                        // in favour of a hardcoded "1200" and a flat zero. They are
                        // read properly now.
                        let squawk = state.count > 14 ? state[14] as? String : nil
                        let verticalRateMs = state.count > 11 ? state[11] as? Double : nil

                        parsed.append(
                            LiveFlight(
                                icao24: icao,
                                callsign: callsign,
                                origin: nil,
                                destination: nil,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                altitude: altFt,
                                speed: spdKts,
                                heading: hdg,
                                verticalRate: verticalRateMs.map { $0 * 196.850394 },
                                squawk: squawk,
                                isTracked: false
                            )
                        )
                        realFlightCount += 1
                    }

                    // Accept the live OpenSky result only if it actually returned
                    // traffic. `parsed` is pre-seeded with tracked flights, so an
                    // empty or rate-limited response (states = []) would otherwise
                    // set `flights` to tracked-only and skip the simulated fallback,
                    // leaving just a couple of pins when zoomed out.
                    if realFlightCount > 0 {
                        DispatchQueue.main.async {
                            self.tileCache[tile] = CachedTile(flights: parsed, fetched: Date())
                            self.pruneTileCache()
                            self.applyFleet(parsed, source: .live)
                        }
                        return
                    }
                }
            } catch {}
            
            DispatchQueue.main.async {
                self.serveCachedOrNothing(tile: tile, center: center, latDelta: latDelta,
                                          lonDelta: lonDelta, targetCount: targetCount,
                                          reason: "Traffic feed returned nothing for this area")
            }
        }.resume()
    }
    
    /// Applies a fleet and records where it came from.
    /// Flights the pilot asked to track, kept across an outage as their last known
    /// position. These came from the real feed when it was reachable; nothing here
    /// is generated.
    private func trackedOnly() -> [LiveFlight] {
        activeFlights.filter { $0.isTracked }
    }

    private func applyFleet(_ fleet: [LiveFlight], source: TrafficSource) {
        activeFlights = fleet
        flights = fleet
        isLoading = false
        trafficSource = source
    }

    /// The fallback ladder: a stale-but-real cached tile beats invented traffic, and
    /// invented traffic beats an empty map — but each one says what it is.
    private func serveCachedOrNothing(tile: TileKey,
                                      center: CLLocationCoordinate2D,
                                      latDelta: Double, lonDelta: Double,
                                      targetCount: Int,
                                      reason: String) {
        if let cached = tileCache[tile] {
            let age = Date().timeIntervalSince(cached.fetched)
            if age < Self.tileUsableAge, !cached.flights.isEmpty {
                applyFleet(cached.flights, source: .cached(age: age))
                return
            }
        }
        // Nearest usable neighbouring tile, before giving up on real data.
        let neighbours = tileCache
            .filter { abs($0.key.lat - tile.lat) <= 1 && abs($0.key.lon - tile.lon) <= 1 }
            .filter { Date().timeIntervalSince($0.value.fetched) < Self.tileUsableAge && !$0.value.flights.isEmpty }
            .sorted { $0.value.fetched > $1.value.fetched }
        if let best = neighbours.first {
            applyFleet(best.value.flights, source: .cached(age: Date().timeIntervalSince(best.value.fetched)))
            return
        }

        // Nothing real to show. The map goes empty and the pill says why, rather
        // than filling the sky with invented aircraft.
        applyFleet(trackedOnly(), source: .unavailable(reason: reason))
    }

    /// OpenSky reports the remaining allowance in a response header; names have
    /// varied, so check the ones it has used rather than depending on one.
    private func recordQuota(from response: HTTPURLResponse) {
        let candidates = ["X-Rate-Limit-Remaining", "x-rate-limit-remaining",
                          "X-RateLimit-Remaining", "X-Rate-Limit-Retry-After-Seconds"]
        for name in candidates.prefix(3) {
            if let raw = response.value(forHTTPHeaderField: name), let value = Int(raw) {
                DispatchQueue.main.async { self.remainingCredits = value }
                return
            }
        }
    }

    /// Keeps the cache to a sane size — this is a convenience, not a database.
    private func pruneTileCache() {
        let cutoff = Date().addingTimeInterval(-Self.tileUsableAge)
        tileCache = tileCache.filter { $0.value.fetched > cutoff }
        if tileCache.count > 40 {
            let keep = tileCache.sorted { $0.value.fetched > $1.value.fetched }.prefix(40)
            tileCache = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    func startLiveUpdates() {
        timer?.invalidate()
        lastPositionUpdate = Date()
        // Live radar stream tick (see updateInterval).
        //
        // Added to .common run-loop modes deliberately: a default-mode timer is
        // starved while the map is being panned or zoomed, so traffic froze during
        // interaction and then lurched forward when the finger lifted.
        let tick = Timer(timeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateFlightPositions()
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }
    
    func stopLiveUpdates() {
        timer?.invalidate()
        timer = nil
    }
    
    func fetchLiveFlights() {
        updateFlightPositions()
    }
    
    private func updateFlightPositions() {
        guard isActive else { return }

        // Advance by the time that really passed, clamped so returning from the
        // background or a stalled run loop cannot fling aircraft across the map.
        let now = Date()
        let elapsed = min(max(now.timeIntervalSince(lastPositionUpdate), 0), updateInterval * 3)
        lastPositionUpdate = now
        guard elapsed > 0.01 else { return }

        let minLat = currentCenter.latitude - max(0.8, currentLatDelta * 0.6)
        let maxLat = currentCenter.latitude + max(0.8, currentLatDelta * 0.6)
        let minLon = currentCenter.longitude - max(0.8, currentLonDelta * 0.6)
        let maxLon = currentCenter.longitude + max(0.8, currentLonDelta * 0.6)

        let updated = activeFlights.compactMap { flight -> LiveFlight? in
            let speedKts = flight.speed ?? 250.0
            let headingDeg = flight.heading ?? 0.0
            let distNm = (speedKts / 3600.0) * elapsed
            let rad = headingDeg * .pi / 180.0

            let newLat = flight.coordinate.latitude + (distNm * cos(rad)) / 60.0
            let newLon = flight.coordinate.longitude + (distNm * sin(rad)) / (60.0 * cos(flight.coordinate.latitude * .pi / 180.0))

            // Aircraft that fly out of the area are dropped, not wrapped. The old
            // toroidal wrap teleported a flight leaving the top edge to the bottom
            // edge in a single tick — the jump that made traffic look glitchy.
            // Replacements are spawned by the region fleet builder instead.
            let margin = 0.15
            guard newLat > minLat - margin, newLat < maxLat + margin,
                  newLon > minLon - margin, newLon < maxLon + margin else { return nil }

            return LiveFlight(
                id: flight.id,
                icao24: flight.icao24,
                callsign: flight.callsign,
                origin: flight.origin,
                destination: flight.destination,
                coordinate: CLLocationCoordinate2D(latitude: newLat, longitude: newLon),
                altitude: flight.altitude,
                speed: flight.speed,
                heading: flight.heading,
                verticalRate: flight.verticalRate,
                squawk: flight.squawk,
                timestamp: Date(),
                isTracked: flight.isTracked
            )
        }
        
        self.activeFlights = updated

        // Extend the selected flight's trail with its new position (capped).
        var newTrail = self.trailPoints
        if let id = self.trailIcao24, let f = updated.first(where: { $0.icao24 == id }) {
            newTrail.append(f.coordinate)
            if newTrail.count > self.maxTrailPoints {
                newTrail.removeFirst(newTrail.count - self.maxTrailPoints)
            }
        }

        DispatchQueue.main.async {
            self.flights = updated
            self.trailPoints = newTrail
            self.isLoading = false
        }
    }
}

// MARK: - Live Flight Annotation View
class LiveFlightAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }
    
    private func setupView() {
        apply(tint: .systemGreen)
        canShowCallout = true
    }

    // MKAnnotationView draws `image` straight into its layer and never re-renders it
    // for a tint change, so a template symbol left untinted draws solid black. Bake
    // the resolved colour into the image instead of relying on tintColor.
    private func apply(tint: UIColor) {
        let resolved = tint.resolvedColor(with: traitCollection)
        tintColor = resolved
        image = UIImage(systemName: "airplane.circle.fill")?
            .withTintColor(resolved, renderingMode: .alwaysOriginal)
    }
    
    func update(with flight: LiveFlight) {
        // Update annotation appearance based on flight data
        if let altitude = flight.altitude {
            if altitude > 30000 {
                apply(tint: .systemBlue) // High altitude
            } else if altitude > 10000 {
                apply(tint: .systemGreen) // Medium altitude
            } else {
                apply(tint: .systemOrange) // Low altitude
            }
        }
        
        // Add callout information
        let hostingController = UIHostingController(rootView: LiveFlightCalloutView(flight: flight))
        detailCalloutAccessoryView = hostingController.view
    }
}

// MARK: - Live Flight Callout View
struct LiveFlightCalloutView: UIViewRepresentable {
    let flight: LiveFlight
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground
        view.layer.cornerRadius = 8
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.layer.shadowOpacity = 0.3
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Flight info
        if let callsign = flight.callsign {
            let callsignLabel = UILabel()
            callsignLabel.text = callsign
            callsignLabel.font = UIFont.boldSystemFont(ofSize: 14)
            stackView.addArrangedSubview(callsignLabel)
        }
        
        // Route info
        if let origin = flight.origin, let destination = flight.destination {
            let routeLabel = UILabel()
            routeLabel.text = "\(origin) → \(destination)"
            routeLabel.font = UIFont.systemFont(ofSize: 12)
            routeLabel.textColor = UIColor.secondaryLabel
            stackView.addArrangedSubview(routeLabel)
        }
        
        // Altitude and speed
        let infoLabel = UILabel()
        var infoText = ""
        if let altitude = flight.altitude {
            infoText += "FL\(Int(altitude/100))"
        }
        if let speed = flight.speed {
            infoText += " • \(Int(speed))kt"
        }
        infoLabel.text = infoText
        infoLabel.font = UIFont.systemFont(ofSize: 12)
        infoLabel.textColor = UIColor.secondaryLabel
        stackView.addArrangedSubview(infoLabel)
        
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update view if needed
    }
}
