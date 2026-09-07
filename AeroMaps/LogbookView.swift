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

    /// Flights bucketed by age, newest bucket first.
    ///
    /// The buckets do not overlap — a flight lands in exactly one — and empty ones
    /// are dropped rather than shown as headings with nothing under them.
    private var groups: [(title: String, records: [FlightRecord])] {
        let now = Date()
        let day = 24.0 * 3600
        // Ordered from newest to oldest; the first bucket a flight fits is the one
        // it belongs to, so the upper bound is all that needs stating.
        let buckets: [(String, TimeInterval)] = [
            ("Today", day),
            ("Last 7 days", 7 * day),
            ("Last 30 days", 30 * day),
            ("Last 12 months", 365 * day)
        ]
        var remaining = records.sorted { $0.startedAt > $1.startedAt }
        var out: [(String, [FlightRecord])] = []

        for (title, maxAge) in buckets {
            let matched = remaining.filter { now.timeIntervalSince($0.startedAt) < maxAge }
            guard !matched.isEmpty else { continue }
            out.append((title, matched))
            let taken = Set(matched.map(\.id))
            remaining.removeAll { taken.contains($0.id) }
        }
        if !remaining.isEmpty { out.append(("Earlier", remaining)) }
        return out
    }

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
                                // Jitter from a stationary recording would otherwise
                                // be totalled up as distance flown.
                                summary(String(format: "%.0f", records.filter { !$0.neverMoved }
                                                .reduce(0) { $0 + $1.actualDistanceNM }), "NM")
                            }
                            .padding(.vertical, 4)
                        }

                        // Grouped by age, and a period with no flights in it is not
                        // rendered at all — an empty "Last 7 days" heading is just a
                        // reminder that you have not flown, which is not what a
                        // logbook is for.
                        ForEach(groups, id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.records) { record in
                                    Button { selected = record } label: { row(record) }
                                        .buttonStyle(.plain)
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        mapState.flightLog.delete(id: group.records[index].id)
                                    }
                                }
                            }
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) { EditButton() }
                    }
                }
            }
            .navigationTitle("Logbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $selected) { record in
                LoggedFlightDetailView(record: record,
                                       onDelete: { mapState.flightLog.delete(id: record.id) })
            }
            // Arriving straight from "View summary" opens that flight rather than
            // making the pilot pick it out of the list they just came from.
            .onAppear {
                if let justFinished = mapState.completedFlight {
                    selected = justFinished
                    mapState.completedFlight = nil
                }
            }
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
    /// Supplied so a flight can be deleted from the record itself rather than only
    /// by swiping a row in the list behind it.
    var onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showPlanned = true
    @State private var showFlown = true
    @State private var confirmingDelete = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if record.plannedPoints.count >= 2 || record.track.count >= 2 {
                        VStack(spacing: 6) {
                            FlightTrackMap(record: record,
                                           showPlanned: showPlanned,
                                           showFlown: showFlown)
                                .frame(height: 240)
                            // Toggles rather than a fixed pair of lines: on a route
                            // that followed the plan closely the two sit on top of
                            // each other, and being able to switch one off is the
                            // only way to see what is underneath.
                            HStack(spacing: 8) {
                                layerToggle("Planned", isOn: $showPlanned, tint: .blue)
                                layerToggle("Flown", isOn: $showFlown, tint: .green)
                                Spacer()
                            }
                            trackLegend
                        }
                    }

                    // The logbook-shaped facts, together at the top: what was flown,
                    // in what, for how long, with how many landings.
                    card("Flight", "airplane") {
                        detail("Date", record.startedAt.formatted(date: .abbreviated, time: .shortened))
                        detail("Aircraft", record.registration.isEmpty
                                            ? record.aircraftName
                                            : "\(record.registration) · \(record.aircraftName)")
                        detail("Route", record.plannedPoints.map(\.ident).joined(separator: " → "))
                        detail("Block time", formatted(record.duration))
                        if record.airborneMinutes > 0 {
                            detail("Airborne", formatted(record.airborneMinutes * 60))
                        }
                        if record.landings > 0 { detail("Landings", "\(record.landings)") }
                    }

                    if let speed = record.groundSpeed, !record.neverMoved {
                        card("Speed made good", "speedometer") {
                            detail("Average ground speed", String(format: "%.0f kt", speed.average))
                            detail("Maximum", String(format: "%.0f kt", speed.max))
                            // The measured half of the wind story, against the figure
                            // the plan was built on.
                            let planned = record.plannedTimeMinutes > 0
                                ? record.plannedDistanceNM / (record.plannedTimeMinutes / 60) : 0
                            if planned > 0 {
                                detail("Planned average", String(format: "%.0f kt", planned))
                                let delta = speed.average - planned
                                Text(abs(delta) < 3
                                     ? "Close to plan — the forecast wind was about right."
                                     : String(format: "%.0f kt %@ than planned, which is the wind you actually got.",
                                              abs(delta), delta > 0 ? "faster" : "slower"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if !record.altitudeTrace.isEmpty && !record.neverMoved {
                        card("Altitude flown", "chart.xyaxis.line") {
                            AltitudeTraceChart(record: record).frame(height: 120)
                            Text("Grey is the planned cruise level; the line is what the aircraft actually flew.")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }

                    card("Planned vs flown", "chart.line.uptrend.xyaxis") {
                        comparison("Distance",
                                   String(format: "%.0f NM", record.plannedDistanceNM),
                                   record.neverMoved ? "did not move"
                                                     : String(format: "%.0f NM", record.actualDistanceNM))
                        comparison("Time",
                                   formatted(record.plannedTimeMinutes * 60),
                                   formatted(record.duration))
                        let deviation = record.deviation
                        comparison("Deviation from track", "—",
                                   record.neverMoved ? "n/a — never left the ground"
                                                     : String(format: "%.1f NM max · %.1f NM mean", deviation.max, deviation.mean))
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

                    if !record.notes.isEmpty {
                        card("Notes", "pencil.and.list.clipboard") {
                            Text(record.notes)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // The items themselves, by phase. A bare count answered "did you
                    // tick anything" but not "what did you actually check", which is
                    // the question worth being able to answer afterwards.
                    if !record.checklistCompleted.isEmpty {
                        let done = Set(record.checklistCompleted)
                        card("Checklist", "checklist") {
                            ForEach(ChecklistView.phases) { phase in
                                let ticked = phase.items.filter { done.contains($0.id) }
                                if !ticked.isEmpty {
                                    Text(phase.title.uppercased())
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundColor(.secondary)
                                        .padding(.top, 2)
                                    ForEach(ticked) { item in
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption2).foregroundColor(.green)
                                            Text(item.action).font(.caption)
                                            Spacer()
                                            Text(item.response)
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(record.routeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if onDelete != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .confirmationDialog("Delete this flight?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete flight", role: .destructive) { onDelete?(); dismiss() }
                Button("Keep", role: .cancel) { }
            } message: {
                Text("The track, notes and checklist for this flight are removed from the device. This cannot be undone.")
            }
        }
    }

    /// Explains the drawing. Two lines that differ is the point of this map, so
    /// what each one means has to be stated rather than inferred.
    private var trackLegend: some View {
        let deviation = record.deviation
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 12) {
                legendKey("Planned", .blue, dashed: true)
                legendKey("Flown", .green, dashed: false)
                if deviation.max >= FlightTrackMap.divergenceNM {
                    legendKey("Off plan", .orange, dashed: false)
                }
            }
            if record.track.count < 2 {
                Text("No track recorded for this flight — the route is shown alone.")
                    .font(.caption2).foregroundColor(.secondary)
            } else if record.neverMoved {
                Text("Recorded without moving — the track is a single point where the device sat, so there is no path to compare against the plan.")
                    .font(.caption2).foregroundColor(.secondary)
            } else if deviation.max < FlightTrackMap.divergenceNM {
                Text(String(format: "Stayed within %.1f NM of the plan throughout.", deviation.max))
                    .font(.caption2).foregroundColor(.secondary)
            } else {
                Text(String(format: "Diverged up to %.1f NM from the plan (%.1f NM average). The widest point is marked.",
                            deviation.max, deviation.mean))
                    .font(.caption2).foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func layerToggle(_ title: String, isOn: Binding<Bool>, tint: Color) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
                Text(title).font(.caption).fontWeight(.medium)
            }
            .foregroundColor(isOn.wrappedValue ? tint : .secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((isOn.wrappedValue ? tint : Color.secondary).opacity(0.14))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func legendKey(_ label: String, _ colour: Color, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(colour)
                .frame(width: 14, height: 2)
                .opacity(dashed ? 0.6 : 1)
            Text(label).font(.caption2).foregroundColor(.secondary)
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

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption).fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
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
/// The flight drawn against its plan.
///
/// Two lines, deliberately different in weight and style: the plan is a dashed
/// ghost because it is the reference, and the track flown is solid because it is
/// what happened. Where the two agree the second hides the first, which is the
/// point — divergence is what this map is for, so it is the only thing that stands
/// out. Sections that stray beyond a threshold are drawn in orange and the widest
/// point is pinned with its distance, because "how far off were we, and where"
/// is the question a pilot actually asks afterwards.
struct FlightTrackMap: UIViewRepresentable {
    let record: FlightRecord
    var showPlanned = true
    var showFlown = true

    /// Beyond this, a track counts as having left the plan rather than just
    /// wandering within normal tracking tolerance.
    static let divergenceNM: Double = 2.0

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = true
        map.isRotateEnabled = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        let planned = record.plannedPoints.map(\.coordinate)
        if planned.count >= 2, showPlanned {
            let line = MKPolyline(coordinates: planned, count: planned.count)
            line.title = "planned"
            map.addOverlay(line)
        }

        // Waypoints, so the plan reads as a route rather than a bare line.
        for point in record.plannedPoints where showPlanned {
            let pin = MKPointAnnotation()
            pin.coordinate = point.coordinate
            pin.title = point.ident
            map.addAnnotation(pin)
        }

        if record.track.count >= 2, showFlown, !record.neverMoved {
            // The track is split into runs of "on plan" and "off plan" so the two
            // can be drawn in different colours. Each run repeats the boundary fix
            // so the line stays continuous across a colour change.
            var runs: [(coords: [CLLocationCoordinate2D], off: Bool)] = []
            var current: [CLLocationCoordinate2D] = []
            var currentOff: Bool?
            var worst = (distance: 0.0, coordinate: record.track[0].coordinate)

            for fix in record.track {
                var best = Double.greatestFiniteMagnitude
                if planned.count >= 2 {
                    for i in 1..<planned.count {
                        best = min(best, FlightRecord.crossTrackNM(point: fix.coordinate,
                                                                   from: planned[i - 1], to: planned[i]))
                    }
                } else { best = 0 }
                if best > worst.distance { worst = (best, fix.coordinate) }

                let off = best >= Self.divergenceNM
                if currentOff == nil { currentOff = off }
                if off != currentOff {
                    current.append(fix.coordinate)
                    runs.append((current, currentOff!))
                    current = [fix.coordinate]
                    currentOff = off
                } else {
                    current.append(fix.coordinate)
                }
            }
            if current.count >= 2, let off = currentOff { runs.append((current, off)) }

            for run in runs where run.coords.count >= 2 {
                let line = MKPolyline(coordinates: run.coords, count: run.coords.count)
                line.title = run.off ? "off" : "flown"
                map.addOverlay(line)
            }

            if worst.distance >= Self.divergenceNM {
                let pin = MKPointAnnotation()
                pin.coordinate = worst.coordinate
                pin.title = String(format: "%.1f NM off plan", worst.distance)
                map.addAnnotation(pin)
            }
        } else if showFlown, record.neverMoved, let first = record.track.first {
            // A stationary recording is a place, not a path. Drawn as one point and
            // labelled, rather than as a scribble of GPS jitter that would otherwise
            // be measured against the route and reported as a huge divergence.
            let pin = MKPointAnnotation()
            pin.coordinate = first.coordinate
            pin.title = "Recorded here — did not move"
            map.addAnnotation(pin)
        }

        // Frame everything drawn, plan included, so a short track does not zoom in
        // so far that the route it belongs to is off screen.
        let rect = map.overlays.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
        if !rect.isNull {
            map.setVisibleMapRect(rect,
                                  edgePadding: UIEdgeInsets(top: 34, left: 34, bottom: 34, right: 34),
                                  animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            switch line.title {
            case "planned":
                renderer.strokeColor = .systemBlue.withAlphaComponent(0.65)
                renderer.lineWidth = 3
                renderer.lineDashPattern = [6, 6]
            case "off":
                renderer.strokeColor = .systemOrange
                renderer.lineWidth = 5
            default:
                renderer.strokeColor = .systemGreen
                renderer.lineWidth = 4
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "pt"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            let title = (annotation.title ?? "") ?? ""
            let isDeviation = title.contains("off plan")
            let isParked = title.contains("did not move")
            view.markerTintColor = isDeviation ? .systemOrange : (isParked ? .systemGreen : .systemBlue)
            view.glyphImage = UIImage(systemName: isDeviation ? "exclamationmark"
                                                 : (isParked ? "figure.stand" : "mappin"))
            view.displayPriority = (isDeviation || isParked) ? .required : .defaultLow
            return view
        }
    }
}

/// The altitude actually flown, against the level that was planned.
///
/// Deliberately spare: one line, one reference, no axes furniture. The question it
/// answers is "did I fly the profile", and that is legible from the shape alone.
struct AltitudeTraceChart: View {
    let record: FlightRecord

    var body: some View {
        GeometryReader { geo in chart(in: geo.size) }
    }

    private var trace: [(distanceNM: Double, altitudeFT: Double)] { record.altitudeTrace }
    private var maxDistance: Double { max(trace.last?.distanceNM ?? 1, 0.001) }
    private var ceiling: Double {
        max(max(trace.map(\.altitudeFT).max() ?? 0, Double(record.plannedCruiseFT)) * 1.15, 1)
    }

    private func x(_ d: Double, _ size: CGSize) -> CGFloat {
        size.width * CGFloat(d / maxDistance)
    }

    private func y(_ ft: Double, _ size: CGSize) -> CGFloat {
        size.height * (1 - CGFloat(ft / ceiling))
    }

    private func chart(in size: CGSize) -> some View {
        let plannedY = y(Double(record.plannedCruiseFT), size)
        return ZStack(alignment: .topLeading) {
            // Planned cruise level, as a reference to read the flown line against.
            Path { p in
                p.move(to: CGPoint(x: 0, y: plannedY))
                p.addLine(to: CGPoint(x: size.width, y: plannedY))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundColor(.secondary.opacity(0.7))

            Path { p in
                guard let first = trace.first else { return }
                p.move(to: CGPoint(x: x(first.distanceNM, size), y: y(first.altitudeFT, size)))
                for point in trace.dropFirst() {
                    p.addLine(to: CGPoint(x: x(point.distanceNM, size), y: y(point.altitudeFT, size)))
                }
            }
            .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

            Text("\(record.plannedCruiseFT.formatted()) ft planned")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .offset(y: max(plannedY - 12, 0))
        }
    }
}
