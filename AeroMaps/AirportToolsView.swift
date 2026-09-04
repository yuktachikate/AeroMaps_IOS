import SwiftUI
import MapKit

// MARK: - Airport diagram ("Plates")

/// A scale runway diagram drawn from the airport's own runway data, plus the field
/// facts a pilot wants on the ramp.
///
/// This is not a published airport diagram or approach plate — AeroMaps ships no
/// chart data. It draws what it actually knows: runway headings, lengths and
/// surfaces, field elevation, and the frequencies in the database.
struct AirportToolsView: View {
    @ObservedObject var mapState: MapState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedICAO: String?

    private var routeAirports: [Airport] {
        mapState.route.waypoints.compactMap { $0.airportICAO.flatMap { mapState.airports[$0] } }
    }

    private var selected: Airport? {
        if let selectedICAO, let a = mapState.airports[selectedICAO] { return a }
        return routeAirports.first ?? mapState.selectedAirport
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if routeAirports.isEmpty && mapState.selectedAirport == nil {
                        emptyState
                    } else {
                        if routeAirports.count > 1 { airportPicker }
                        if let airport = selected {
                            diagramCard(airport)
                            runwayTable(airport)
                            fieldFacts(airport)
                        }
                        Text("Drawn from AeroMaps' runway database. Official airport diagrams, approach plates and taxi charts are not included — carry current published charts.")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Airport Diagram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var airportPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(routeAirports) { airport in
                    let isSelected = selected?.icao == airport.icao
                    Button { selectedICAO = airport.icao } label: {
                        Text(airport.icao)
                            .font(.caption).fontWeight(.bold)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func diagramCard(_ airport: Airport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(airport.icao).font(.headline).fontWeight(.heavy)
                    Text(airport.name).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Text("\(airport.elevation.formatted()) ft")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            RunwayDiagram(runways: airport.runways)
                .frame(height: 240)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func runwayTable(_ airport: Airport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RUNWAYS").font(.system(size: 9, weight: .heavy)).foregroundColor(.secondary)
            ForEach(airport.runways) { runway in
                HStack {
                    Text(runway.designation).font(.caption).fontWeight(.bold).frame(width: 70, alignment: .leading)
                    Text("\(runway.length.formatted()) × \(runway.width) ft").font(.caption2)
                    Spacer()
                    Text(runway.surface).font(.caption2).foregroundColor(.secondary)
                    if runway.lighted {
                        Image(systemName: "lightbulb.fill").font(.system(size: 9)).foregroundColor(.yellow)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func fieldFacts(_ airport: Airport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FIELD").font(.system(size: 9, weight: .heavy)).foregroundColor(.secondary)
            fact("Location", [airport.city, airport.state].filter { !$0.isEmpty }.joined(separator: ", "))
            fact("Elevation", "\(airport.elevation.formatted()) ft MSL")
            fact("Pattern altitude", "\((airport.elevation + 1_000).formatted()) ft MSL")
            fact("Position", Waypoint.formatCoordinate(airport.coordinate))
            if !airport.services.isEmpty {
                fact("Services", airport.services.joined(separator: ", "))
            }
            ForEach(airport.frequencies) { freq in
                fact(freq.type, freq.frequency)
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.largeTitle).foregroundColor(.secondary)
            Text("Add an airport to your route, or select one on the map, to see its diagram.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }
}

/// Runways drawn to scale and rotated to their real headings, north up.
///
/// Parallel runways share a heading, so they are fanned apart perpendicular to that
/// heading — otherwise 10L/28R and 10R/28L land on exactly the same line and their
/// labels overprint each other.
struct RunwayDiagram: View {
    let runways: [Runway]

    private struct Placed: Identifiable {
        let id = UUID()
        let runway: Runway
        let heading: Double
        let offsetIndex: Double   // signed position within its parallel group
    }

    /// Groups runways by heading and assigns each a symmetric offset slot.
    private var placed: [Placed] {
        var groups: [Int: [Runway]] = [:]
        for runway in runways {
            guard let heading = runway.trueHeadingLow ?? Self.heading(runway.designation) else { continue }
            // Group by rounded heading so parallels still fan apart together.
            groups[Int(heading.rounded()), default: []].append(runway)
        }
        var out: [Placed] = []
        for (heading, group) in groups.sorted(by: { $0.key < $1.key }) {
            let count = Double(group.count)
            for (i, runway) in group.enumerated() {
                out.append(Placed(runway: runway,
                                  heading: Double(heading),
                                  offsetIndex: Double(i) - (count - 1) / 2))
            }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let longest = Double(runways.map(\.length).max() ?? 1)
            let maxRadius = min(geo.size.width, geo.size.height) * 0.38
            let separation = maxRadius * 0.22

            ZStack {
                VStack(spacing: 2) {
                    Image(systemName: "location.north.fill").font(.system(size: 11))
                    Text("N").font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.secondary)
                .position(x: geo.size.width - 20, y: 22)

                ForEach(placed) { item in
                    let halfLength = maxRadius * (Double(item.runway.length) / longest)
                    let radians = (item.heading - 90) * .pi / 180
                    let dx = cos(radians) * halfLength
                    let dy = sin(radians) * halfLength
                    // Perpendicular unit vector, used to fan parallel strips apart.
                    let ox = -sin(radians) * separation * item.offsetIndex
                    let oy = cos(radians) * separation * item.offsetIndex
                    let mid = CGPoint(x: centre.x + ox, y: centre.y + oy)
                    let startPoint = CGPoint(x: mid.x - dx, y: mid.y - dy)
                    let endPoint = CGPoint(x: mid.x + dx, y: mid.y + dy)

                    Path { p in
                        p.move(to: startPoint)
                        p.addLine(to: endPoint)
                    }
                    .stroke(Color.primary.opacity(0.8), style: StrokeStyle(lineWidth: 11, lineCap: .butt))

                    Path { p in
                        p.move(to: startPoint)
                        p.addLine(to: endPoint)
                    }
                    .stroke(Color(.systemBackground), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))

                    let ends = item.runway.designation.split(separator: "/").map(String.init)
                    if ends.count == 2 {
                        Text(ends[0])
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.secondary)
                            .fixedSize()
                            .position(x: mid.x - dx * 1.22, y: mid.y - dy * 1.22)
                        Text(ends[1])
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.secondary)
                            .fixedSize()
                            .position(x: mid.x + dx * 1.22, y: mid.y + dy * 1.22)
                    }
                }
            }
        }
        .padding(16)
    }

    /// Uses the first end of "10L/28R" to orient the strip.
    private static func heading(_ designation: String) -> Double? {
        let first = designation.split(separator: "/").first.map(String.init) ?? designation
        let digits = first.prefix { $0.isNumber }
        guard let number = Int(digits), (1...36).contains(number) else { return nil }
        return Double(number * 10)
    }
}

// MARK: - Checklist

struct ChecklistItem: Identifiable {
    let id: String
    let action: String
    let response: String
}

struct ChecklistPhase: Identifiable {
    let id: String
    let title: String
    let icon: String
    let tint: Color
    let items: [ChecklistItem]
}

/// Standard light-single flow, phase by phase. Ticks live in MapState so the state
/// survives closing and reopening the sheet mid-flight.
struct ChecklistView: View {
    @ObservedObject var mapState: MapState
    @Environment(\.dismiss) private var dismiss

    static let phases: [ChecklistPhase] = [
        ChecklistPhase(id: "preflight", title: "Preflight", icon: "checklist", tint: .blue, items: [
            ChecklistItem(id: "pf1", action: "Documents", response: "ARROW aboard"),
            ChecklistItem(id: "pf2", action: "Weather & NOTAMs", response: "Reviewed"),
            ChecklistItem(id: "pf3", action: "Weight & balance", response: "Within limits"),
            ChecklistItem(id: "pf4", action: "Fuel quantity", response: "Checked, sumped"),
            ChecklistItem(id: "pf5", action: "Control surfaces", response: "Free and correct"),
            ChecklistItem(id: "pf6", action: "Route loaded", response: "Verified on map")
        ]),
        ChecklistPhase(id: "beforeStart", title: "Before Start", icon: "key.fill", tint: .purple, items: [
            ChecklistItem(id: "bs1", action: "Seats & belts", response: "Secure"),
            ChecklistItem(id: "bs2", action: "Brakes", response: "Set"),
            ChecklistItem(id: "bs3", action: "Circuit breakers", response: "In"),
            ChecklistItem(id: "bs4", action: "Avionics", response: "Off"),
            ChecklistItem(id: "bs5", action: "Mixture", response: "Rich")
        ]),
        ChecklistPhase(id: "runup", title: "Run-up", icon: "gauge.high", tint: .orange, items: [
            ChecklistItem(id: "ru1", action: "Throttle", response: "1800 RPM"),
            ChecklistItem(id: "ru2", action: "Magnetos", response: "Checked"),
            ChecklistItem(id: "ru3", action: "Carb heat", response: "Checked"),
            ChecklistItem(id: "ru4", action: "Engine gauges", response: "Green"),
            ChecklistItem(id: "ru5", action: "Flight instruments", response: "Set")
        ]),
        ChecklistPhase(id: "takeoff", title: "Takeoff", icon: "airplane.departure", tint: .green, items: [
            ChecklistItem(id: "to1", action: "Runway", response: "Confirmed, clear"),
            ChecklistItem(id: "to2", action: "Flaps", response: "Set for takeoff"),
            ChecklistItem(id: "to3", action: "Transponder", response: "ALT"),
            ChecklistItem(id: "to4", action: "Lights", response: "On"),
            ChecklistItem(id: "to5", action: "Engine instruments", response: "Green on roll")
        ]),
        ChecklistPhase(id: "cruise", title: "Cruise", icon: "arrow.right", tint: .cyan, items: [
            ChecklistItem(id: "cr1", action: "Power", response: "Set"),
            ChecklistItem(id: "cr2", action: "Mixture", response: "Leaned"),
            ChecklistItem(id: "cr3", action: "Altitude", response: "Cruise level, hemispherical"),
            ChecklistItem(id: "cr4", action: "Fuel", response: "Balanced, log time")
        ]),
        ChecklistPhase(id: "descent", title: "Descent & Landing", icon: "airplane.arrival", tint: .red, items: [
            ChecklistItem(id: "ds1", action: "ATIS / weather", response: "Obtained"),
            ChecklistItem(id: "ds2", action: "Altimeter", response: "Set"),
            ChecklistItem(id: "ds3", action: "Mixture", response: "Rich"),
            ChecklistItem(id: "ds4", action: "Landing runway", response: "Briefed"),
            ChecklistItem(id: "ds5", action: "Flaps & speed", response: "As required")
        ]),
        ChecklistPhase(id: "emergency", title: "Engine Failure", icon: "exclamationmark.triangle.fill", tint: .yellow, items: [
            ChecklistItem(id: "em1", action: "Airspeed", response: "Best glide"),
            ChecklistItem(id: "em2", action: "Landing site", response: "Selected"),
            ChecklistItem(id: "em3", action: "Fuel selector / mixture / mags", response: "Restart attempt"),
            ChecklistItem(id: "em4", action: "Mayday 121.5 · squawk 7700", response: "Transmit"),
            ChecklistItem(id: "em5", action: "Doors & belts", response: "Unlatched, tight")
        ])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Self.phases) { phase in
                        phaseCard(phase)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Checklists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") { mapState.checkedChecklistItems.removeAll() }
                }
            }
        }
    }

    private func phaseCard(_ phase: ChecklistPhase) -> some View {
        let done = phase.items.filter { mapState.checkedChecklistItems.contains($0.id) }.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: phase.icon).foregroundColor(phase.tint)
                Text(phase.title).font(.subheadline).fontWeight(.bold)
                Spacer()
                Text("\(done)/\(phase.items.count)")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(done == phase.items.count ? .green : .secondary)
            }

            ForEach(phase.items) { item in
                let checked = mapState.checkedChecklistItems.contains(item.id)
                Button {
                    if checked { mapState.checkedChecklistItems.remove(item.id) }
                    else { mapState.checkedChecklistItems.insert(item.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(checked ? .green : .secondary)
                        Text(item.action)
                            .font(.caption).fontWeight(.medium)
                            .strikethrough(checked, color: .secondary)
                        Spacer()
                        Text(item.response)
                            .font(.caption2).foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(checked ? Color.green.opacity(0.1) : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Notes

/// Free-text scratchpad for clearances, frequencies and ATIS copy.
struct FlightNotesView: View {
    @ObservedObject var mapState: MapState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Scratchpad for clearances, ATIS and frequencies. Kept with this flight for the session.")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.horizontal, 16)

                TextEditor(text: $mapState.flightNotes)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .focused($focused)

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Flight Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") { mapState.flightNotes = "" }
                        .disabled(mapState.flightNotes.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}
