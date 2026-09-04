import Foundation
import SwiftUI

/// A flyable aircraft profile. Everything the vertical planner, the fuel check and
/// the route generator need comes from here — change the aircraft and the cruise
/// altitude, climb distances, leg times, fuel burn and range all move with it.
struct AircraftProfile: Identifiable, Equatable, Hashable, Codable {
    var id: String              // "C172", or a UUID string for a pilot's own aircraft
    var name: String            // "Cessna 172 Skyhawk"
    var category: String        // "Single-engine piston"
    /// Tail number, when the pilot has entered one. Pilots think in registrations —
    /// "N12345", not "a 172" — so this leads the display wherever it is set.
    var registration: String = ""
    /// False for the built-in types, which are read-only reference figures.
    var isCustom: Bool = false
    var cruiseKTAS: Double
    var climbRateFPM: Double
    var climbKTAS: Double
    var descentRateFPM: Double
    var descentKTAS: Double
    var fuelBurnGPH: Double
    var usableFuelGal: Double
    var serviceCeilingFT: Int
    /// Maximum demonstrated crosswind component, used by the runway briefing.
    var demonstratedCrosswindKT: Double
    var seats: Int

    var performance: AircraftPerformance {
        AircraftPerformance(
            cruiseKTAS: cruiseKTAS,
            climbRateFPM: climbRateFPM,
            climbKTAS: climbKTAS,
            descentRateFPM: descentRateFPM,
            descentKTAS: descentKTAS,
            fuelBurnGPH: fuelBurnGPH,
            serviceCeilingFT: serviceCeilingFT
        )
    }

    /// Still-air endurance in hours on full usable fuel.
    var enduranceHours: Double { fuelBurnGPH > 0 ? usableFuelGal / fuelBurnGPH : 0 }

    /// Still-air range in NM, before any reserve is taken out.
    var rangeNM: Double { enduranceHours * cruiseKTAS }

    var summaryLine: String {
        "\(Int(cruiseKTAS)) kt · \(String(format: "%.1f", fuelBurnGPH)) gph · \(serviceCeilingFT.formatted()) ft ceiling"
    }

    /// What to show on the chip and in lists: the tail number when known.
    var shortLabel: String { registration.isEmpty ? id : registration }
    var displayName: String { registration.isEmpty ? name : "\(registration) · \(name)" }
}

enum AircraftLibrary {
    /// Published book figures for common light aircraft, rounded to planning values.
    /// Read-only reference points; a pilot's own aircraft lives in AircraftStore.
    static let builtIn: [AircraftProfile] = [
        AircraftProfile(id: "C172", name: "Cessna 172 Skyhawk", category: "Single-engine piston",
                        cruiseKTAS: 120, climbRateFPM: 700, climbKTAS: 79,
                        descentRateFPM: 500, descentKTAS: 130,
                        fuelBurnGPH: 8.5, usableFuelGal: 53, serviceCeilingFT: 14_000,
                        demonstratedCrosswindKT: 15, seats: 4),

        AircraftProfile(id: "PA28", name: "Piper PA-28 Cherokee", category: "Single-engine piston",
                        cruiseKTAS: 130, climbRateFPM: 725, climbKTAS: 87,
                        descentRateFPM: 500, descentKTAS: 140,
                        fuelBurnGPH: 9.0, usableFuelGal: 48, serviceCeilingFT: 14_000,
                        demonstratedCrosswindKT: 17, seats: 4),

        AircraftProfile(id: "DA40", name: "Diamond DA40", category: "Single-engine piston",
                        cruiseKTAS: 140, climbRateFPM: 800, climbKTAS: 85,
                        descentRateFPM: 600, descentKTAS: 150,
                        fuelBurnGPH: 9.5, usableFuelGal: 40, serviceCeilingFT: 16_400,
                        demonstratedCrosswindKT: 20, seats: 4),

        AircraftProfile(id: "SR22", name: "Cirrus SR22", category: "High-performance single",
                        cruiseKTAS: 180, climbRateFPM: 1_270, climbKTAS: 110,
                        descentRateFPM: 700, descentKTAS: 190,
                        fuelBurnGPH: 16.0, usableFuelGal: 92, serviceCeilingFT: 17_500,
                        demonstratedCrosswindKT: 21, seats: 4),

        AircraftProfile(id: "BE58", name: "Beechcraft Baron 58", category: "Twin-engine piston",
                        cruiseKTAS: 200, climbRateFPM: 1_400, climbKTAS: 120,
                        descentRateFPM: 800, descentKTAS: 210,
                        fuelBurnGPH: 30.0, usableFuelGal: 166, serviceCeilingFT: 20_688,
                        demonstratedCrosswindKT: 22, seats: 6),

        AircraftProfile(id: "TBM9", name: "Daher TBM 940", category: "Single-engine turboprop",
                        cruiseKTAS: 330, climbRateFPM: 2_000, climbKTAS: 160,
                        descentRateFPM: 1_500, descentKTAS: 290,
                        fuelBurnGPH: 60.0, usableFuelGal: 292, serviceCeilingFT: 31_000,
                        demonstratedCrosswindKT: 25, seats: 6)
    ]

    static let `default` = builtIn[0]

    /// Built-in types plus the pilot's own aircraft.
    static var all: [AircraftProfile] { builtIn + AircraftStore.shared.custom }

    static func profile(id: String) -> AircraftProfile {
        all.first { $0.id == id } ?? `default`
    }
}

/// Persistence for aircraft the pilot has entered.
///
/// Book figures for a type are a starting point, not a flight plan. Almost every
/// GA pilot flies one specific airframe whose numbers differ from the book — a
/// different prop, an STC, a tired engine — and a flight school plans by tail
/// number across a fleet. Weight and balance is per-airframe by definition.
final class AircraftStore: ObservableObject {
    static let shared = AircraftStore()

    private static let key = "AeroMaps_CustomAircraft"
    private static let favouritesKey = "AeroMaps_FavouriteAircraft"

    @Published private(set) var custom: [AircraftProfile] = []
    /// Aircraft the pilot actually flies, pinned above the rest. A GA pilot returns
    /// to the same one or two airframes; the full list is for finding them once.
    @Published private(set) var favourites: Set<String> = []

    private init() { load() }

    func isFavourite(_ id: String) -> Bool { favourites.contains(id) }

    func toggleFavourite(_ id: String) {
        if favourites.contains(id) { favourites.remove(id) } else { favourites.insert(id) }
        UserDefaults.standard.set(Array(favourites), forKey: Self.favouritesKey)
    }

    /// Matches on tail number, type name, category and ident.
    func search(_ query: String, in profiles: [AircraftProfile]) -> [AircraftProfile] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return profiles }
        return profiles.filter {
            $0.name.lowercased().contains(q)
            || $0.registration.lowercased().contains(q)
            || $0.category.lowercased().contains(q)
            || $0.id.lowercased().contains(q)
        }
    }

    private func load() {
        if let saved = UserDefaults.standard.array(forKey: Self.favouritesKey) as? [String] {
            favourites = Set(saved)
        }
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([AircraftProfile].self, from: data) else { return }
        custom = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(custom) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    func save(_ profile: AircraftProfile) {
        var entry = profile
        entry.isCustom = true
        if let index = custom.firstIndex(where: { $0.id == entry.id }) {
            custom[index] = entry
        } else {
            custom.append(entry)
        }
        persist()
    }

    func delete(id: String) {
        custom.removeAll { $0.id == id }
        persist()
    }

    /// A new aircraft seeded from an existing type — far better than a blank form,
    /// since most pilots fly a variant of something already in the list.
    func draft(basedOn template: AircraftProfile) -> AircraftProfile {
        var copy = template
        copy.id = UUID().uuidString
        copy.isCustom = true
        copy.registration = ""
        copy.name = template.name
        return copy
    }
}

// MARK: - Picker

/// Choosing the airframe. Every number the planner produces downstream — climb
/// distances, cruise altitude limits, leg times, fuel and range — comes from this
/// choice, so the picker shows those figures rather than just a name.
struct AircraftPickerView: View {
    @ObservedObject var mapState: MapState
    @ObservedObject private var store = AircraftStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var editing: AircraftProfile?
    @State private var editingIsNew = false

    private var favourites: [AircraftProfile] {
        store.search(query, in: AircraftLibrary.all.filter { store.isFavourite($0.id) })
    }
    private var mine: [AircraftProfile] {
        store.search(query, in: store.custom.filter { !store.isFavourite($0.id) })
    }
    private var types: [AircraftProfile] {
        store.search(query, in: AircraftLibrary.builtIn.filter { !store.isFavourite($0.id) })
    }
    private var hasResults: Bool { !favourites.isEmpty || !mine.isEmpty || !types.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    searchField

                    if !favourites.isEmpty { section("MY AIRCRAFT", profiles: favourites) }
                    if !mine.isEmpty { section(favourites.isEmpty ? "MY AIRCRAFT" : "SAVED", profiles: mine) }
                    if !types.isEmpty { section("AIRCRAFT TYPES", profiles: types) }

                    if !hasResults { noResults }

                    addButton

                    Text("Built-in types are published book figures, rounded for planning. Your own aircraft overrides them with its actual numbers — a different prop, an STC or a tired engine all move these, and the whole plan is computed from them.")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(16)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Aircraft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { profile in
                AircraftEditorView(editing: profile, isNew: editingIsNew) { saved in
                    mapState.selectAircraft(saved)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search tail number or type", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "airplane.slash").font(.title2).foregroundStyle(.secondary)
            Text("No aircraft matching \"\(query)\"")
                .font(.subheadline).fontWeight(.semibold)
            Text("Add it below, starting from whichever type flies closest to yours.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    /// Seeded from a type, because correcting a few numbers beats entering eleven
    /// into a blank form.
    private var addButton: some View {
        Menu {
            ForEach(AircraftLibrary.builtIn) { template in
                Button("Based on \(template.name)") {
                    var draft = store.draft(basedOn: template)
                    if !query.isEmpty, query.rangeOfCharacter(from: .decimalDigits) != nil {
                        draft.registration = query.uppercased()
                    }
                    editing = draft
                    editingIsNew = true
                }
            }
        } label: {
            Label("Add my aircraft", systemImage: "plus.circle.fill")
                .font(.subheadline).fontWeight(.semibold)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func section(_ title: String, profiles: [AircraftProfile]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .heavy)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(profiles) { profile in
                let isSelected = profile.id == mapState.route.aircraftID
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            mapState.selectAircraft(profile)
                        }
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(profile.displayName)
                                        .font(.subheadline).fontWeight(.bold)
                                        .multilineTextAlignment(.leading)
                                    Text(profile.category).font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                }
                            }
                            HStack(spacing: 0) {
                                spec("\(Int(profile.cruiseKTAS))", "kt cruise")
                                spec("\(Int(profile.climbRateFPM))", "fpm climb")
                                spec("\(profile.serviceCeilingFT.formatted())", "ft ceiling")
                                spec(String(format: "%.1f", profile.fuelBurnGPH), "gph")
                                spec("\(Int(profile.rangeNM))", "NM range")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 10) {
                        Button { store.toggleFavourite(profile.id) } label: {
                            Image(systemName: store.isFavourite(profile.id) ? "star.fill" : "star")
                                .foregroundColor(store.isFavourite(profile.id) ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)

                        if profile.isCustom {
                            Button { editing = profile; editingIsNew = false } label: {
                                Image(systemName: "slider.horizontal.3").foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 28)
                }
                .padding(12)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
            }
        }
    }

    private func spec(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.caption2).fontWeight(.bold)
            Text(label).font(.system(size: 8)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
