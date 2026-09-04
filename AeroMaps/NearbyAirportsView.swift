import SwiftUI
import CoreLocation

/// Fields close to the aircraft or to the area being looked at.
///
/// Most flying this app is built for is local — a training circuit, a hop to the
/// next field, a cross-country of an hour. Making those airports one tap away is
/// worth more than any amount of search.
struct NearbyAirportsStrip: View {
    @ObservedObject var mapState: MapState
    @EnvironmentObject private var locationManager: LocationManager

    /// Anchor on the aircraft when its position is known, otherwise on what the
    /// pilot is looking at.
    private var anchor: CLLocationCoordinate2D {
        locationManager.lastLocation?.coordinate ?? mapState.camera.centerCoordinate
    }

    private var anchoredOnAircraft: Bool { locationManager.lastLocation != nil }

    private var nearby: [Airport] {
        mapState.nearbyAirports(to: anchor, withinNM: 60, count: 12)
    }

    var body: some View {
        let airports = nearby
        if !airports.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: anchoredOnAircraft ? "location.fill" : "map")
                        .font(.system(size: 9))
                    Text(anchoredOnAircraft ? "AIRPORTS NEAR YOU" : "AIRPORTS IN VIEW")
                        .font(.system(size: 9, weight: .heavy))
                    Spacer()
                    Text("tap to add")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }
                .foregroundColor(.white.opacity(0.5))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(airports) { airport in
                            let distance = AltitudePlanner.distanceNM(anchor, airport.coordinate)
                            let alreadyOnRoute = mapState.route.waypoints.contains { $0.airportICAO == airport.icao }
                            Button {
                                guard !alreadyOnRoute else { return }
                                mapState.appendWaypoint(Waypoint(airport: airport))
                                if mapState.route.waypoints.count >= 2 { mapState.zoomToRoute() }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(airport.icao)
                                            .font(.caption).fontWeight(.bold)
                                            .foregroundColor(alreadyOnRoute ? .green : .white)
                                        if alreadyOnRoute {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.green)
                                        }
                                    }
                                    Text(airport.name)
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(1)
                                    Text("\(Int(distance.rounded())) NM · \(airport.elevation.formatted()) ft")
                                        .font(.system(size: 9))
                                        .foregroundColor(.cyan.opacity(0.8))
                                }
                                .frame(width: 118, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(Color.white.opacity(alreadyOnRoute ? 0.03 : 0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(alreadyOnRoute ? Color.green.opacity(0.4) : Color.white.opacity(0.12),
                                                lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
    }
}

/// Where the aeronautical data came from and how old it is.
///
/// Shown because a pilot planning offline is entitled to know whether they are
/// looking at last week's database or last year's.
struct AeroDataStatusRow: View {
    @ObservedObject var database: AeronauticalDatabase

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(tint)
            Text(text)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            if database.isRefreshing {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text(database.refreshStage.map { "\($0) \(Int(database.refreshProgress * 100))%" } ?? "Updating…")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
            } else {
                Button {
                    database.refreshIfDue(force: true)
                } label: {
                    Text("Update")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.cyan.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var icon: String {
        switch database.status {
        case .loading:        return "arrow.triangle.2.circlepath"
        case .failed:         return "exclamationmark.triangle.fill"
        case .ready:          return "internaldrive"
        }
    }

    private var tint: Color {
        if case .failed = database.status { return .orange }
        return .white.opacity(0.4)
    }

    private var text: String {
        switch database.status {
        case .loading:
            return "Loading aeronautical data…"
        case .failed(let message):
            return message
        case .ready(let source, let generated):
            let count = database.catalog.count.formatted()
            guard let generated else { return "\(count) airports · \(source.rawValue) · available offline" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let age = formatter.localizedString(for: generated, relativeTo: Date())
            return "\(count) airports · \(source.rawValue) \(age) · available offline"
        }
    }
}
