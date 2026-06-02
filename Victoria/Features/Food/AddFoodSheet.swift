import SwiftUI
import SwiftData

/// A plain-value description of a food entry used to seed `AddFoodSheet`.
///
/// We pass a struct (not a live `FoodEntry`) so the sheet can build the editable
/// form without inserting anything into the context until the user taps Save.
/// Every photo/barcode/search flow converts its result into one of these.
///
/// `Identifiable` so flows can drive `.sheet(item:)` with a freshly-produced draft.
struct FoodDraft: Identifiable {
    let id = UUID()
    var name: String = ""
    var meal: MealType = .snack
    var servingDescription: String = ""
    var quantity: Double = 1
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var caloriesLow: Double? = nil
    var caloriesHigh: Double? = nil
    var source: FoodSource = .manual
    var confidence: EstimateConfidence? = nil
    var barcode: String? = nil
    var notes: String? = nil
    var photoData: Data? = nil
}

/// Reusable editable form for creating a `FoodEntry`.
///
/// Used directly for "Manual entry" and as the final confirmation step for the
/// photo, barcode, and search flows. The estimate is always presented as a
/// friendly starting point the user can edit before saving.
struct AddFoodSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// The day the entry should be logged to (preserves the day's time-of-day-agnostic date).
    let date: Date

    /// When non-nil, Save updates this entry in place instead of inserting a new one.
    /// This lets the same form serve both "confirm a new estimate" and "edit a saved entry".
    private let existing: FoodEntry?

    // Editable fields
    @State private var name: String
    @State private var meal: MealType
    @State private var servingDescription: String
    @State private var quantity: String
    @State private var calories: String
    @State private var proteinG: String
    @State private var carbsG: String
    @State private var fatG: String
    @State private var notes: String

    // Carried through from the draft, not directly edited.
    private let caloriesLow: Double?
    private let caloriesHigh: Double?
    private let source: FoodSource
    private let confidence: EstimateConfidence?
    private let barcode: String?
    private let photoData: Data?

    /// The ORIGINAL estimate, so the quick-scale portion buttons multiply from a stable base
    /// (1× always returns to the estimate) instead of compounding tap-over-tap.
    private let baseCalories: Double
    private let baseProteinG: Double
    private let baseCarbsG: Double
    private let baseFatG: Double
    @State private var portionScale: Double = 1

    /// - Parameters:
    ///   - draft: prefilled values (defaults to an empty manual draft).
    ///   - date: the day to log to (defaults to now).
    ///   - existing: when provided, Save updates this entry in place rather than inserting.
    init(draft: FoodDraft = FoodDraft(), date: Date = .now, existing: FoodEntry? = nil) {
        self.date = date
        self.existing = existing
        _name = State(initialValue: draft.name)
        _meal = State(initialValue: draft.meal)
        _servingDescription = State(initialValue: draft.servingDescription)
        _quantity = State(initialValue: Self.numberString(draft.quantity, fallback: "1"))
        _calories = State(initialValue: Self.numberString(draft.calories))
        _proteinG = State(initialValue: Self.numberString(draft.proteinG))
        _carbsG = State(initialValue: Self.numberString(draft.carbsG))
        _fatG = State(initialValue: Self.numberString(draft.fatG))
        _notes = State(initialValue: draft.notes ?? "")
        caloriesLow = draft.caloriesLow
        caloriesHigh = draft.caloriesHigh
        source = draft.source
        confidence = draft.confidence
        barcode = draft.barcode
        photoData = draft.photoData
        baseCalories = draft.calories
        baseProteinG = draft.proteinG
        baseCarbsG = draft.carbsG
        baseFatG = draft.fatG
    }

    private var caloriesValue: Double { Double(calories) ?? 0 }
    private var quantityValue: Double { max(Double(quantity) ?? 1, 0) }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && caloriesValue > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                if source != .manual {
                    estimateSection
                }

                Section {
                    if let photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .listRowInsets(EdgeInsets())
                            .padding(.vertical, 4)
                    }
                }

                Section("What did you eat?") {
                    TextField("Name", text: $name)
                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    TextField("Serving (e.g. 1 cup)", text: $servingDescription)
                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("1", text: $quantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section("Nutrition") {
                    if source != .manual && baseCalories > 0 {
                        portionRow
                    }
                    nutrientRow("Calories", text: $calories, unit: "kcal", color: Theme.calories)
                    nutrientRow("Protein", text: $proteinG, unit: "g", color: Theme.protein)
                    nutrientRow("Carbs", text: $carbsG, unit: "g", color: Theme.carbs)
                    nutrientRow("Fat", text: $fatG, unit: "g", color: Theme.fat)
                    if quantityValue != 1 && caloriesValue > 0 {
                        HStack {
                            Text("Total (\(formatted(quantityValue))×)")
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(Int((caloriesValue * quantityValue).rounded())) kcal")
                                .font(Theme.number(15))
                                .foregroundStyle(Theme.calories)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Anything to remember?", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    private var estimateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                // Lead with ONE confident number (it updates live as you tap a portion below),
                // with the confidence badge tucked to the side.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                    Text("\(Int(caloriesValue.rounded()))")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                    if let confidence { ConfidenceBadge(confidence: confidence) }
                }

                // Macro chips read at a glance.
                HStack(spacing: Theme.Space.sm) {
                    macroChip("P", Double(proteinG) ?? 0, Theme.protein)
                    macroChip("C", Double(carbsG) ?? 0, Theme.carbs)
                    macroChip("F", Double(fatG) ?? 0, Theme.fat)
                }

                // Uncertainty demoted to a quiet secondary line — "tap to refine", not a scary
                // error bar (this is how Cal AI keeps it feeling confident yet correctable).
                if let low = caloriesLow, let high = caloriesHigh, high >= low {
                    Text("Range \(Int(low.rounded()))–\(Int(high.rounded())) kcal · tap a portion below to refine")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("A starting point — tap a portion below or edit anything that looks off.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Theme.accentSoft)
    }

    private func macroChip(_ label: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(Int(grams.rounded()))g \(label)")
                .font(.caption.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(color.opacity(0.14), in: Capsule())
    }

    /// Quick portion scaling — the single biggest fix for photo-estimate accuracy (portion
    /// size is the #1 error source). Tapping multiplies the WHOLE estimate from its original
    /// base, so "1×" always returns to the estimate and taps never compound.
    private static let portionFactors: [(label: String, value: Double)] = [
        ("½", 0.5), ("¾", 0.75), ("1×", 1), ("1¼", 1.25), ("1½", 1.5), ("2×", 2),
    ]

    private var portionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Portion — tap to adjust the whole estimate")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                ForEach(Self.portionFactors, id: \.value) { factor in
                    let selected = abs(portionScale - factor.value) < 0.001
                    Button {
                        applyScale(factor.value)
                    } label: {
                        Text(factor.label)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(selected ? Theme.accent : Theme.accentSoft, in: Capsule())
                            .foregroundStyle(selected ? Theme.background : Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Rescale the four nutrient fields from the original estimate by `factor`.
    private func applyScale(_ factor: Double) {
        portionScale = factor
        calories = Self.numberString((baseCalories * factor).rounded())
        proteinG = Self.numberString((baseProteinG * factor).rounded())
        carbsG = Self.numberString((baseCarbsG * factor).rounded())
        fatG = Self.numberString((baseFatG * factor).rounded())
    }

    private func nutrientRow(_ label: String, text: Binding<String>, unit: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(Theme.textSecondary)
                .font(.caption)
                .frame(width: 32, alignment: .leading)
        }
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
        let finalQuantity = quantityValue == 0 ? 1 : quantityValue
        let finalName = name.trimmingCharacters(in: .whitespaces)
        let finalServing = servingDescription.trimmingCharacters(in: .whitespaces)

        if let existing {
            // Editing a saved entry: mutate in place, preserving identity/source metadata.
            existing.name = finalName
            existing.mealType = meal
            existing.servingDescription = finalServing
            existing.quantity = finalQuantity
            existing.calories = caloriesValue
            existing.proteinG = Double(proteinG) ?? 0
            existing.carbsG = Double(carbsG) ?? 0
            existing.fatG = Double(fatG) ?? 0
            existing.notes = finalNotes
        } else {
            let entry = FoodEntry(
                date: date,
                mealType: meal,
                name: finalName,
                servingDescription: finalServing,
                quantity: finalQuantity,
                calories: caloriesValue,
                proteinG: Double(proteinG) ?? 0,
                carbsG: Double(carbsG) ?? 0,
                fatG: Double(fatG) ?? 0,
                caloriesLow: caloriesLow,
                caloriesHigh: caloriesHigh,
                source: source,
                confidence: confidence,
                notes: finalNotes,
                barcode: barcode,
                photoData: photoData
            )
            context.insert(entry)
        }
        try? context.save()
        dismiss()
    }

    // MARK: - Formatting

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2g", value)
    }

    /// Renders a number for a text field, hiding the noisy "0" default.
    private static func numberString(_ value: Double, fallback: String = "") -> String {
        guard value != 0 else { return fallback }
        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
