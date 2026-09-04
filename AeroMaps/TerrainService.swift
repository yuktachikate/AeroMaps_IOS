import Foundation
import CoreLocation

/// Terrain elevations sampled along a route, used to set a safe cruise altitude and
/// to draw the ground under the vertical profile.
///
/// Sampling is sparse by design — one point roughly every 1/120th of the route —
/// so `elevationFT(at:)` answers with the nearest sample rather than an exact
/// lookup. That is the right resolution for "how high is the rock under this leg",
/// not for terrain-following guidance.
struct TerrainSampler {
    struct Sample {
        let coordinate: CLLocationCoordinate2D
        let elevationFT: Double
    }

    private(set) var samples: [Sample] = []

    var isEmpty: Bool { samples.isEmpty }

    init(samples: [Sample] = []) {
        self.samples = samples
    }

    func elevationFT(at coordinate: CLLocationCoordinate2D) -> Double? {
        guard !samples.isEmpty else { return nil }
        var best: (distance: Double, elevation: Double)?
        for sample in samples {
            let dLat = sample.coordinate.latitude - coordinate.latitude
            let dLon = sample.coordinate.longitude - coordinate.longitude
            let d = dLat * dLat + dLon * dLon
            if best == nil || d < best!.distance { best = (d, sample.elevationFT) }
        }
        return best?.elevation
    }

    func peakElevationFT(along waypoints: [Waypoint]) -> Double? {
        samples.map(\.elevationFT).max()
    }
}

/// Fetches terrain elevations from Open-Meteo's elevation endpoint.
///
/// Chosen because it needs no API key and no account — the app stays runnable from
/// a fresh clone. When the request fails (offline, rate-limited) the profile simply
/// renders without a ground layer and altitude suggestions fall back to field
/// elevations, which is why every terrain value in the planner is optional.
final class TerrainService: ObservableObject {
    @Published private(set) var sampler = TerrainSampler()
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    /// Route signature the current samples were fetched for, so panning or editing
    /// unrelated state does not re-fetch.
    private var loadedSignature: String = ""
    private var task: Task<Void, Never>?

    private static let maxPointsPerRequest = 100

    func loadTerrain(for waypoints: [Waypoint], force: Bool = false) {
        let signature = waypoints.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" }
            .joined(separator: "|")
        guard waypoints.count >= 2 else {
            sampler = TerrainSampler()
            loadedSignature = ""
            return
        }
        guard force || signature != loadedSignature else { return }

        task?.cancel()
        loadedSignature = signature
        isLoading = true
        lastError = nil

        let coordinates = Self.samplePoints(along: waypoints, count: Self.maxPointsPerRequest)
        task = Task { [weak self] in
            do {
                let elevations = try await Self.fetchElevations(coordinates)
                guard !Task.isCancelled else { return }
                let samples = zip(coordinates, elevations).map {
                    TerrainSampler.Sample(coordinate: $0.0, elevationFT: $0.1 * 3.28084)
                }
                await MainActor.run { [weak self] in
                    self?.sampler = TerrainSampler(samples: samples)
                    self?.isLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.isLoading = false
                    self?.lastError = "Terrain unavailable"
                }
            }
        }
    }

    func clear() {
        task?.cancel()
        sampler = TerrainSampler()
        loadedSignature = ""
        isLoading = false
    }

    /// Samples terrain along an arbitrary track without disturbing the route's own
    /// cached samples — used by the route generator to survey a track it is still
    /// deciding on.
    static func sampler(for waypoints: [Waypoint]) async throws -> TerrainSampler {
        guard waypoints.count >= 2 else { return TerrainSampler() }
        let coordinates = samplePoints(along: waypoints, count: maxPointsPerRequest)
        let elevations = try await fetchElevations(coordinates)
        return TerrainSampler(samples: zip(coordinates, elevations).map {
            TerrainSampler.Sample(coordinate: $0.0, elevationFT: $0.1 * 3.28084)
        })
    }

    /// Evenly spaced points along the route's legs.
    private static func samplePoints(along waypoints: [Waypoint], count: Int) -> [CLLocationCoordinate2D] {
        var cumulative: [Double] = [0]
        for i in 1..<waypoints.count {
            cumulative.append(cumulative[i - 1] + AltitudePlanner.distanceNM(waypoints[i - 1].coordinate,
                                                                            waypoints[i].coordinate))
        }
        let total = cumulative.last ?? 0
        guard total > 0 else { return waypoints.map(\.coordinate) }
        return (0..<count).map { i in
            AltitudePlanner.coordinate(along: waypoints, cumulative: cumulative,
                                       atDistance: total * Double(i) / Double(count - 1))
        }
    }

    private struct ElevationResponse: Decodable { let elevation: [Double] }

    private static func fetchElevations(_ coordinates: [CLLocationCoordinate2D]) async throws -> [Double] {
        let lats = coordinates.map { String(format: "%.4f", $0.latitude) }.joined(separator: ",")
        let lons = coordinates.map { String(format: "%.4f", $0.longitude) }.joined(separator: ",")
        var components = URLComponents(string: "https://api.open-meteo.com/v1/elevation")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: lats),
            URLQueryItem(name: "longitude", value: lons)
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ElevationResponse.self, from: data)
        guard decoded.elevation.count == coordinates.count else { throw URLError(.cannotParseResponse) }
        return decoded.elevation
    }
}
