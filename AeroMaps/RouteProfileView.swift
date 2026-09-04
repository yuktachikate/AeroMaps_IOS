import SwiftUI
import MapKit

/// Vertical profile of the route: planned altitude over along-track distance, with
/// sampled terrain underneath and the waypoints marked along the bottom.
///
/// This is the view that makes the altitude plan legible — a leg that looks fine as
/// a number in a list is obviously wrong when its line clips the ground.
struct RouteProfileView: View {
    @ObservedObject var mapState: MapState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedLegID: UUID?

    private var profile: AltitudeProfile { mapState.altitudeProfile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if profile.isEmpty {
                        emptyState
                    } else {
                        chartCard
                        summaryRow
                        cameraCard
                        legList
                    }
                }
                .padding(16)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Vertical Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(profile.legs.first?.fromIdent ?? "") → \(profile.legs.last?.toIdent ?? "")")
                    .font(.headline).fontWeight(.bold)
                Spacer()
                if mapState.terrain.isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            ProfileChart(profile: profile,
                         waypoints: mapState.route.waypoints,
                         cruiseFT: mapState.route.altitudeFT)
                .frame(height: 220)

            HStack(spacing: 14) {
                legendDot(color: .cyan, label: "Planned altitude")
                legendDot(color: .brown, label: profile.maxTerrainFT == nil ? "Terrain (unavailable)" : "Terrain")
                legendDot(color: .orange, label: "Clearance alert")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }

    // MARK: Summary

    private var summaryRow: some View {
        HStack(spacing: 0) {
            summaryBlock("Distance", "\(Int(profile.totalDistanceNM.rounded())) NM", "ruler", .cyan)
            summaryBlock("Time", formattedTime(profile.totalTimeMinutes), "clock", .blue)
            summaryBlock("Fuel", String(format: "%.1f gal", profile.totalFuelGallons), "fuelpump", .orange)
            summaryBlock("Peak terrain",
                         profile.maxTerrainFT.map { "\($0.formatted()) ft" } ?? "—",
                         "mountain.2.fill", .brown)
            summaryBlock("Top of climb", "\(Int(profile.topOfClimbNM.rounded())) NM",
                         "arrow.up.right", .green)
            summaryBlock("Top of descent", "\(Int(profile.topOfDescentNM.rounded())) NM",
                         "arrow.down.right", .orange)
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func summaryBlock(_ title: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundColor(tint)
            Text(value).font(.subheadline).fontWeight(.bold)
            Text(title).font(.system(size: 9)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 3D camera

    private var cameraCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("3D Map View", systemImage: "rotate.3d")
                .font(.subheadline).fontWeight(.bold)

            Text("Tilts the map along the route so the terrain under each leg is visible in relief.")
                .font(.caption).foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button {
                    applyCamera(pitch: 65, altitudeMode: .terrain)
                    dismiss()
                } label: {
                    Label("Fly the route in 3D", systemImage: "mountain.2.circle.fill")
                        .font(.caption).fontWeight(.bold)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.orange).foregroundColor(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    applyCamera(pitch: 0, altitudeMode: .flat)
                    dismiss()
                } label: {
                    Label("Top-down", systemImage: "map.fill")
                        .font(.caption).fontWeight(.bold)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private enum AltitudeMode { case terrain, flat }

    private func applyCamera(pitch: CGFloat, altitudeMode: AltitudeMode) {
        let waypoints = mapState.route.waypoints
        guard waypoints.count >= 2 else { return }
        let course = AltitudePlanner.bearingDegrees(from: waypoints[0].coordinate,
                                                    to: waypoints[1].coordinate)
        mapState.mapStyle = altitudeMode == .terrain ? .hybrid : .standard
        mapState.camera = MKMapCamera(lookingAtCenter: waypoints[0].coordinate,
                                      fromDistance: altitudeMode == .terrain ? 20_000 : 90_000,
                                      pitch: pitch,
                                      heading: course)
        mapState.shouldCenterCamera = true
        mapState.activeTab = 0
    }

    // MARK: Legs

    private var legList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LEGS")
                .font(.caption2).fontWeight(.heavy).foregroundColor(.secondary)

            ForEach(profile.legs) { leg in
                let conflict = leg.hasTerrainConflict(minClearanceFT: AltitudeProfile.minimumClearanceFT)
                HStack(spacing: 12) {
                    Image(systemName: leg.phase.symbolName)
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(phaseColor(leg.phase))
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(leg.fromIdent) → \(leg.toIdent)")
                            .font(.subheadline).fontWeight(.semibold)
                            .lineLimit(1)
                        Text("\(leg.startAltitudeFT.formatted()) → \(leg.endAltitudeFT.formatted()) ft · \(leg.phase.rawValue)")
                            .font(.caption2).foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(leg.distanceNM.rounded())) NM")
                            .font(.caption).fontWeight(.semibold)
                        Text(String(format: "%03.0f°T · %d min", leg.courseTrue, Int(leg.timeMinutes.rounded())))
                            .font(.system(size: 9)).foregroundColor(.secondary)
                    }

                    if conflict {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(conflict ? Color.orange.opacity(0.12) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func phaseColor(_ phase: FlightPhase) -> Color {
        switch phase {
        case .climb:   return .green
        case .cruise:  return .cyan
        case .descent: return .orange
        case .climbCruise, .cruiseDescent, .mixed: return .purple
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle).foregroundColor(.secondary)
            Text("Add at least two waypoints to see a vertical profile.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func formattedTime(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total) min"
    }
}

// MARK: - Chart

/// Altitude-over-distance plot with the terrain silhouette beneath it.
struct ProfileChart: View {
    let profile: AltitudeProfile
    let waypoints: [Waypoint]
    let cruiseFT: Int

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: 34, y: 8,
                              width: max(geo.size.width - 44, 1),
                              height: max(geo.size.height - 34, 1))
            let range = altitudeRange()

            ZStack(alignment: .topLeading) {
                gridAndLabels(plot: plot, range: range)
                terrainShape(plot: plot, range: range)
                altitudeShape(plot: plot, range: range)
                altitudeLine(plot: plot, range: range)
                waypointMarkers(plot: plot, range: range)
            }
        }
    }

    // Padded so the curve never touches the frame edges.
    private func altitudeRange() -> (min: Double, max: Double) {
        var lo = 0.0
        var hi = Double(max(cruiseFT, 1_000))
        for sample in profile.samples {
            hi = Swift.max(hi, sample.altitudeFT)
            if let terrain = sample.terrainFT { hi = Swift.max(hi, terrain) }
        }
        hi *= 1.18
        if let peak = profile.maxTerrainFT { lo = Swift.min(lo, Double(peak) - 2_000) }
        return (Swift.max(lo, -500), Swift.max(hi, 2_000))
    }

    private func x(_ distance: Double, _ plot: CGRect) -> CGFloat {
        guard profile.totalDistanceNM > 0 else { return plot.minX }
        return plot.minX + plot.width * CGFloat(distance / profile.totalDistanceNM)
    }

    private func y(_ altitude: Double, _ plot: CGRect, _ range: (min: Double, max: Double)) -> CGFloat {
        let span = Swift.max(range.max - range.min, 1)
        return plot.maxY - plot.height * CGFloat((altitude - range.min) / span)
    }

    private func gridAndLabels(plot: CGRect, range: (min: Double, max: Double)) -> some View {
        let steps = 4
        return ZStack(alignment: .topLeading) {
            ForEach(0...steps, id: \.self) { i in
                let value = range.min + (range.max - range.min) * Double(i) / Double(steps)
                let yPos = y(value, plot, range)
                Path { p in
                    p.move(to: CGPoint(x: plot.minX, y: yPos))
                    p.addLine(to: CGPoint(x: plot.maxX, y: yPos))
                }
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)

                Text("\(Int((value / 100).rounded()) * 100)")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .position(x: plot.minX - 17, y: yPos)
            }

            // Cruise altitude reference line.
            let cruiseY = y(Double(cruiseFT), plot, range)
            Path { p in
                p.move(to: CGPoint(x: plot.minX, y: cruiseY))
                p.addLine(to: CGPoint(x: plot.maxX, y: cruiseY))
            }
            .stroke(Color.cyan.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // Total distance sits inside the plot; the axis below belongs to the
            // waypoint idents, which would otherwise collide with it.
            Text("\(Int(profile.totalDistanceNM.rounded())) NM total")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .position(x: plot.maxX - 34, y: plot.minY + 8)
        }
    }

    private func terrainShape(plot: CGRect, range: (min: Double, max: Double)) -> some View {
        Path { p in
            let terrainSamples = profile.samples.filter { $0.terrainFT != nil }
            guard let first = terrainSamples.first else { return }
            p.move(to: CGPoint(x: x(first.distanceNM, plot), y: plot.maxY))
            for sample in terrainSamples {
                p.addLine(to: CGPoint(x: x(sample.distanceNM, plot), y: y(sample.terrainFT!, plot, range)))
            }
            if let last = terrainSamples.last {
                p.addLine(to: CGPoint(x: x(last.distanceNM, plot), y: plot.maxY))
            }
            p.closeSubpath()
        }
        .fill(LinearGradient(colors: [Color.brown.opacity(0.75), Color.brown.opacity(0.35)],
                             startPoint: .top, endPoint: .bottom))
    }

    private func altitudeShape(plot: CGRect, range: (min: Double, max: Double)) -> some View {
        Path { p in
            guard let first = profile.samples.first else { return }
            p.move(to: CGPoint(x: x(first.distanceNM, plot), y: plot.maxY))
            for sample in profile.samples {
                p.addLine(to: CGPoint(x: x(sample.distanceNM, plot), y: y(sample.altitudeFT, plot, range)))
            }
            if let last = profile.samples.last {
                p.addLine(to: CGPoint(x: x(last.distanceNM, plot), y: plot.maxY))
            }
            p.closeSubpath()
        }
        .fill(LinearGradient(colors: [Color.cyan.opacity(0.35), Color.cyan.opacity(0.04)],
                             startPoint: .top, endPoint: .bottom))
    }

    private func altitudeLine(plot: CGRect, range: (min: Double, max: Double)) -> some View {
        Path { p in
            guard let first = profile.samples.first else { return }
            p.move(to: CGPoint(x: x(first.distanceNM, plot), y: y(first.altitudeFT, plot, range)))
            for sample in profile.samples.dropFirst() {
                p.addLine(to: CGPoint(x: x(sample.distanceNM, plot), y: y(sample.altitudeFT, plot, range)))
            }
        }
        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    private func waypointMarkers(plot: CGRect, range: (min: Double, max: Double)) -> some View {
        var cumulative: [Double] = [0]
        for i in 1..<Swift.max(waypoints.count, 1) {
            cumulative.append(cumulative[i - 1] + AltitudePlanner.distanceNM(waypoints[i - 1].coordinate,
                                                                            waypoints[i].coordinate))
        }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(waypoints.enumerated()), id: \.element.id) { index, wp in
                let distance = index < cumulative.count ? cumulative[index] : 0
                let altitude = Double(profile.waypointAltitudes[wp.id] ?? 0)
                let px = x(distance, plot)
                let py = y(altitude, plot, range)

                Path { p in
                    p.move(to: CGPoint(x: px, y: plot.minY))
                    p.addLine(to: CGPoint(x: px, y: plot.maxY))
                }
                .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))

                Circle()
                    .fill(wp.isAltitudeManual ? Color.yellow : Color.white)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.cyan, lineWidth: 2))
                    .position(x: px, y: py)

                // Keep end labels inside the frame instead of hanging off the edge.
                Text(wp.ident.prefix(5))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                    .fixedSize()
                    .position(x: Swift.min(Swift.max(px, plot.minX + 14), plot.maxX - 14),
                              y: plot.maxY + 14)
            }
        }
    }
}
