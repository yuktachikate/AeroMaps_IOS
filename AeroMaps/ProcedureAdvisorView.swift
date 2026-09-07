import SwiftUI
import MapKit

// MARK: - Runway analysis

/// One usable landing/takeoff direction, with the wind resolved into its
/// along-runway and across-runway components.
struct RunwayEnd: Identifiable {
    let id = UUID()
    let designation: String       // "28R"
    /// True heading. Published where the database has it, and only derived from
    /// the designation when it does not — the two differ by up to five degrees, and
    /// the approach geometry in InFlightAmendment depends on this being true.
    let headingDegrees: Double
    let lengthFT: Int
    let surface: String
    let lighted: Bool
    let headwindKT: Double
    let crosswindKT: Double

    var isFavourable: Bool { headwindKT >= 0 }

    /// Which side the crosswind comes from, for the briefing line.
    var crosswindSide: String { crosswindKT >= 0 ? "right" : "left" }
}

enum RunwayAnalyser {

    /// Expands "10L/28R" into its two ends and scores each against the wind.
    static func ends(for airport: Airport, windDirection: Double, windSpeed: Double) -> [RunwayEnd] {
        var out: [RunwayEnd] = []
        for runway in airport.runways {
            let tokens = runway.designation.split(separator: "/").map(String.init)
            for (position, token) in tokens.enumerated() {
                // Published true heading where the database has it; the designation
                // digits are only a fallback. "28R" is 280° by that rule but 298° in
                // fact at KSFO, and an 18° error moves several knots between the
                // headwind and crosswind components.
                let published = position == 0 ? runway.trueHeadingLow : runway.trueHeadingHigh
                guard let heading = published ?? heading(from: token) else { continue }
                let delta = (windDirection - heading) * .pi / 180
                out.append(RunwayEnd(
                    designation: token,
                    headingDegrees: heading,
                    lengthFT: runway.length,
                    surface: runway.surface,
                    lighted: runway.lighted,
                    headwindKT: windSpeed * cos(delta),
                    crosswindKT: windSpeed * sin(delta)
                ))
            }
        }
        // Equal headwind happens constantly with parallel runways; prefer the
        // longer strip rather than whichever the data happened to list first.
        return out.sorted {
            abs($0.headwindKT - $1.headwindKT) < 0.5 ? $0.lengthFT > $1.lengthFT
                                                     : $0.headwindKT > $1.headwindKT
        }
    }

    /// "28R" → 280°. Runway numbers are tens of degrees magnetic.
    private static func heading(from designation: String) -> Double? {
        let digits = designation.prefix { $0.isNumber }
        guard let number = Int(digits), (1...36).contains(number) else { return nil }
        return Double(number * 10)
    }
}

// MARK: - View

/// Departure and arrival planning for the two ends of the route: which runway the
/// wind favours, pattern altitudes, the first course out and the descent back in.
///
/// It does not show SIDs, STARs or instrument approaches — those are published
/// procedures that need a charts subscription the app does not have, and inventing
/// them would be worse than omitting them.
struct ProcedureAdvisorView: View {
    @ObservedObject var mapState: MapState
    @Environment(\.dismiss) private var dismiss

    /// Maximum demonstrated crosswind for the light single the planner models.
    static let demonstratedCrosswindKT: Double = 15

    private var departureAirport: Airport? { airport(at: 0) }
    private var destinationAirport: Airport? { airport(at: mapState.route.waypoints.count - 1) }

    private func airport(at index: Int) -> Airport? {
        guard mapState.route.waypoints.indices.contains(index) else { return nil }
        guard let icao = mapState.route.waypoints[index].airportICAO else { return nil }
        return mapState.airports[icao]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mapState.route.waypoints.count < 2 {
                        emptyState("Build a route with a departure and destination to brief its procedures.")
                    } else if departureAirport == nil && destinationAirport == nil {
                        emptyState("This route's endpoints are map points, not airports. Add an airport as the departure or destination to brief runways and pattern altitudes.")
                    } else {
                        if let departure = departureAirport {
                            airportSection(departure, role: .departure)
                        }
                        if let destination = destinationAirport {
                            airportSection(destination, role: .arrival)
                        }
                        disclaimer
                    }
                }
                .padding(16)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Procedure Advisor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { mapState.refreshRouteWeather() }
        }
    }

    private enum Role {
        case departure, arrival

        var title: String { self == .departure ? "Departure" : "Arrival" }
        var icon: String { self == .departure ? "airplane.departure" : "airplane.arrival" }
        var tint: Color { self == .departure ? .green : .orange }
    }

    @ViewBuilder
    private func airportSection(_ airport: Airport, role: Role) -> some View {
        // Observed surface wind where a station is reporting; the positional model
        // only when nothing is. Which one it used is stated below the figure — a
        // runway recommendation is only as good as the wind behind it.
        let wind = mapState.windAt(airport.coordinate, altitudeFT: 0)
        let ends = RunwayAnalyser.ends(for: airport,
                                       windDirection: Double(wind.direction),
                                       windSpeed: Double(wind.speed))
        let patternAltitude = airport.elevation + 1_000

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: role.icon)
                    .font(.title3).foregroundColor(role.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(role.title) · \(airport.icao)")
                        .font(.subheadline).fontWeight(.bold)
                    Text(airport.name).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("\(wind.direction)° @ \(wind.speed) kt")
                            .font(.caption).fontWeight(.semibold)
                        if let gust = wind.gust {
                            Text("G\(gust)")
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                    }
                    HStack(spacing: 3) {
                        Image(systemName: wind.source.isObserved ? "dot.radiowaves.up.forward" : "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                        Text(wind.source.label)
                            .font(.system(size: 9))
                    }
                    .foregroundColor(wind.source.isObserved ? .green : .orange)
                }
            }

            // Runway recommendation
            if let best = ends.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text(role == .departure ? "DEPART RUNWAY" : "EXPECT RUNWAY")
                        .font(.system(size: 9, weight: .heavy)).foregroundColor(.secondary)
                    HStack(spacing: 10) {
                        Text(best.designation)
                            .font(.title2).fontWeight(.heavy)
                            .foregroundColor(role.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.0f kt headwind · %.0f kt crosswind from the %@",
                                        max(best.headwindKT, 0), abs(best.crosswindKT), best.crosswindSide))
                                .font(.caption)
                            Text("\(best.lengthFT.formatted()) ft \(best.surface)\(best.lighted ? " · lighted" : "")")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    if abs(best.crosswindKT) > mapState.route.aircraft.demonstratedCrosswindKT {
                        Label(String(format: "Crosswind %.0f kt exceeds the %.0f kt demonstrated for the %@",
                                     abs(best.crosswindKT), mapState.route.aircraft.demonstratedCrosswindKT,
                                     mapState.route.aircraft.name),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                }
                .padding(10)
                .background(role.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // All runway ends
            if ends.count > 1 {
                VStack(spacing: 4) {
                    ForEach(ends) { end in
                        HStack(spacing: 8) {
                            Text(end.designation)
                                .font(.caption).fontWeight(.bold)
                                .frame(width: 38, alignment: .leading)
                            Text(String(format: "%@%.0f kt", end.headwindKT >= 0 ? "↓" : "↑", abs(end.headwindKT)))
                                .font(.caption2)
                                .foregroundColor(end.headwindKT >= 0 ? .green : .red)
                                .frame(width: 60, alignment: .leading)
                            Text(String(format: "×%.0f kt", abs(end.crosswindKT)))
                                .font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text("\(end.lengthFT.formatted()) ft")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
            }

            // Vertical plan for this end of the route
            factRow(role == .departure ? "Field elevation" : "Field elevation",
                    "\(airport.elevation.formatted()) ft MSL")
            factRow("Traffic pattern altitude", "\(patternAltitude.formatted()) ft MSL (1,000 ft AGL)")

            if role == .departure {
                if let course = initialCourse {
                    factRow("Initial course", String(format: "%03.0f°T to %@", course.0, course.1))
                }
                factRow("Climb to cruise",
                        "\(mapState.route.altitudeFT.formatted()) ft at \(Int(mapState.route.climbRateFPM)) fpm — level off \(Int(mapState.altitudeProfile.topOfClimbNM.rounded())) NM out")
            } else {
                let descentFrom = mapState.route.altitudeFT - airport.elevation
                let todNM = max(mapState.altitudeProfile.totalDistanceNM - mapState.altitudeProfile.topOfDescentNM, 0)
                factRow("Descent", "\(descentFrom.formatted()) ft to lose at \(Int(mapState.route.descentRateFPM)) fpm")
                factRow("Start down", String(format: "%.0f NM from the field", todNM))
            }

            if !airport.frequencies.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FREQUENCIES")
                        .font(.system(size: 9, weight: .heavy)).foregroundColor(.secondary)
                    ForEach(airport.frequencies) { freq in
                        HStack {
                            Text(freq.type).font(.caption).fontWeight(.semibold)
                            Spacer()
                            Text(freq.frequency).font(.caption).monospacedDigit()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// True course from the departure to the next point on the route.
    private var initialCourse: (Double, String)? {
        let waypoints = mapState.route.waypoints
        guard waypoints.count >= 2 else { return nil }
        return (AltitudePlanner.bearingDegrees(from: waypoints[0].coordinate, to: waypoints[1].coordinate),
                waypoints[1].ident)
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    private var disclaimer: some View {
        Text("Runway selection is computed from the reported surface wind and published runway headings. Published SIDs, STARs and instrument approaches are not included — check current charts and NOTAMs before flight.")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.top, 4)
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.triangle.merge")
                .font(.largeTitle).foregroundColor(.secondary)
            Text(message)
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
