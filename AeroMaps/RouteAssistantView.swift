import SwiftUI

/// Everything the app can do *to* a route, in one place: build one from scratch,
/// compare reshapings of the one you have, and check it. They are the same question
/// asked three ways, so they share a screen rather than three toolbar buttons.
struct RouteAssistantView: View {
    @ObservedObject var mapState: MapState
    /// Which section opens first, depending on which button was pressed.
    var initialTab: Tab = .validate
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case generate = "Generate"
        case alternatives = "Alternatives"
        case validate = "Check"
        var id: String { rawValue }

        init(storageKey: String) {
            switch storageKey {
            case "generate":     self = .generate
            case "alternatives": self = .alternatives
            default:             self = .validate
            }
        }

        var icon: String {
            switch self {
            case .generate:     return "wand.and.stars"
            case .alternatives: return "arrow.triangle.branch"
            case .validate:     return "checkmark.shield"
            }
        }
    }

    @State private var tab: Tab = .validate
    @State private var proposal: RouteGenerator.Proposal?
    @State private var isGenerating = false

    private var findings: [RouteValidator.Finding] {
        RouteValidator.validate(route: mapState.route,
                                profile: mapState.altitudeProfile,
                                terrainLoaded: !mapState.terrain.sampler.isEmpty,
                                hazards: mapState.aviationWeather.hazards,
                                hazardFreshness: mapState.aviationWeather.hazardFreshness,
                                notamStatus: mapState.notams.status,
                                notamCount: mapState.notams.notams.count,
                                airspace: mapState.airspace,
                                isStudentPilot: mapState.isStudentPilot)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Label(t.rawValue, systemImage: t.icon).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if mapState.route.waypoints.count < 2 {
                            emptyState
                        } else {
                            switch tab {
                            case .generate:     generateSection
                            case .alternatives: alternativesSection
                            case .validate:     validateSection
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Route Advisor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { tab = initialTab }
            .task {
                // Pull hazard advisories and observations for the check.
                await mapState.aviationWeather.loadHazards()
                mapState.refreshRouteWeather()
                mapState.airspace.load(along: mapState.route.waypoints)
            }
        }
    }

    // MARK: Generate

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Fill out \(mapState.route.waypoints.map(\.ident).joined(separator: " → "))")
                    .font(.headline)
                Text("Keeps every point you placed, in order, and adds en-route checkpoints inside your existing legs — plus a fuel stop if the \(mapState.route.aircraft.name) cannot make it in one go, and altitudes that clear the terrain. Everything it adds stays editable.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Button {
                Task { await runGeneration() }
            } label: {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView().controlSize(.small).tint(.black)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isGenerating ? "Surveying terrain…"
                         : (proposal == nil ? "Generate route" : "Generate again"))
                        .fontWeight(.bold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.yellow).foregroundColor(.black)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)

            if let proposal {
                proposalCard(proposal)
            }
        }
    }

    private func proposalCard(_ proposal: RouteGenerator.Proposal) -> some View {
        // Altitudes for the proposal's own points, so the list can show what the
        // aircraft is doing vertically at each one.
        let profile = AltitudePlanner.computeProfile(
            waypoints: proposal.waypoints,
            cruiseAltitudeFT: proposal.cruiseAltitudeFT,
            performance: mapState.route.performance,
            terrain: nil)

        return VStack(alignment: .leading, spacing: 12) {
            RoutePreviewCard(waypoints: proposal.waypoints)

            HStack(spacing: 0) {
                metric("\(proposal.waypoints.count)", "points", "mappin", .cyan)
                metric("\(Int(proposal.distanceNM.rounded()))", "NM", "ruler", .blue)
                metric(formattedTime(proposal.timeMinutes), "", "clock", .purple)
                metric(String(format: "%.1f", proposal.fuelGallons), "gal", "fuelpump", .orange)
                metric("\(proposal.cruiseAltitudeFT.formatted())", "ft", "arrow.up.to.line", .green)
            }
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(proposal.notes) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: note.icon)
                            .font(.caption)
                            .foregroundColor(note.kind == .caution ? .orange : .secondary)
                            .frame(width: 18)
                        Text(note.text)
                            .font(.caption)
                            .foregroundColor(note.kind == .caution ? .primary : .secondary)
                        Spacer(minLength: 0)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("PROPOSED ROUTE")
                    .font(.system(size: 9, weight: .heavy)).foregroundColor(.secondary)
                ForEach(Array(proposal.waypoints.enumerated()), id: \.element.id) { index, wp in
                    let altitude = profile.waypointAltitudes[wp.id]
                    let phase = profile.waypointPhases[wp.id]
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption2).fontWeight(.heavy)
                            .foregroundColor(.secondary).frame(width: 16)
                        Image(systemName: wp.kind.symbolName)
                            .font(.caption2).foregroundColor(.cyan).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(wp.ident).font(.caption).fontWeight(.semibold).lineLimit(1)
                            // Why this point is on the route at all. Points the pilot
                            // placed have no reason and just show their kind.
                            Text(wp.reason ?? wp.kind.label)
                                .font(.system(size: 9))
                                .foregroundColor(wp.reason == nil ? .secondary : .orange)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 6)
                        if let altitude {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(altitude.formatted()) ft")
                                    .font(.caption).fontWeight(.bold)
                                    .monospacedDigit()
                                if let phase {
                                    HStack(spacing: 3) {
                                        Image(systemName: phase.symbolName)
                                            .font(.system(size: 8, weight: .bold))
                                        Text(phase.shortLabel).font(.system(size: 8, weight: .heavy))
                                    }
                                    .foregroundColor(phaseTint(phase))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack(spacing: 10) {
                Button {
                    self.proposal = nil
                } label: {
                    Text("Discard").font(.caption).fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        mapState.route.waypoints = proposal.waypoints
                        mapState.route.altitudeFT = proposal.cruiseAltitudeFT
                    }
                    mapState.zoomToRoute()
                    dismiss()
                } label: {
                    Text("Use this route").font(.caption).fontWeight(.bold)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.green).foregroundColor(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func phaseTint(_ phase: FlightPhase) -> Color {
        switch phase {
        case .climb:   return .green
        case .cruise:  return .cyan
        case .descent: return .orange
        case .climbCruise, .cruiseDescent, .mixed: return .purple
        }
    }

    private func runGeneration() async {
        let existing = mapState.route.waypoints
        guard existing.count >= 2 else { return }
        isGenerating = true
        defer { isGenerating = false }

        // Survey the route as drawn, including any intermediate points.
        let sampler = try? await TerrainService.sampler(for: existing)
        proposal = RouteGenerator.generate(
            route: existing,
            aircraft: mapState.route.aircraft,
            performance: mapState.route.performance,
            fuelOnBoardGal: mapState.route.fuelOnBoardGal,
            airports: mapState.airports,
            terrain: (sampler?.isEmpty ?? true) ? nil : sampler)
    }

    // MARK: Alternatives

    private var alternativesSection: some View {
        let candidates = RouteAdvisor.candidates(for: mapState.route, airports: mapState.airports)
        let currentDistance = mapState.route.totalDistanceNM

        return VStack(alignment: .leading, spacing: 14) {
            Text("Reshapings of the route you already have. Computed from its geometry and the airport database — AeroMaps has no published airway or ATC-preferred-route data, so none is claimed here.")
                .font(.caption).foregroundColor(.secondary)

            ForEach(candidates) { candidate in
                candidateCard(candidate, currentDistance: currentDistance)
            }
        }
    }

    private func candidateCard(_ candidate: RouteCandidate, currentDistance: Double) -> some View {
        let performance = mapState.route.performance
        let delta = candidate.distanceNM - currentDistance
        let isCurrent = candidate.waypoints.map(\.id) == mapState.route.waypoints.map(\.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: candidate.iconName)
                    .font(.title3).foregroundColor(candidate.tint).frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title).font(.subheadline).fontWeight(.bold)
                    Text(candidate.waypoints.map(\.ident).joined(separator: " → "))
                        .font(.caption2).foregroundColor(.secondary).lineLimit(2)
                }

                Spacer()

                if isCurrent {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .heavy)).foregroundColor(.green)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.green.opacity(0.18)).clipShape(Capsule())
                }
            }

            Text(candidate.reason).font(.caption).foregroundColor(.secondary)

            if !candidate.isWithinFuelRange(performance: performance,
                                            fuelOnBoardGal: mapState.route.fuelOnBoardGal) {
                Label("Exceeds the \(String(format: "%.0f", mapState.route.fuelOnBoardGal)) gal aboard with a 30 min reserve — needs a fuel stop",
                      systemImage: "fuelpump.slash")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(.orange)
            }

            if !isCurrent {
                RoutePreviewCard(waypoints: candidate.waypoints, height: 150)
            }

            HStack(spacing: 14) {
                Label("\(Int(candidate.distanceNM.rounded())) NM", systemImage: "ruler")
                Label("\(Int(candidate.timeMinutes(performance: performance).rounded())) min", systemImage: "clock")
                Label(String(format: "%.1f gal", candidate.fuelGallons(performance: performance)), systemImage: "fuelpump")
                if abs(delta) >= 1 {
                    Text(delta > 0 ? "+\(Int(delta.rounded())) NM" : "\(Int(delta.rounded())) NM")
                        .fontWeight(.bold)
                        .foregroundColor(delta > 0 ? .orange : .green)
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            if !isCurrent {
                Button {
                    mapState.route.waypoints = candidate.waypoints
                    mapState.zoomToRoute()
                    dismiss()
                } label: {
                    Text("Use this route")
                        .font(.caption).fontWeight(.bold)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(candidate.tint.opacity(0.9)).foregroundColor(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Validate

    private var validateSection: some View {
        let all = findings
        let problems = all.filter { $0.severity > .pass }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: problems.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(problems.isEmpty ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(problems.isEmpty ? "Route checks out" : "\(problems.count) thing\(problems.count == 1 ? "" : "s") to look at")
                        .font(.headline)
                    Text(problems.isEmpty
                         ? "Terrain, altitude and fuel all check out for the \(mapState.route.aircraft.name)."
                         : "Checked against terrain, VFR cruising altitudes, aircraft limits and fuel reserves.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }

            ForEach(all) { finding in
                findingCard(finding)
            }

            Text("Checks are computed from the app's own data. They do not replace a preflight briefing, current charts or NOTAMs.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private func findingCard(_ finding: RouteValidator.Finding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: finding.severity.icon)
                    .font(.subheadline).foregroundColor(tint(finding.severity))
                Text(finding.title).font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(finding.severity.label)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(tint(finding.severity))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(tint(finding.severity).opacity(0.15))
                    .clipShape(Capsule())
            }

            Text(finding.detail).font(.caption).foregroundColor(.secondary)

            if let fix = finding.fix {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { apply(fix) }
                } label: {
                    Label(fix.title, systemImage: "wrench.and.screwdriver.fill")
                        .font(.caption).fontWeight(.bold)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(tint(finding.severity).opacity(0.9))
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func apply(_ fix: RouteValidator.Fix) {
        switch fix {
        case .setCruise(let ft):
            mapState.route.altitudeFT = ft
        case .setWaypointAltitude(let id, let ft):
            mapState.setWaypointAltitude(id: id, altitudeFT: ft)
        case .clearWaypointOverrides:
            for i in mapState.route.waypoints.indices {
                mapState.route.waypoints[i].plannedAltitudeFT = nil
            }
        }
    }

    private func tint(_ severity: RouteValidator.Severity) -> Color {
        switch severity {
        case .pass:     return .green
        case .advisory: return .blue
        case .caution:  return .yellow
        case .warning:  return .orange
        }
    }

    // MARK: Shared

    private func metric(_ value: String, _ unit: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.caption).fontWeight(.bold)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formattedTime(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.largeTitle).foregroundColor(.secondary)
            Text("Add a departure and a destination first.")
                .font(.subheadline).fontWeight(.semibold)
            Text("The assistant works between two points — press and hold the map, or type an airport, coordinates or a place into the route field.")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
}
