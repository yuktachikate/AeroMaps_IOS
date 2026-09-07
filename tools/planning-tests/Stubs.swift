import Foundation
import CoreLocation
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

// Minimal stand-ins so the pure planning engine can be exercised off-device.
// Only the members Waypoint.swift actually touches.
struct Airport {
    let icao: String, name: String
    let coordinate: CLLocationCoordinate2D
    let elevation: Int
}
struct AirportCatalog {
    var byIdent: [String: Airport] = [:]
    subscript(key: String) -> Airport? { byIdent[key] }
}
