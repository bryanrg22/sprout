import SwiftUI
import SwiftData

/// Flexible water logging — opened from the Today water card and the Nutrients tab.
/// Three ways to log, so you're never locked into one container:
///   1. Quick-tap your usual bottle (fast path).
///   2. Add any custom ounce amount.
///   3. Edit your bottle's size + name so the quick button matches what you actually drink.
struct WaterLogSheet: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WaterEntry.date, order: .reverse) private var allWater: [WaterEntry]

    @State private var customOz: String = ""
    @State private var bottleOzDraft: String = ""
    @State private var bottleLabelDraft: String = ""

    private var todayEntries: [WaterEntry] {
        allWater.filter { Calendar.current.isDateInToday($0.date) }
    }
    private var todayOz: Double { todayEntries.reduce(0) { $0 + $1.amountOz } }
    private var containerOz: Double { profile.waterContainerOz > 0 ? profile.waterContainerOz : 16.9 }
    private var goalOz: Double { profile.waterTargetOz }
    private var label: String { profile.waterContainerLabel.isEmpty ? "bottle" : profile.waterContainerLabel }
    private var customValue: Double { Double(customOz.trimmingCharacters(in: .whitespaces)) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: "drop.fill").foregroundStyle(Theme.water)
                        Text("\(oz(todayOz)) of \(oz(goalOz)) oz today")
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
                        Label("Add 1 \(label) (\(oz(containerOz)) oz)", systemImage: "plus.circle.fill")
                            .foregroundStyle(Theme.brand)
                    }
                } header: { header("Quick add") }
                .listRowBackground(Theme.card)

                Section {
                    HStack(spacing: Theme.Space.sm) {
                        TextField("Amount", text: $customOz)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(Theme.textPrimary)
                        Text("oz").foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button("Add") {
                            if customValue > 0 { add(customValue); customOz = "" }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(customValue > 0 ? Theme.brand : Theme.textSecondary)
                        .disabled(customValue <= 0)
                    }
                } header: { header("Custom amount") } footer: {
                    footer("Drank a different amount? Add exactly how many ounces.")
                }
                .listRowBackground(Theme.card)

                Section {
                    HStack(spacing: Theme.Space.sm) {
                        TextField("Size", text: $bottleOzDraft)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(Theme.textPrimary)
                        Text("oz").foregroundStyle(Theme.textSecondary)
                    }
                    TextField("Name (e.g. bottle, glass, cup)", text: $bottleLabelDraft)
                        .autocorrectionDisabled()
                        .foregroundStyle(Theme.textPrimary)
                    Button("Save my bottle") {
                        if let v = Double(bottleOzDraft.trimmingCharacters(in: .whitespaces)), v > 0 {
                            profile.waterContainerOz = v
                        }
                        let l = bottleLabelDraft.trimmingCharacters(in: .whitespaces)
                        if !l.isEmpty { profile.waterContainerLabel = l }
                        try? context.save()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.brand)
                } header: { header("Your bottle") } footer: {
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
                bottleOzDraft = oz(containerOz)
                bottleLabelDraft = label
            }
        }
    }

    private func add(_ amountOz: Double) {
        context.insert(WaterEntry(amountOz: amountOz))
        try? context.save()
    }

    /// Whole numbers show as "16", fractional as "16.9".
    private func oz(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(Theme.textSecondary)
    }
    private func footer(_ t: String) -> some View {
        Text(t).font(.caption).foregroundStyle(Theme.textSecondary)
    }
}
