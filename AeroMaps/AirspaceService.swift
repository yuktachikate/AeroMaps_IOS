import Foundation
import MapKit
import Combine

/// A piece of controlled airspace, as published.
struct AirspaceVolume: Identifiable {
    let id: String
    let name: String
    /// "B", "C", "D", "E" — nil for Mode C veils and other non-class volumes.
    let airspaceClass: String?
    let localType: String?
    let lowerFT: Int?
    let upperFT: Int?
    let polygon: [CLLocationCoordinate2D]
    /// Precomputed extent. Filtering "is this on screen" by walking every vertex of
    /// every volume on each map update was millions of comparisons a frame; a box
    /// test answers the same question in four.
    let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double

    func intersects(centerLat: Double, centerLon: Double, latSpan: Double, lonSpan: Double) -> Bool {
        !(maxLat < centerLat - latSpan || minLat > centerLat + latSpan ||
          maxLon < centerLon - lonSpan || minLon > centerLon + lonSpan)
    }

    /// The shelf label a pilot reads off a sectional: ceiling over floor.
    var altitudeLabel: String {
        let top = upperFT.map { "\($0.formatted())" } ?? "—"
        let bottom = (lowerFT ?? 0) == 0 ? "SFC" : "\((lowerFT ?? 0).formatted())"
        return "\(top) / \(bottom)"
    }

    var displayClass: String {
        if let airspaceClass, !airspaceClass.isEmpty { return "Class \(airspaceClass)" }
        return localType ?? "Airspace"
    }

    /// What entering this airspace actually requires of a VFR pilot.
    ///
    /// These are radio and clearance requirements met in flight, not something an
    /// app can grant — so the planner's job is to say what will be needed, not to
    /// route around it unasked.
    var entryRequirement: String? {
        switch airspaceClass {
        case "B":
            return "ATC clearance required — you must hear \"cleared into the Class Bravo\" before entering."
        case "C":
            return "Two-way radio communication must be established with approach before entering."
        case "D":
            return "Two-way radio communication must be established with the tower before entering."
        default:
            return nil
        }
    }

    /// Class B carries an extra restriction that matters to a training operation.
    var hasStudentPilotRestriction: Bool { airspaceClass == "B" }

    /// True when a planned altitude sits inside this volume's vertical limits.
    func contains(altitudeFT: Int) -> Bool {
        altitudeFT >= (lowerFT ?? 0) && altitudeFT <= (upperFT ?? 60_000)
    }

    func contains(_ point: CLLocationCoordinate2D) -> Bool {
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
}

/// Real controlled airspace from the FAA's Aeronautical Information Services
/// feature service.
///
/// Chosen because it is authoritative, published on the 56-day cycle, and needs no
/// key or account. It covers the United States only — which is where this app's
/// users mostly fly — and the map says so rather than drawing nothing and letting
/// an empty screen imply clear air.
///
/// This replaces two hardcoded circles at SFO and SJC that were drawn everywhere in
/// the world regardless of where the map was.
final class AirspaceService: ObservableObject {

    private static let endpoint =
        "https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/arcgis/rest/services/Class_Airspace/FeatureServer/0/query"

    /// Airspace changes on a 56-day cycle, so a cached tile stays good for a long
    /// while — and staying usable offline matters more than being minutes-fresh.
    private static let tileFreshness: TimeInterval = 14 * 24 * 3600
    /// Above this span there is too much airspace to draw usefully.
    static let maxSpanDegrees: Double = 3.0
    /// Airspace is fetched, keyed and cached on one grid.
    ///
    /// The cache key used to be a 1° cell while the query covered a 3° box, so
    /// panning across three adjacent keys issued three heavily overlapping queries
    /// for substantially the same airspace — roughly triple the download, and
    /// triple the request units charged against a service that rate limits on them.
    private static let cellDegrees: Double = 3
    /// Overlap between neighbouring cells, so airspace straddling a cell edge is
    /// present before the next cell has been fetched.
    /// A 3.5° envelope measured at ~6.5 s and 176 KB for 139 volumes over central
    /// California — comfortably inside the record cap, with overlap enough that
    /// airspace on a cell boundary is already present.
    private static let cellPaddingDegrees: Double = 0.25

    @Published private(set) var volumes: [AirspaceVolume] = []
    @Published private(set) var freshness: DataFreshness = .unavailable
    @Published private(set) var isLoading = false
    /// Set when the service capped the response. Airspace quietly missing from a
    /// map is worse than airspace that says it is incomplete.
    @Published private(set) var isTruncated = false

    private var loadedTiles: Set<String> = []
    /// The service is rate limited (roughly 6,000 request units a minute, shared).
    /// Retrying a rejected tile on the next frame — which is what a naive failure
    /// path does — keeps the app permanently over that limit, so failures back off.
    private var retryAfter: Date?
    private var cache: [String: [AirspaceVolume]] = [:]
    private var task: Task<Void, Never>?

    /// Loads airspace for the visible area, one 1°×1° tile at a time so panning
    /// reuses what is already held.
    func load(around center: CLLocationCoordinate2D, spanDegrees: Double) {
        guard spanDegrees <= Self.maxSpanDegrees else {
            // Zoomed too far out to draw meaningfully; keep what we have.
            return
        }
        if let retryAfter, Date() < retryAfter { return }
        let tile = tileKey(center)
        guard !loadedTiles.contains(tile) else { return }
        loadedTiles.insert(tile)

        task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.isLoading = true }
            defer { Task { @MainActor in self.isLoading = false } }

            let origin = Self.cellOrigin(center)
            let pad = Self.cellPaddingDegrees
            let minX = origin.lon - pad, maxX = origin.lon + Self.cellDegrees + pad
            let minY = origin.lat - pad, maxY = origin.lat + Self.cellDegrees + pad
            let envelope = #"{"xmin":\#(minX),"ymin":\#(minY),"xmax":\#(maxX),"ymax":\#(maxY),"spatialReference":{"wkid":4326}}"#

            var components = URLComponents(string: Self.endpoint)!
            components.queryItems = [
                URLQueryItem(name: "geometry", value: envelope),
                URLQueryItem(name: "geometryType", value: "esriGeometryEnvelope"),
                URLQueryItem(name: "inSR", value: "4326"),
                URLQueryItem(name: "outSR", value: "4326"),
                URLQueryItem(name: "spatialRel", value: "esriSpatialRelIntersects"),
                URLQueryItem(name: "outFields", value: "NAME,CLASS,LOCAL_TYPE,LOWER_VAL,UPPER_VAL,IDENT"),
                URLQueryItem(name: "returnGeometry", value: "true"),
                URLQueryItem(name: "resultRecordCount", value: "600"),
                // Simplify server-side. Full-fidelity boundaries came back at 9–11 MB
                // a tile — a Mode C veil alone is ~1,700 vertices — which is far more
                // precision than a moving map can draw or a phone should download.
                URLQueryItem(name: "maxAllowableOffset", value: "0.002"),
                URLQueryItem(name: "geometryPrecision", value: "5"),
                URLQueryItem(name: "f", value: "geojson")
            ]
            guard let url = components.url else { return }

            guard let result = await DataCache.shared.fetch(
                // Generous timeout: a cell-sized query measured at ~6.5 s normally,
                // but the service slows markedly when it is busy, and a timeout here
                // costs a whole cell of airspace.
                url, key: "airspace-\(tile)", freshFor: Self.tileFreshness, timeout: 45,
                validate: { Self.isFeatureCollection($0) }) else {
                await MainActor.run {
                    self.loadedTiles.remove(tile)
                    self.retryAfter = Date().addingTimeInterval(70)
                    if self.volumes.isEmpty { self.freshness = .unavailable }
                }
                return
            }
            guard let parsed = Self.decode(result.data) else {
                await MainActor.run {
                    self.loadedTiles.remove(tile)
                    self.retryAfter = Date().addingTimeInterval(70)
                    if self.volumes.isEmpty { self.freshness = .unavailable }
                }
                return
            }

            let truncated = Self.wasTruncated(result.data)
            await MainActor.run {
                self.cache[tile] = parsed
                self.isTruncated = self.isTruncated || truncated
                self.rebuild()
                self.freshness = DataFreshness(age: result.age, fromCache: result.fromCache)
            }
        }
    }

    /// Loads every tile the route passes through, so a check covers the whole
    /// route rather than only what the map happens to be showing.
    func load(along waypoints: [Waypoint]) {
        guard waypoints.count >= 2 else { return }
        var cumulative: [Double] = [0]
        for i in 1..<waypoints.count {
            cumulative.append(cumulative[i - 1] + AltitudePlanner.distanceNM(waypoints[i - 1].coordinate,
                                                                            waypoints[i].coordinate))
        }
        let total = cumulative.last ?? 0
        guard total > 0 else { return }

        // One sample every ~60 NM is enough to hit each cell the route crosses.
        var seen = Set<String>()
        let steps = max(Int(total / 60), 1)
        for i in 0...steps {
            let coord = AltitudePlanner.coordinate(along: waypoints, cumulative: cumulative,
                                                   atDistance: total * Double(i) / Double(steps))
            let key = tileKey(coord)
            guard seen.insert(key).inserted else { continue }
            load(around: coord, spanDegrees: 1.0)
        }
    }

    /// Controlled airspace a point at a given altitude sits inside.
    func volumes(containing coordinate: CLLocationCoordinate2D, altitudeFT: Int) -> [AirspaceVolume] {
        volumes.filter { volume in
            volume.airspaceClass?.isEmpty == false
            && volume.contains(altitudeFT: altitudeFT)
            && volume.contains(coordinate)
        }
    }

    /// True only for a real GeoJSON FeatureCollection. ArcGIS answers rate limits
    /// and bad queries with a 200 and `{"error":{...}}`, which must never reach the
    /// cache — an error stored under a 14-day freshness window would keep airspace
    /// blank for a fortnight.
    /// ArcGIS reports a capped result set rather than failing, so it has to be
    /// checked for explicitly.
    private static func wasTruncated(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (root["exceededTransferLimit"] as? Bool) == true
            || (root["properties"] as? [String: Any])?["exceededTransferLimit"] as? Bool == true
    }

    private static func isFeatureCollection(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if root["error"] != nil { return false }
        return root["features"] is [Any]
    }

    private func rebuild() {
        var seen = Set<String>()
        var merged: [AirspaceVolume] = []
        for volume in cache.values.flatMap({ $0 }) where seen.insert(volume.id).inserted {
            merged.append(volume)
        }
        volumes = merged
    }

    /// Bottom-left corner of the grid cell a coordinate falls in.
    private static func cellOrigin(_ c: CLLocationCoordinate2D) -> (lat: Double, lon: Double) {
        (floor(c.latitude / cellDegrees) * cellDegrees,
         floor(c.longitude / cellDegrees) * cellDegrees)
    }

    private func tileKey(_ c: CLLocationCoordinate2D) -> String {
        let origin = Self.cellOrigin(c)
        return "\(Int(origin.lat))_\(Int(origin.lon))"
    }

    // MARK: Decoding

    private struct GeoJSON: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                let NAME: String?
                let CLASS: String?
                let LOCAL_TYPE: String?
                let LOWER_VAL: Double?
                let UPPER_VAL: Double?
                let IDENT: String?
            }
            struct Geometry: Decodable {
                let type: String?
                let coordinates: Coordinates?
            }
            /// ArcGIS returns Polygon and MultiPolygon; nesting differs by one level.
            enum Coordinates: Decodable {
                case polygon([[[Double]]])
                case multi([[[[Double]]]])
                init(from decoder: Decoder) throws {
                    let c = try decoder.singleValueContainer()
                    if let p = try? c.decode([[[Double]]].self) { self = .polygon(p) }
                    else { self = .multi(try c.decode([[[[Double]]]].self)) }
                }
                var rings: [[[Double]]] {
                    switch self {
                    case .polygon(let p): return p
                    case .multi(let m): return m.flatMap { $0 }
                    }
                }
            }
            let properties: Properties
            let geometry: Geometry?
        }
        let features: [Feature]
    }

    private static func decode(_ data: Data) -> [AirspaceVolume]? {
        guard let file = try? JSONDecoder().decode(GeoJSON.self, from: data) else { return nil }
        var out: [AirspaceVolume] = []

        for (index, feature) in file.features.enumerated() {
            guard let rings = feature.geometry?.coordinates?.rings, let outer = rings.first else { continue }
            let points = outer.compactMap { pair -> CLLocationCoordinate2D? in
                guard pair.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
            guard points.count >= 3 else { continue }

            let lats = points.map(\.latitude), lons = points.map(\.longitude)
            let p = feature.properties
            out.append(AirspaceVolume(
                id: "\(p.IDENT ?? p.NAME ?? "ASP")-\(p.LOWER_VAL.map { Int($0) } ?? 0)-\(index)",
                name: (p.NAME ?? "Airspace").capitalized,
                airspaceClass: p.CLASS?.trimmingCharacters(in: .whitespaces),
                localType: p.LOCAL_TYPE,
                lowerFT: p.LOWER_VAL.map { Int($0) },
                upperFT: p.UPPER_VAL.map { Int($0) },
                polygon: points,
                minLat: lats.min() ?? 0, maxLat: lats.max() ?? 0,
                minLon: lons.min() ?? 0, maxLon: lons.max() ?? 0))
        }
        return out
    }
}

/// An airspace polygon on the map, carrying the class so the renderer can colour it
/// the way a sectional does.
final class AirspaceOverlay: MKPolygon {
    var airspaceClass: String?
    var volumeTitle: String?
    /// Identity of the volume this overlay draws, so the map can tell which
    /// polygons it already has and leave them alone.
    var volumeID: String = ""

    static func make(from volume: AirspaceVolume) -> AirspaceOverlay {
        var coords = volume.polygon
        let overlay = AirspaceOverlay(coordinates: &coords, count: coords.count)
        overlay.airspaceClass = volume.airspaceClass
        overlay.volumeID = volume.id
        overlay.volumeTitle = "\(volume.displayClass) · \(volume.name) · \(volume.altitudeLabel)"
        return overlay
    }

    /// Sectional convention: Class B in blue, C in magenta, D dashed blue.
    var strokeColor: UIColor {
        switch airspaceClass {
        case "B": return .systemBlue
        case "C": return .systemPink
        case "D": return .systemTeal
        case "E": return .systemPurple
        default:  return .systemGray
        }
    }
}
