import SwiftUI

/// Form for a pilot's own aircraft.
///
/// Seeded from an existing type rather than starting blank: most people fly a
/// variant of something already in the list, so the useful act is "start from a
/// 172 and correct the numbers", not "enter eleven figures from scratch".
struct AircraftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AircraftStore.shared

    @State private var draft: AircraftProfile
    private let isNew: Bool
    var onSave: ((AircraftProfile) -> Void)?

    init(editing profile: AircraftProfile, isNew: Bool, onSave: ((AircraftProfile) -> Void)? = nil) {
        _draft = State(initialValue: profile)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    LabeledContent("Registration") {
                        TextField("N12345", text: $draft.registration)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Type") {
                        TextField("Cessna 172S", text: $draft.name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Category") {
                        TextField("Single-engine piston", text: $draft.category)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    numberRow("Cruise speed", value: $draft.cruiseKTAS, unit: "kt", range: 40...600, step: 5)
                    numberRow("Climb rate", value: $draft.climbRateFPM, unit: "fpm", range: 100...4000, step: 25)
                    numberRow("Climb speed", value: $draft.climbKTAS, unit: "kt", range: 40...300, step: 5)
                    numberRow("Descent rate", value: $draft.descentRateFPM, unit: "fpm", range: 100...4000, step: 25)
                    numberRow("Descent speed", value: $draft.descentKTAS, unit: "kt", range: 40...400, step: 5)
                } header: {
                    Text("Performance")
                } footer: {
                    Text("These drive the vertical profile: where the route tops of climb and starts down, and how long each leg takes.")
                }

                Section {
                    numberRow("Fuel burn", value: $draft.fuelBurnGPH, unit: "gph", range: 1...200, step: 0.5, decimals: 1)
                    numberRow("Usable fuel", value: $draft.usableFuelGal, unit: "gal", range: 5...500, step: 1)
                    LabeledContent("Still-air range") {
                        Text("\(Int(draft.rangeNM)) NM · \(String(format: "%.1f", draft.enduranceHours)) h")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Fuel")
                } footer: {
                    Text("Used to decide whether a route needs a fuel stop, and to check the 30-minute day-VFR reserve. Range shown is still air with no reserve.")
                }

                Section {
                    intRow("Service ceiling", value: $draft.serviceCeilingFT, unit: "ft", range: 3000...45000, step: 500)
                    numberRow("Demonstrated crosswind", value: $draft.demonstratedCrosswindKT, unit: "kt", range: 5...40, step: 1)
                    intRow("Seats", value: $draft.seats, unit: "", range: 1...19, step: 1)
                } header: {
                    Text("Limits")
                } footer: {
                    Text("Cruise altitude is capped at the lower of the service ceiling and 17,500 ft, the VFR maximum. The crosswind figure is what the runway briefing warns against.")
                }

                if draft.isCustom && !isNew {
                    Section {
                        Button("Delete Aircraft", role: .destructive) {
                            store.delete(id: draft.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Aircraft" : "Edit Aircraft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
                            draft.name = draft.registration.isEmpty ? "Custom aircraft" : draft.registration
                        }
                        store.save(draft)
                        onSave?(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, unit: String,
                           range: ClosedRange<Double>, step: Double, decimals: Int = 0) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain).foregroundStyle(.tint)
            Text(String(format: "%.\(decimals)f", value.wrappedValue))
                .monospacedDigit().frame(minWidth: 52, alignment: .trailing)
            Text(unit).foregroundStyle(.secondary).font(.caption)
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain).foregroundStyle(.tint)
        }
    }

    private func intRow(_ title: String, value: Binding<Int>, unit: String,
                        range: ClosedRange<Int>, step: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain).foregroundStyle(.tint)
            Text(value.wrappedValue.formatted())
                .monospacedDigit().frame(minWidth: 52, alignment: .trailing)
            if !unit.isEmpty { Text(unit).foregroundStyle(.secondary).font(.caption) }
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain).foregroundStyle(.tint)
        }
    }
}
