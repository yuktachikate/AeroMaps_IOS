import SwiftUI
import MapKit
import CoreLocation

/// Changing the plan after you have left the ground.
///
/// The case this exists for: you are airborne, approach assigns a landing runway
/// that is not the one the route assumed, and the arrival needs to change. On a
/// road map that is a reroute and nobody thinks twice about it; in the air it also
/// moves the fuel figure, because the fuel you have left is what you started with
/// minus what you have already burned — not what the pre-flight plan said.
///
/// So every amendment here does three things: change the route, re-estimate the
/// fuel from time actually airborne, and write the change into the flight record so
/// the reason for the track is still answerable on the ground afterwards.
enum ArrivalPlanner {
    /// A point on the extended runway centreline, on the approach side.
    ///
    /// Placing it 5 NM out puts it at a normal straight-in intercept, far enough to
    /// be a real leg rather than a cosmetic dogleg over the field.
    static func finalApproachFix(airport: CLLocationCoordinate2D,
                                 runwayHeadingTrue: Double,
                                 distanceNM: Double = 5) -> CLLocationCoordinate2D {
        // Back down the approach path: the aircraft flies *along* the runway
        // heading to land, so the fix sits on the reciprocal.
        offset(from: airport, bearingTrue: runwayHeadingTrue + 180, distanceNM: distanceNM)
    }

    /// Great-circle offset from a point.
    static func offset(from origin: CLLocationCoordinate2D,
                       bearingTrue: Double,
                       distanceNM: Double) -> CLLocationCoordinate2D {
        let radiusNM = 3_440.065
        let angular = distanceNM / radiusNM
        let bearing = bearingTrue * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1),
                                cos(angular) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi,
                                      longitude: lon2 * 180 / .pi)
    }

    /// Identifier used for the inserted approach leg, so a second assignment
    /// replaces the first rather than stacking up doglegs.
    static func fixIdent(runway: String) -> String { "RW\(runway)" }
    static func isApproachFix(_ waypoint: Waypoint) -> Bool { waypoint.ident.hasPrefix("RW") }
}

// MARK: - The sheet

/// In-flight amendments: the runway you were given, a diversion, or a fuel stop.
struct InFlightAmendmentView: View {
    @ObservedObject var mapState: MapState
    @Environment(\.dismiss) private var dismiss

    private var destination: Waypoint? { mapState.route.waypoints.last }

    private var destinationAirport: Airport? {
        guard let ident = destination?.airportICAO else { return nil }
        return mapState.airports[ident]
    }

    private var metar: Metar? {
        guard let ident = destination?.airportICAO else { return nil }
        return mapState.aviationWeather.metars[ident]
    }

    /// Runways ranked by headwind, using the destination's reported wind when there
    /// is one. With no observation the wind components are unknown rather than
    /// assumed calm, and the list is shown without them.
    private var runways: [RunwayEnd] {
        guard let airport = destinationAirport, airport.isVerified else { return [] }
        if let metar, case .degrees(let dir)? = metar.wdir, let speed = metar.wspd {
            return RunwayAnalyser.ends(for: airport, windDirection: Double(dir), windSpeed: speed)
        }
        return RunwayAnalyser.ends(for: airport, windDirection: 0, windSpeed: 0)
    }

    private var hasWind: Bool {
        guard let metar, case .degrees? = metar.wdir, metar.wspd != nil else { return false }
        return true
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fuelCard
                    runwayCard
                    divertCard
                    if !mapState.route.waypoints.isEmpty { amendmentHistory }
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .navigationTitle("Amend Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Fuel

    /// Fuel as it stands now, not as it was planned. This is the number an
    /// amendment actually threatens.
    private var fuelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Fuel remaining", systemImage: "fuelpump.fill")
                .font(.headline)

            if let estimate = mapState.inFlightFuel {
                HStack(spacing: 16) {
                    figure(String(format: "%.1f", estimate.remainingGal), "gal left", .blue)
                    figure(String(format: "%.1f", estimate.requiredGal), "gal to run", .purple)
                    figure(String(format: "%+.1f", estimate.marginGal), "gal margin",
                           estimate.isSufficient ? .green : .red)
                }

                Text(estimate.isSufficient
                     ? String(format: "About %.0f min endurance left at the planned burn; the rest of the route and a 30 min reserve need %.1f gal.",
                              estimate.enduranceMinutes, estimate.requiredGal + estimate.reserveGal)
                     : String(format: "Short by %.1f gal against the rest of the route plus a 30 min reserve. Add a fuel stop before continuing.",
                              -estimate.marginGal))
                    .font(.caption)
                    .foregroundColor(estimate.isSufficient ? .secondary : .red)

                // Said plainly, because it is an estimate from a clock and a book
                // burn rate, not a reading from the aircraft.
                Text("Estimated from \(Int(mapState.activeFlight.map { Date().timeIntervalSince($0.startedAt) / 60 } ?? 0)) min airborne at \(String(format: "%.1f", mapState.route.performance.fuelBurnGPH)) GPH. Not a fuel gauge — confirm against the aircraft.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Not airborne. Fuel is re-estimated from time in flight once a route is started.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func figure(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3).fontWeight(.bold).foregroundColor(tint)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: Runway

    private var runwayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Assigned landing runway", systemImage: "airplane.arrival")
                .font(.headline)

            if let destination {
                Text("Approach into \(destination.ident). Pick the runway ATC gave you and the arrival is re-planned onto a 5 NM final for it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if runways.isEmpty {
                Text(destinationAirport == nil
                     ? "The destination is not an airport in the database, so no runways are published for it."
                     : "No runway data published for this field.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                if !hasWind {
                    Label("No wind observation for this field — runways are listed without wind components.",
                          systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                ForEach(runways) { end in
                    Button { assign(end) } label: { runwayRow(end) }
                        .buttonStyle(.plain)
                }
            }

            if let current = mapState.route.waypoints.first(where: ArrivalPlanner.isApproachFix) {
                Button(role: .destructive) {
                    mapState.removeWaypoint(id: current.id)
                    mapState.recordAmendment(.runwayAssigned, summary: "Cleared assigned runway \(current.ident.dropFirst(2))")
                } label: {
                    Label("Clear \(current.ident.dropFirst(2)) approach", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func runwayRow(_ end: RunwayEnd) -> some View {
        HStack(spacing: 12) {
            Text(end.designation)
                .font(.headline).fontWeight(.bold)
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%03.0f°T · %d ft %@", end.headingDegrees, end.lengthFT, end.surface))
                    .font(.caption)
                if hasWind {
                    Text(String(format: "%@ %.0f kt · crosswind %.0f kt %@",
                                end.headwindKT >= 0 ? "headwind" : "TAILWIND",
                                abs(end.headwindKT), abs(end.crosswindKT), end.crosswindSide))
                        .font(.caption2)
                        .foregroundColor(end.headwindKT < 0 ? .orange : .secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Puts a 5 NM final for the assigned runway in front of the destination.
    private func assign(_ end: RunwayEnd) {
        guard let airport = destinationAirport else { return }
        var plan = mapState.route
        // Replace any previous assignment rather than stacking doglegs.
        plan.waypoints.removeAll(where: ArrivalPlanner.isApproachFix)

        let fix = ArrivalPlanner.finalApproachFix(airport: airport.coordinate,
                                                  runwayHeadingTrue: end.headingDegrees)
        let waypoint = Waypoint(
            ident: ArrivalPlanner.fixIdent(runway: end.designation),
            name: "\(airport.icao) RWY \(end.designation) final",
            coordinate: fix,
            kind: .coordinate,
            fieldElevationFT: airport.elevation,
            airportICAO: nil,
            reason: "5 NM final for runway \(end.designation)")
        plan.waypoints.insert(waypoint, at: max(plan.waypoints.count - 1, 0))
        mapState.route = plan

        mapState.recordAmendment(.runwayAssigned,
                                 summary: "Runway \(end.designation) at \(airport.icao) — 5 NM final inserted")
        dismiss()
    }

    // MARK: Divert and fuel stops

    /// Fields the aircraft can actually reach on the fuel it has left.
    ///
    /// Reachability is measured against the *current* estimate — what you started
    /// with minus what you have burned — not the pre-flight figure, because the
    /// whole point of diverting partway is that the original plan no longer applies.
    /// A 30-minute reserve is held back before anything is called reachable.
    private var reachableAirports: [(airport: Airport, distanceNM: Double, reachable: Bool)] {
        guard let here = mapState.locationManager?.lastLocation?.coordinate else { return [] }
        let estimate = mapState.inFlightFuel
        let perf = mapState.route.performance
        let usableGal = max((estimate?.remainingGal ?? mapState.route.fuelOnBoardGal) - (estimate?.reserveGal ?? 0), 0)
        let rangeNM = perf.fuelBurnGPH > 0 ? (usableGal / perf.fuelBurnGPH) * perf.cruiseKTAS : 0

        let current = Set(mapState.route.waypoints.compactMap(\.airportICAO))
        return mapState.nearbyAirports(to: here, withinNM: 120, count: 40)
            .filter { $0.isVerified && !current.contains($0.icao) }
            .map { airport -> (Airport, Double, Bool) in
                let d = AltitudePlanner.distanceNM(here, airport.coordinate)
                return (airport, d, d <= rangeNM)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(6)
            .map { (airport: $0.0, distanceNM: $0.1, reachable: $0.2) }
    }

    private var divertCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Divert or add a stop", systemImage: "arrow.triangle.branch")
                .font(.headline)

            if mapState.inFlightFuel?.isSufficient == false {
                Label("The fuel estimate no longer covers the rest of the route. A stop here is not optional.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            let options = reachableAirports
            if options.isEmpty {
                Text("No airfields found nearby, or no position fix yet.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text("Nearest fields, with reach measured on the fuel you have left.")
                    .font(.caption).foregroundColor(.secondary)

                ForEach(options, id: \.airport.icao) { option in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(option.airport.icao)
                                    .font(.subheadline).fontWeight(.bold)
                                if !option.reachable {
                                    Text("beyond fuel range")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.red)
                                }
                            }
                            Text(String(format: "%@ · %.0f NM", option.airport.name, option.distanceNM))
                                .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        // Two different intentions: stop here and carry on, or make
                        // this the new destination.
                        Button("Stop") { addStop(option.airport) }
                            .font(.caption).fontWeight(.semibold)
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        Button("Divert") { divert(to: option.airport) }
                            .font(.caption).fontWeight(.semibold)
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                    .opacity(option.reachable ? 1 : 0.55)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Inserts a landing before the destination and keeps the rest of the route.
    private func addStop(_ airport: Airport) {
        var plan = mapState.route
        var waypoint = Waypoint(airport: airport)
        waypoint.stop = StopPlan(kind: .fuel, groundMinutes: 45,
                                 refuelToGal: plan.aircraft.usableFuelGal)
        waypoint.reason = "Added in flight"
        // Ahead of the aircraft, not behind it: inserting before the leg already
        // being flown would put a landing in the past.
        let insertAt = min(max(mapState.currentWaypointIndex + 1, 1), plan.waypoints.count - 1)
        plan.waypoints.insert(waypoint, at: insertAt)
        mapState.route = plan
        mapState.recordAmendment(.fuelStopAdded,
                                 summary: "Fuel stop added at \(airport.icao) in flight")
        dismiss()
    }

    /// Makes this field the destination and drops everything that came after the
    /// aircraft's current position.
    private func divert(to airport: Airport) {
        var plan = mapState.route
        let keep = min(mapState.currentWaypointIndex + 1, plan.waypoints.count)
        let previousDestination = plan.waypoints.last?.ident ?? "destination"
        plan.waypoints = Array(plan.waypoints.prefix(keep))
        plan.waypoints.append(Waypoint(airport: airport).withReason("Diversion"))
        mapState.route = plan
        mapState.recordAmendment(.destinationChanged,
                                 summary: "Diverted from \(previousDestination) to \(airport.icao)")
        mapState.zoomToRoute()
        dismiss()
    }

    // MARK: History

    private var amendmentHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            let amendments = mapState.activeFlight?.amendments ?? []
            if !amendments.isEmpty {
                Label("Changes this flight", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                ForEach(amendments) { amendment in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: amendment.kind.symbolName)
                            .font(.caption).foregroundColor(.blue).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(amendment.summary).font(.caption)
                            Text(amendment.time.formatted(date: .omitted, time: .shortened))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
