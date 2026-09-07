import Foundation
import CoreLocation
var pass = 0, fail = 0
func check(_ n: String, _ ok: Bool) { ok ? (pass += 1) : (fail += 1); print("  \(ok ? "PASS" : "FAIL")  \(n)") }
func near(_ a: Double, _ b: Double, _ t: Double = 0.5) -> Bool { abs(a-b) <= t }

print("Wind triangle")
let hw = WindTriangle.solve(courseTrue: 0, trueAirspeedKT: 120, windFromTrue: 0, windSpeedKT: 20)
check("headwind GS 100", near(hw.groundSpeedKT, 100))
let tw = WindTriangle.solve(courseTrue: 0, trueAirspeedKT: 120, windFromTrue: 180, windSpeedKT: 20)
check("tailwind GS 140", near(tw.groundSpeedKT, 140))
let xw = WindTriangle.solve(courseTrue: 0, trueAirspeedKT: 120, windFromTrue: 90, windSpeedKT: 20)
check("crosswind GS 118.3", near(xw.groundSpeedKT, 118.32))
check("crosswind WCA 9.59", near(xw.wcaDegrees, 9.59))
let neg = WindTriangle.solve(courseTrue: 10, trueAirspeedKT: 100, windFromTrue: 280, windSpeedKT: 30)
check("negative heading wraps to 352.5", near(neg.headingTrue, 352.54))
check("gale vs TAS does not NaN", WindTriangle.solve(courseTrue: 0, trueAirspeedKT: 20, windFromTrue: 90, windSpeedKT: 60).groundSpeedKT.isFinite)

print("Direction blending")
check("350/010 blends to ~0 not 180", { let d = WindColumn.blendDirection(350, 10, 0.5); return d > 359 || d < 1 }())

print("Profile with wind")
func wp(_ id: String, _ la: Double, _ lo: Double, _ e: Int) -> Waypoint {
    Waypoint(ident: id, name: id, coordinate: .init(latitude: la, longitude: lo), kind: .airport, fieldElevationFT: e, airportICAO: id) }
var perf = AircraftPerformance(); perf.cruiseKTAS = 120; perf.fuelBurnGPH = 8.5
let ksfo = wp("KSFO", 37.6188, -122.3750, 13), klax = wp("KLAX", 33.9425, -118.4081, 125)
func fld(_ dir: Double, _ kt: Double) -> WindField {
    WindField(columns: [ksfo, klax].map { w in WindColumn(coordinate: w.coordinate, validAt: Date(),
        levels: [WindLevel(altitudeFT: 1000, directionTrue: dir, speedKT: kt, temperatureC: nil),
                 WindLevel(altitudeFT: 12000, directionTrue: dir, speedKT: kt, temperatureC: nil)]) }) }
let still = AltitudePlanner.computeProfile(waypoints: [ksfo, klax], cruiseAltitudeFT: 6500, performance: perf)
let head = AltitudePlanner.computeProfile(waypoints: [ksfo, klax], cruiseAltitudeFT: 6500, performance: perf, terrain: nil, wind: fld(138, 30))
let tail = AltitudePlanner.computeProfile(waypoints: [ksfo, klax], cruiseAltitudeFT: 6500, performance: perf, terrain: nil, wind: fld(318, 30))
check("headwind costs more fuel", head.totalFuelGallons > still.totalFuelGallons)
check("tailwind saves fuel", tail.totalFuelGallons < still.totalFuelGallons)
check("still air reports usedWind=false", !still.usedWind)
check("wind reports usedWind=true", head.usedWind)
check("headwind mean is positive", head.meanHeadwindKT > 20)
check("tailwind mean is negative", tail.meanHeadwindKT < -20)

print("Stops")
var kbfl = wp("KBFL", 35.4336, -119.0568, 507)
let overfly = AltitudePlanner.computeProfile(waypoints: [ksfo, kbfl, klax], cruiseAltitudeFT: 8500, performance: perf)
kbfl.stop = StopPlan(kind: .fuel, groundMinutes: 45, refuelToGal: 40)
let stopped = AltitudePlanner.computeProfile(waypoints: [ksfo, kbfl, klax], cruiseAltitudeFT: 8500, performance: perf)
check("overflight stays at cruise", overfly.waypointAltitudes[kbfl.id] ?? 0 > 8000)
check("stop descends to the field", stopped.waypointAltitudes[kbfl.id] == 507)
check("stop makes 2 sectors", stopped.sectors.count == 2)
check("overflight makes 1 sector", overfly.sectors.count == 1)
check("ground time counted in block", near(stopped.totalElapsedMinutes - stopped.totalTimeMinutes, 45, 0.01))
check("max sector < route total", stopped.maxSectorFuelGallons < stopped.totalFuelGallons)
check("refuel flag carried", stopped.sectors.first?.refuelsAtEnd == true)

print("Deviation")
let onTrack = FlightRecord.crossTrackNM(point: .init(latitude: 36, longitude: -120.5),
                                        from: .init(latitude: 37, longitude: -122), to: .init(latitude: 35, longitude: -119))
check("point on the line is ~0 NM", onTrack < 3)
let off = FlightRecord.crossTrackNM(point: .init(latitude: 38, longitude: -122),
                                    from: .init(latitude: 37, longitude: -122), to: .init(latitude: 37, longitude: -120))
check("1 degree north of leg is ~60 NM", near(off, 60, 2))
let beyond = FlightRecord.crossTrackNM(point: .init(latitude: 37, longitude: -119),
                                       from: .init(latitude: 37, longitude: -122), to: .init(latitude: 37, longitude: -120))
check("beyond the end clamps to the endpoint", near(beyond, 48, 3))

print("Fuel estimator")
let est = FuelEstimator.estimate(elapsed: 3600, startedWithGal: 40, burnGPH: 8.5, remainingRouteFuelGal: 20)
check("burned 8.5 in an hour", near(est.burnedGal, 8.5, 0.01))
check("31.5 remaining", near(est.remainingGal, 31.5, 0.01))
check("margin = 31.5 - 20 - 4.25", near(est.marginGal, 7.25, 0.01))
check("sufficient", est.isSufficient)
let tight = FuelEstimator.estimate(elapsed: 3600*3, startedWithGal: 40, burnGPH: 8.5, remainingRouteFuelGal: 20)
check("3h in, 20gal to run is short", !tight.isSufficient)

print("Approach geometry")
let fix = ArrivalPlanner.finalApproachFix(airport: .init(latitude: 37.6188, longitude: -122.3750), runwayHeadingTrue: 280, distanceNM: 5)
let d = AltitudePlanner.distanceNM(.init(latitude: 37.6188, longitude: -122.3750), fix)
check("final fix is 5 NM out", near(d, 5, 0.1))
let brg = AltitudePlanner.bearingDegrees(from: .init(latitude: 37.6188, longitude: -122.3750), to: fix)
check("final fix sits on the reciprocal (100)", near(brg, 100, 1))

print("\n\(pass) passed, \(fail) failed")
