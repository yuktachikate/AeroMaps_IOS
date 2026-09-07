import SwiftUI
import MapKit

/// The flights this device has recorded.
///
/// Not a certifying logbook — it makes no claim to be one — but a record of what
/// was actually flown against what was planned: the track, how far it strayed, the
/// changes made in the air and why, and which checklist items were ticked.
struct LogbookView: View {
    @ObservedObject var mapState: MapState
    @Environment(\.dismiss) private var dismiss
    @State private var selected: FlightRecord?

    private var records: [FlightRecord] { mapState.flightLog.records }

    var body: some View {
        NavigationView {
            Group {
                if records.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            HStack {
                                summary("\(records.filter(\.isComplete).count)", "flights")
                                Divider()
                                summary(String(format: "%.1f", mapState.flightLog.totalHours), "hours")
                                Divider()
                                summary(String(format: "%.0f", records.reduce(0) { $0 + $1.actualDistanceNM }), "NM")
                            }
                            .padding(.vertical, 4)
                        }

                        ForEach(records) { record in
                            Button { selected = record } label: { row(record) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            for index in indexSet { mapState.flightLog.delete(id: records[index].id) }
                        }
                    }
                }
            }
            .navigationTitle("Logbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $selected) { LoggedFlightDetailView(record: $0) }
        }
    }

    private func summary(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3).fontWeight(.bold)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ record: FlightRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: record.isComplete ? "airplane" : "dot.radiowaves.left.and.right")
                .foregroundColor(record.isComplete ? .blue : .green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.routeName).font(.subheadline).fontWeight(.semibold)
                Text("\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.aircraftName)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.isComplete ? formatted(record.duration) : "in flight")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(record.isComplete ? .primary : .green)
                if !record.amendments.isEmpty {
                    Text("\(record.amendments.count) change\(record.amendments.count == 1 ? "" : "s")")
                        .font(.caption2).foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed").font(.largeTitle).foregroundColor(.secondary)
            Text("No flights recorded").font(.headline)
            Text("A record starts when you tap Start on a route, and captures the track flown, any changes made in the air, and the checklist as it stood.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// One logged flight: plan versus what happened. Named to avoid colliding with
/// the live-traffic FlightDetailView, which is a different thing entirely.
struct LoggedFlightDetailView: View {
    let record: FlightRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if record.track.count >= 2 { FlightTrackMap(record: record).frame(height: 220) }

                    card("Planned vs flown", "chart.line.uptrend.xyaxis") {
                        comparison("Distance",
                                   String(format: "%.0f NM", record.plannedDistanceNM),
                                   String(format: "%.0f NM", record.actualDistanceNM))
                        comparison("Time",
                                   formatted(record.plannedTimeMinutes * 60),
                                   formatted(record.duration))
                        let deviation = record.deviation
                        comparison("Deviation from track", "—",
                                   String(format: "%.1f NM max · %.1f NM mean", deviation.max, deviation.mean))
                        comparison("Max altitude",
                                   "\(record.plannedCruiseFT.formatted()) ft planned",
                                   record.maxAltitudeFT > 0 ? "\(Int(record.maxAltitudeFT).formatted()) ft" : "—")
                    }

                    card("Route as filed", "point.topleft.down.to.point.bottomright.curvepath") {
                        ForEach(record.plannedPoints) { point in
                            HStack {
                                Text(point.ident).font(.caption).fontWeight(.semibold)
                                if point.isStop {
                                    Image(systemName: "pause.circle.fill")
                                        .font(.caption2).foregroundColor(.green)
                                }
                                Spacer()
                                Text(point.plannedAltitudeFT.map { "\($0.formatted()) ft" } ?? "—")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }

                    if !record.amendments.isEmpty {
                        card("Changes in the air", "clock.arrow.circlepath") {
                            ForEach(record.amendments) { amendment in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: amendment.kind.symbolName)
                                        .font(.caption).foregroundColor(.orange).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(amendment.summary).font(.caption)
                                        HStack(spacing: 8) {
                                            Text(amendment.time.formatted(date: .omitted, time: .shortened))
                                            if let nm = amendment.remainingNM {
                                                Text(String(format: "%.0f NM to run", nm))
                                            }
                                            if let gal = amendment.remainingFuelGal {
                                                Text(String(format: "%.1f gal est.", gal))
                                            }
                                        }
                                        .font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }

                    if !record.checklistCompleted.isEmpty {
                        card("Checklist", "checklist") {
                            Text("\(record.checklistCompleted.count) items ticked during this flight.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(record.routeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func card<Content: View>(_ title: String, _ icon: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func comparison(_ label: String, _ planned: String, _ actual: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(planned).font(.caption).foregroundColor(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundColor(.secondary)
            Text(actual).font(.caption).fontWeight(.semibold)
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// The track flown, with the planned route under it so the two can be compared.
struct FlightTrackMap: UIViewRepresentable {
    let record: FlightRecord

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)

        if record.plannedPoints.count >= 2 {
            let planned = record.plannedPoints.map(\.coordinate)
            let line = MKPolyline(coordinates: planned, count: planned.count)
            line.title = "planned"
            map.addOverlay(line)
        }
        if record.track.count >= 2 {
            let flown = record.track.map(\.coordinate)
            let line = MKPolyline(coordinates: flown, count: flown.count)
            line.title = "flown"
            map.addOverlay(line)
            map.setVisibleMapRect(line.boundingMapRect,
                                  edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30),
                                  animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            if line.title == "planned" {
                // The plan is the reference, drawn as a dashed ghost so the solid
                // track flown reads as the thing that actually happened.
                renderer.strokeColor = .systemBlue.withAlphaComponent(0.6)
                renderer.lineWidth = 3
                renderer.lineDashPattern = [6, 6]
            } else {
                renderer.strokeColor = .systemGreen
                renderer.lineWidth = 4
            }
            return renderer
        }
    }
}
