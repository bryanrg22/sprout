import SwiftUI
import SwiftData

/// Flexible water logging — opened from the Today water card and the Nutrients tab.
/// Storage is ALWAYS canonical ounces (`WaterEntry.amountOz`); the display + the typed inputs use
/// the user's chosen unit (`profile.waterUnit`, oz or mL) and convert only at the edges.
///   1. Quick-tap your usual bottle (fast path).
///   2. Add any custom amount (in your chosen unit).
///   3. Edit your bottle's size + name so the quick button matches what you actually drink.
struct WaterLogSheet: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WaterEntry.date, order: .reverse) private var allWater: [WaterEntry]

    /// Typed in the chosen display unit (oz or mL); converted to oz on save.
    @State private var customAmount: String = ""
    @State private var bottleSizeDraft: String = ""
    @State private var bottleLabelDraft: String = ""

    private var todayEntries: [WaterEntry] {
        allWater.filter { Calendar.current.isDateInToday($0.date) }
    }
    private var todayOz: Double { todayEntries.reduce(0) { $0 + $1.amountOz } }
    private var containerOz: Double { profile.waterContainerOz > 0 ? profile.waterContainerOz : 16.9 }
    private var goalOz: Double { profile.waterTargetOz }
    private var label: String { profile.waterContainerLabel.isEmpty ? "bottle" : profile.waterContainerLabel }
    private var unitLabel: String { profile.waterUnitLabel }
    /// The custom-amount field parsed from the chosen unit into canonical oz.
    private var customOz: Double { profile.waterToOz(Double(customAmount.trimmingCharacters(in: .whitespaces)) ?? 0) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Units", selection: Binding(get: { profile.waterUnit },
                                                       set: { profile.waterUnit = $0; try? context.save() })) {
                        ForEach(WaterUnit.allCases) { u in Text(u.label).tag(u) }
                    }
                    .pickerStyle(.segmented)
                } header: { header("Units") }
                .listRowBackground(Theme.card)

                Section {
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: "drop.fill").foregroundStyle(Theme.water)
                        Text("\(profile.waterText(todayOz, goalOz: goalOz)) today")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if let last = todayEntries.first {
                            Button("Undo last") {
                                context.delete(last); try? context.save()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    Button { add(containerOz) } label: {
                        Label("Add 1 \(label) (\(profile.waterAmount(containerOz)))", systemImage: "plus.circle.fill")
                            .foregroundStyle(Theme.brand)
                    }
                } header: { header("Quick add") }
                .listRowBackground(Theme.card)

                Section {
                    HStack(spacing: Theme.Space.sm) {
                        TextField("Amount", text: $customAmount)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(Theme.textPrimary)
                        Text(unitLabel).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button("Add") {
                            if customOz > 0 { add(customOz); customAmount = "" }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(customOz > 0 ? Theme.brand : Theme.textSecondary)
                        .disabled(customOz <= 0)
                    }
                } header: { header("Custom amount") } footer: {
                    footer("Drank a different amount? Add exactly how much in \(unitLabel).")
                }
                .listRowBackground(Theme.card)

                Section {
                    HStack(spacing: Theme.Space.sm) {
                        TextField("Size", text: $bottleSizeDraft)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(Theme.textPrimary)
                        Text(unitLabel).foregroundStyle(Theme.textSecondary)
                    }
                    TextField("Name (e.g. bottle, glass, cup)", text: $bottleLabelDraft)
                        .autocorrectionDisabled()
                        .foregroundStyle(Theme.textPrimary)
                    Button("Save my \(label)") {
                        if let v = Double(bottleSizeDraft.trimmingCharacters(in: .whitespaces)), v > 0 {
                            profile.waterContainerOz = profile.waterToOz(v)
                        }
                        let l = bottleLabelDraft.trimmingCharacters(in: .whitespaces)
                        if !l.isEmpty { profile.waterContainerLabel = l }
                        try? context.save()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.brand)
                } header: { header("Your \(label)") } footer: {
                    footer("Set your usual container so the quick button matches what you actually drink from.")
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .tint(Theme.brand)
            .onAppear {
                bottleSizeDraft = profile.waterAmountValue(containerOz)
                bottleLabelDraft = label
            }
            // When the unit flips, re-read the bottle draft in the new unit and clear the half-typed
            // custom amount so a number typed as oz isn't silently reinterpreted as mL.
            .onChange(of: profile.waterUnitRaw) { _, _ in
                bottleSizeDraft = profile.waterAmountValue(containerOz)
                customAmount = ""
            }
        }
    }

    private func add(_ amountOz: Double) {
        context.insert(WaterEntry(amountOz: amountOz))
        try? context.save()
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(Theme.textSecondary)
    }
    private func footer(_ t: String) -> some View {
        Text(t).font(.caption).foregroundStyle(Theme.textSecondary)
    }
}
