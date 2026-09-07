import Foundation
import CoreLocation

/// Wind, and what it does to a flight plan.
///
/// Before this existed the planner computed every time and fuel figure at *true
/// airspeed* — that is, it assumed the air was still. For a 120 kt trainer a
/// routine 20 kt headwind is a 20% error in time and therefore in fuel, and it is
/// worst on exactly the leg where it matters: the long one into wind, at the end
/// of the day, planned against a 30-minute reserve. Still-air planning does not
/// merely lose accuracy, it loses it in the unsafe direction.
///
/// Everything here is true-north referenced, matching the rest of the planner.
/// Wind direction follows the meteorological convention: the direction the wind is
/// coming *from*.

// MARK: - The wind triangle

/// The classic navigation triangle: what a given wind does to a given course.
enum WindTriangle {
    /// Folds any angle into [0, 360). Both a raw sum and a `truncatingRemainder`
    /// can land outside it — a left drift correction off a course of 010° gives
    /// -10°, which must read as 350° and not as a negative heading.
    static func normalized(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    struct Solution {
        /// Speed over the ground. This, not TAS, is what a flight plan runs on.
        let groundSpeedKT: Double
        /// Positive into wind, negative with it.
        let headwindKT: Double
        /// Positive from the right.
        let crosswindKT: Double
        /// Wind correction angle — how far the nose is turned off the course to
        /// hold the track, in degrees, positive to the right.
        let wcaDegrees: Double
        /// The heading to fly to make good the course.
        let headingTrue: Double
    }

    /// Solves for ground speed and drift.
    ///
    /// - Parameters:
    ///   - courseTrue: the track to be made good, degrees true.
    ///   - trueAirspeedKT: aircraft speed through the air.
    ///   - windFromTrue: direction the wind blows *from*, degrees true.
    ///   - windSpeedKT: wind speed.
    static func solve(courseTrue: Double,
                      trueAirspeedKT: Double,
                      windFromTrue: Double,
                      windSpeedKT: Double) -> Solution {
        guard trueAirspeedKT > 0 else {
            return Solution(groundSpeedKT: 0, headwindKT: 0, crosswindKT: 0,
                            wcaDegrees: 0, headingTrue: courseTrue)
        }
        let theta = (windFromTrue - courseTrue) * .pi / 180
        let headwind = windSpeedKT * cos(theta)
        let crosswind = windSpeedKT * sin(theta)

        // A crosswind larger than TAS cannot be crabbed out — the aircraft cannot
        // hold the track at all. Clamping keeps asin defined; the caller sees the
        // resulting ground speed collapse, which is the honest answer.
        let sinWCA = max(-1, min(1, crosswind / trueAirspeedKT))
        let wca = asin(sinWCA)
        let groundSpeed = trueAirspeedKT * cos(wca) - headwind

        return Solution(groundSpeedKT: max(groundSpeed, 0),
                        headwindKT: headwind,
                        crosswindKT: crosswind,
                        wcaDegrees: wca * 180 / .pi,
                        headingTrue: normalized(courseTrue + wca * 180 / .pi))
    }
}

// MARK: - The field

/// Wind at one altitude, at one place and time.
struct WindLevel {
    let altitudeFT: Double
    let directionTrue: Double
    let speedKT: Double
    /// Outside air temperature, when the source reports it. Carried because it is
    /// what turns an indicated altitude into a density altitude later.
    var temperatureC: Double?
}

/// The vertical stack of winds over one point, at one forecast hour.
struct WindColumn {
    let coordinate: CLLocationCoordinate2D
    let validAt: Date
    /// Ascending by altitude.
    let levels: [WindLevel]

    /// Wind at an arbitrary altitude, linearly interpolated between the reported
    /// levels and held constant outside them.
    ///
    /// Interpolating direction needs care: the mean of 350° and 010° is 0°, not
    /// 180°, so the two are blended as vectors rather than as numbers.
    func wind(atFT altitude: Double) -> (directionTrue: Double, speedKT: Double)? {
        guard !levels.isEmpty else { return nil }
        if levels.count == 1 || altitude <= levels[0].altitudeFT {
            return (levels[0].directionTrue, levels[0].speedKT)
        }
        if let last = levels.last, altitude >= last.altitudeFT {
            return (last.directionTrue, last.speedKT)
        }
        for i in 1..<levels.count where altitude <= levels[i].altitudeFT {
            let lower = levels[i - 1], upper = levels[i]
            let span = upper.altitudeFT - lower.altitudeFT
            let t = span > 0 ? (altitude - lower.altitudeFT) / span : 0
            return (Self.blendDirection(lower.directionTrue, upper.directionTrue, t),
                    lower.speedKT + (upper.speedKT - lower.speedKT) * t)
        }
        return (levels[levels.count - 1].directionTrue, levels[levels.count - 1].speedKT)
    }

    /// Blends two compass directions the short way round, via unit vectors.
    static func blendDirection(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let ra = a * .pi / 180, rb = b * .pi / 180
        let x = cos(ra) * (1 - t) + cos(rb) * t
        let y = sin(ra) * (1 - t) + sin(rb) * t
        guard x != 0 || y != 0 else { return a }
        return WindTriangle.normalized(atan2(y, x) * 180 / .pi)
    }
}

/// Winds sampled at several points along a route.
///
/// Nearest-column lookup rather than horizontal interpolation: the columns are
/// spaced along the track at a resolution far finer than the weather model's own,
/// so blending between them would invent detail the forecast does not contain.
struct WindField {
    var columns: [WindColumn] = []

    var isEmpty: Bool { columns.isEmpty }

    func wind(at coordinate: CLLocationCoordinate2D,
              altitudeFT: Double) -> (directionTrue: Double, speedKT: Double)? {
        guard !columns.isEmpty else { return nil }
        var best: (distance: Double, column: WindColumn)?
        for column in columns {
            let dLat = column.coordinate.latitude - coordinate.latitude
            let dLon = column.coordinate.longitude - coordinate.longitude
            let d = dLat * dLat + dLon * dLon
            if best == nil || d < best!.distance { best = (d, column) }
        }
        return best?.column.wind(atFT: altitudeFT)
    }

    /// Ground speed for a segment, falling back to still air when there is no
    /// forecast for it. The fallback is the old behaviour, and it is deliberately
    /// visible to the caller through `hasWind` so the UI can say which it used
    /// rather than presenting a still-air number as though it were a wind-corrected one.
    func solution(courseTrue: Double,
                  trueAirspeedKT: Double,
                  at coordinate: CLLocationCoordinate2D,
                  altitudeFT: Double) -> WindTriangle.Solution? {
        guard let w = wind(at: coordinate, altitudeFT: altitudeFT) else { return nil }
        return WindTriangle.solve(courseTrue: courseTrue,
                                  trueAirspeedKT: trueAirspeedKT,
                                  windFromTrue: w.directionTrue,
                                  windSpeedKT: w.speedKT)
    }
}
