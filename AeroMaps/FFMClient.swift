import Foundation
import CoreLocation
import MapKit

// MARK: - FFM Client Models

struct FFMRequest: Codable {
    struct Aircraft: Codable {
        let type: String
        let trueAirspeedKTAS: Double
        let fuelBurnGPH: Double
    }
    struct Waypoint: Codable {
        let lat: Double
        let lon: Double
    }
    struct Policy: Codable {
        let reserveMinutes: Int
        let enforceMEF: Bool
    }
    let aircraft: Aircraft
    let route: [Waypoint]
    let policy: Policy
}

struct FFMResponse: Codable {
    struct Coordinate: Codable { let lat: Double; let lon: Double }
    struct LegRisk: Codable {
        let fromIndex: Int
        let toIndex: Int
        let icing: Double
        let turbulence: Double
        let terrain: Double
    }
    let polyline: [Coordinate]
    let legRisks: [LegRisk]
    let alternates: [String]
    let advisory: String
    let riskTileTemplates: [String]
}

// MARK: - FFM Client

final class FFMClient {
    private let baseURL: URL?
    private let useMockDefault: Bool
    init(baseURL: URL? = nil, useMockDefault: Bool? = nil) {
        if let baseURL = baseURL {
            self.baseURL = baseURL
        } else if let urlString = Bundle.main.object(forInfoDictionaryKey: "FFMBaseURL") as? String,
                  let url = URL(string: urlString) {
            self.baseURL = url
        } else {
            self.baseURL = URL(string: "http://localhost:8080")
        }
        if let useMockDefault = useMockDefault {
            self.useMockDefault = useMockDefault
        } else if let flag = Bundle.main.object(forInfoDictionaryKey: "FFMUseMock") as? Bool {
            self.useMockDefault = flag
        } else {
            self.useMockDefault = true
        }
    }

    func plan(request: FFMRequest, useMock: Bool? = nil) async throws -> FFMResponse {
        let shouldMock = useMock ?? useMockDefault
        if shouldMock {
            if let url = Bundle.main.url(forResource: "ffm_mock_response", withExtension: "json") {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(FFMResponse.self, from: data)
            }
            // Fallback to embedded mock
            let data = Data(Self.embeddedMock.utf8)
            return try JSONDecoder().decode(FFMResponse.self, from: data)
        }

        guard let baseURL else {
            throw URLError(.badURL)
        }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("/v1/plan"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(FFMResponse.self, from: data)
    }

    private static let embeddedMock = """
    {
      "polyline": [
        {"lat": 37.6213, "lon": -122.3790},
        {"lat": 37.3639, "lon": -121.9289}
      ],
      "legRisks": [
        {"fromIndex": 0, "toIndex": 1, "icing": 0.2, "turbulence": 0.4, "terrain": 0.1}
      ],
      "alternates": ["KOAK", "KSQL"],
      "advisory": "Moderate turbulence forecast along the route. Consider lower altitude after SUU.",
      "riskTileTemplates": [
        "https://tile.openweathermap.org/map/precipitation_new/{z}/{x}/{y}.png?appid=demo"
      ]
    }
    """
}

// MARK: - Helpers

extension Array where Element == FFMResponse.Coordinate {
    func toPolyline() -> MKPolyline {
        let coords = self.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        return MKPolyline(coordinates: coords, count: coords.count)
    }
}


