import Foundation
import CoreLocation

/// Fetches real winds aloft along a route.
///
/// The app previously showed a "Winds Aloft" panel whose numbers were
/// `15 + index * 5` knots from `240 + index * 10` degrees — an arithmetic sequence
/// with no connection to place, altitude or time. That is exactly the kind of
/// plausible-looking invention a pilot might plan a fuel load around, so it is gone.
///
/// The source is Open-Meteo's pressure-level forecast, chosen because the app
/// already depends on it for terrain, it needs no key or account, it covers the
/// whole globe, and it reports the geopotential height of each pressure level — so
/// levels map to real altitudes instead of being assumed. Winds come back in knots
/// and degrees true, which is what the planner works in.
final class WindsAloftService: ObservableObject {
    @Published private(set) var field = WindField()
    @Published private(set) var freshness: DataFreshness = .unavailable
    @Published private(set) var isLoading = false

    /// Route signature the current field was fetched for, so panning or unrelated
    /// edits do not re-fetch.
    private var loadedSignature = ""
    private var task: Task<Void, Never>?

    /// Forecasts are issued hourly; an hour old is still the current forecast.
    private static let freshFor: TimeInterval = 60 * 60

    /// Pressure levels spanning the sky a light aircraft uses. 1000 hPa sits near
    /// the surface and 500 hPa near 18,000 ft, which brackets everything a
    /// non-turbocharged piston will see.
    private static let levels = [1000, 925, 850, 700, 600, 500]

    /// At most this many columns along the route. The weather model's own grid is
    /// coarser than a dense sample would suggest, so more points would buy
    /// resolution the forecast does not have — and one URL has to hold them all.
    private static let maxColumns = 8

    func load(for waypoints: [Waypoint], departureTime: Date, force: Bool = false) {
        guard waypoints.count >= 2 else {
            field = WindField(); freshness = .unavailable; loadedSignature = ""
            return
        }
        let points = Self.samplePoints(along: waypoints, limit: Self.maxColumns)
        let signature = points.map { String(format: "%.2f,%.2f", $0.latitude, $0.longitude) }
            .joined(separator: ";") + "@" + String(Int(departureTime.timeIntervalSince1970 / 3600))
        guard force || signature != loadedSignature else { return }
        loadedSignature = signature

        task?.cancel()
        task = Task { [weak self] in
            await self?.fetch(points: points, departureTime: departureTime)
        }
    }

    private func fetch(points: [CLLocationCoordinate2D], departureTime: Date) async {
        await publish { $0.isLoading = true }
        defer { Task { @MainActor [weak self] in self?.isLoading = false } }

        let hourly = Self.levels.flatMap {
            ["windspeed_\($0)hPa", "winddirection_\($0)hPa",
             "geopotential_height_\($0)hPa", "temperature_\($0)hPa"]
        }.joined(separator: ",")

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: points.map { String(format: "%.4f", $0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: points.map { String(format: "%.4f", $0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: hourly),
            URLQueryItem(name: "windspeed_unit", value: "kn"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "GMT")
        ]
        guard let url = components.url else { return }

        guard let result = await DataCache.shared.fetch(
            url, key: "winds-" + String(loadedSignature.hashValue), freshFor: Self.freshFor,
            timeout: 20, validate: { Self.decode($0) != nil })
        else {
            await publish { $0.field = WindField(); $0.freshness = .unavailable }
            return
        }

        guard let responses = Self.decode(result.data) else {
            await publish { $0.field = WindField(); $0.freshness = .unavailable }
            return
        }

        var columns: [WindColumn] = []
        for (index, response) in responses.enumerated() where index < points.count {
            if let column = response.column(at: points[index], nearest: departureTime) {
                columns.append(column)
            }
        }
        let state: DataFreshness = columns.isEmpty
            ? .unavailable
            : DataFreshness(age: result.age, fromCache: result.fromCache)
        await publish { $0.field = WindField(columns: columns); $0.freshness = state }
    }

    /// Published state is only ever written on the main queue, matching the other
    /// services MapState observes.
    private func publish(_ mutate: @escaping (WindsAloftService) -> Void) async {
        await MainActor.run { mutate(self) }
    }

    // MARK: Decoding

    /// Open-Meteo returns a bare object for one coordinate and an array for several.
    /// Normalised here so the caller never has to care.
    private static func decode(_ data: Data) -> [Response]? {
        let decoder = JSONDecoder()
        if let many = try? decoder.decode([Response].self, from: data), !many.isEmpty { return many }
        if let one = try? decoder.decode(Response.self, from: data) { return [one] }
        return nil
    }

    private struct Response: Decodable {
        let hourly: [String: [Double?]]

        private enum CodingKeys: String, CodingKey { case hourly }

        init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: CodingKeys.self)
            // The `hourly` object mixes a time array with per-level arrays, all of
            // them numeric, so it decodes uniformly as [String: [Double?]] — nulls
            // included, because a level can be missing at a given hour.
            hourly = try root.decode([String: [Double?]].self, forKey: .hourly)
        }

        /// Builds the column for whichever forecast hour is closest to the time the
        /// aircraft will actually be there.
        func column(at coordinate: CLLocationCoordinate2D, nearest date: Date) -> WindColumn? {
            guard let times = hourly["time"]?.compactMap({ $0 }), !times.isEmpty else { return nil }
            let target = date.timeIntervalSince1970
            var index = 0
            var bestGap = Double.greatestFiniteMagnitude
            for (i, t) in times.enumerated() {
                let gap = abs(t - target)
                if gap < bestGap { bestGap = gap; index = i }
            }

            var levels: [WindLevel] = []
            for hPa in WindsAloftService.levels {
                guard let heights = hourly["geopotential_height_\(hPa)hPa"], index < heights.count,
                      let metres = heights[index],
                      let speeds = hourly["windspeed_\(hPa)hPa"], let speed = speeds[index],
                      let dirs = hourly["winddirection_\(hPa)hPa"], let dir = dirs[index]
                else { continue }
                let temp = hourly["temperature_\(hPa)hPa"].flatMap { index < $0.count ? $0[index] : nil }
                levels.append(WindLevel(altitudeFT: metres * 3.280839895,
                                        directionTrue: dir,
                                        speedKT: speed,
                                        temperatureC: temp))
            }
            guard !levels.isEmpty else { return nil }
            return WindColumn(coordinate: coordinate,
                              validAt: Date(timeIntervalSince1970: times[index]),
                              levels: levels.sorted { $0.altitudeFT < $1.altitudeFT })
        }
    }

    // MARK: Sampling

    /// Points spread evenly along the track, always including both ends.
    static func samplePoints(along waypoints: [Waypoint], limit: Int) -> [CLLocationCoordinate2D] {
        guard waypoints.count >= 2 else { return waypoints.map(\.coordinate) }
        var cumulative: [Double] = [0]
        for i in 1..<waypoints.count {
            cumulative.append(cumulative[i - 1]
                + AltitudePlanner.distanceNM(waypoints[i - 1].coordinate, waypoints[i].coordinate))
        }
        let total = cumulative.last ?? 0
        guard total > 0 else { return [waypoints[0].coordinate] }

        // Short hops do not need eight columns; one every 40 NM is finer than the
        // forecast grid already.
        let wanted = max(2, min(limit, Int(total / 40) + 2))
        return (0..<wanted).map { step in
            let target = total * Double(step) / Double(wanted - 1)
            return Self.coordinate(along: waypoints, cumulative: cumulative, at: target)
        }
    }

    private static func coordinate(along waypoints: [Waypoint],
                                   cumulative: [Double],
                                   at distance: Double) -> CLLocationCoordinate2D {
        guard let last = cumulative.last, distance > 0 else { return waypoints[0].coordinate }
        if distance >= last { return waypoints[waypoints.count - 1].coordinate }
        for i in 1..<cumulative.count where distance <= cumulative[i] {
            let span = cumulative[i] - cumulative[i - 1]
            let t = span > 0 ? (distance - cumulative[i - 1]) / span : 0
            let a = waypoints[i - 1].coordinate, b = waypoints[i].coordinate
            return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                          longitude: a.longitude + (b.longitude - a.longitude) * t)
        }
        return waypoints[waypoints.count - 1].coordinate
    }
}
