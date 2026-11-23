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
    /// Smart default by time of day (breakfast/lunch/dinner, else snack) — she can change it on the
    /// chip row before saving. Flows that know the meal (a meal section's "+") pass it explicitly.
    var meal: MealType = MealTime.current()
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
    /// Extra photos when several were snapped of the same meal (cover lives in `photoData`).
    var additionalPhotoData: [Data]? = nil
    /// When the coach back-dates a forgotten meal, the day to log it on (nil = today). Only the
    /// Vita `log_food` path reads this; the manual AddFoodSheet sets the entry date itself.
    var loggedDate: Date? = nil
    /// The label nutrients beyond the macros, per serving. A value the source did not state
    /// stays nil (not known) all the way to the saved entry; it is never filled with 0.
    var detail: NutrientDetail = NutrientDetail()
}

extension FoodDraft {
    /// Builds a draft from an Open Food Facts lookup, carrying through a low-confidence
    /// flag + "double-check this" note when the looked-up numbers failed the plausibility
    /// check. Centralised so the barcode, search, and recents-search paths stay identical.
    init(from hit: OpenFoodFactsService.FoodHit, meal: MealType, source: FoodSource) {
        let composed = [hit.brand, hit.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        self.init(
            name: composed.isEmpty ? hit.name : composed,
            meal: meal,
            servingDescription: hit.servingDescription,
            quantity: 1,
            calories: hit.calories,
            proteinG: hit.proteinG,
            carbsG: hit.carbsG,
            fatG: hit.fatG,
            source: source,
            confidence: hit.isSuspicious ? .low : nil,
            barcode: hit.barcode,
            notes: [hit.sanityNote, hit.sodiumNote].compactMap { $0 }.joined(separator: "\n").nilIfEmpty,
            detail: hit.detail
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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
    /// One text field per label nutrient. An EMPTY field is "not known" and is saved as nil;
    /// "0" is a real zero. Never pre-filled with 0.
    @State private var detailText: [Nutrient: String]
    @State private var showDetail: Bool

    // Carried through from the draft, not directly edited.
    private let caloriesLow: Double?
    private let caloriesHigh: Double?
    private let source: FoodSource
    private let confidence: EstimateConfidence?
    private let barcode: String?
    private let photoData: Data?
    private let additionalPhotoData: [Data]?

    /// The ORIGINAL estimate, so the quick-scale portion buttons multiply from a stable base
    /// (1× always returns to the estimate) instead of compounding tap-over-tap.
    private let baseCalories: Double
    private let baseProteinG: Double
    private let baseCarbsG: Double
    private let baseFatG: Double
    private let baseDetail: NutrientDetail
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
        _detailText = State(initialValue: FoodDetailInput.text(for: draft.detail))
        // Open when there is something to see; closed for a blank manual add, where the
        // eleven optional rows would bury the four that matter.
        _showDetail = State(initialValue: !draft.detail.isEmpty)
        caloriesLow = draft.caloriesLow
        caloriesHigh = draft.caloriesHigh
        source = draft.source
        confidence = draft.confidence
        barcode = draft.barcode
        photoData = draft.photoData
        additionalPhotoData = draft.additionalPhotoData
        baseCalories = draft.calories
        baseProteinG = draft.proteinG
        baseCarbsG = draft.carbsG
        baseFatG = draft.fatG
        baseDetail = draft.detail
    }

    /// Opens the form pre-filled from a saved entry; Save updates it in place
    /// (identity, source, photos and timestamps are preserved).
    init(editing entry: FoodEntry) {
        self.init(draft: Self.draft(from: entry), date: entry.date, existing: entry)
    }

    /// Snapshots a saved entry into an editable draft.
    static func draft(from entry: FoodEntry) -> FoodDraft {
        FoodDraft(
            name: entry.name,
            meal: entry.mealType,
            servingDescription: entry.servingDescription,
            quantity: entry.quantity,
            calories: entry.calories,
            proteinG: entry.proteinG,
            carbsG: entry.carbsG,
            fatG: entry.fatG,
            caloriesLow: entry.caloriesLow,
            caloriesHigh: entry.caloriesHigh,
            source: entry.source,
            confidence: entry.confidence,
            barcode: entry.barcode,
            notes: entry.notes,
            photoData: entry.photoData,
            additionalPhotoData: entry.additionalPhotoData,
            detail: entry.detail
        )
    }

    private var caloriesValue: Double { Double(calories) ?? 0 }
    private var quantityValue: Double { max(Double(quantity) ?? 1, 0) }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && caloriesValue > 0
            && !FoodDetailInput.hasInvalid(detailText)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
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
                        .accessibilityIdentifier(AccessibilityID.AddFood.name)
                    mealSelectorRow
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
                        .accessibilityIdentifier(AccessibilityID.AddFood.calories)
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

                detailSection

                Section("Notes") {
                    TextField("Anything to remember?", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            #if DEBUG
            // `--demo-scroll-label`: bring the label rows into view for a screenshot run,
            // which cannot scroll.
            .task {
                guard CommandLine.arguments.contains("--demo-scroll-label") else { return }
                try? await Task.sleep(nanoseconds: 700_000_000)
                scroller.scrollTo(Nutrient.potassium.id, anchor: .bottom)
            }
            #endif
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                        .accessibilityIdentifier(AccessibilityID.AddFood.save)
                }
            }
        }
    }

    /// Prominent, always-visible meal picker. The old inline `Picker` row was easy to miss, so a
    /// snack could silently land in "Dinner" with no obvious way to change it. These chips make the
    /// choice — and that it's changeable — unmissable; a meal is always selected so nothing is unfiled.
    private var mealSelectorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meal").font(.caption).foregroundStyle(Theme.textSecondary)
            MealChipsRow(selection: $meal)
        }
        .padding(.vertical, 4)
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
    private var portionFactors: [(label: String, value: Double)] {
        // A SCANNED packaged item carries PER-SERVING values, so offer whole servings — "how
        // many did you have?" — reaching a full multi-serving bag in one tap (the Gushers case).
        // A photo estimate is the whole plate, so those stay fractions of the estimate.
        if source == .barcode {
            return [("½", 0.5), ("1", 1), ("2", 2), ("3", 3), ("4", 4)]
        }
        return [("½", 0.5), ("¾", 0.75), ("1×", 1), ("1¼", 1.25), ("1½", 1.5), ("2×", 2)]
    }

    private var portionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source == .barcode ? "How many servings did you have?"
                                    : "Portion — tap to adjust the whole estimate")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                ForEach(portionFactors, id: \.value) { factor in
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
        // The label nutrients scale with the portion too; one that was not known stays blank.
        detailText = FoodDetailInput.text(for: baseDetail.scaled(by: factor))
    }

    // MARK: - More from the label

    private var knownDetailCount: Int {
        Nutrient.allCases.filter { FoodDetailInput.value(detailText[$0] ?? "", for: $0) != nil }.count
    }

    /// Fiber, sugars, sodium and the rest of the Nutrition Facts panel, per serving. Every row
    /// is optional: a blank row is saved as "not known", never as zero.
    private var detailSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showDetail) {
                ForEach(Nutrient.allCases) { nutrient in
                    detailRow(nutrient).id(nutrient.id)
                }
            } label: {
                HStack {
                    Text("More from the label")
                    Spacer()
                    Text(knownDetailCount == 0 ? "Optional" : "\(knownDetailCount) of \(Nutrient.allCases.count)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } footer: {
            if FoodDetailInput.hasInvalid(detailText) {
                Text("The highlighted row isn't an amount that can be saved. Fix it or clear it to save.")
                    .foregroundStyle(Theme.warning)
            } else if showDetail {
                Text(source == .photo
                     ? "Fiber, sugars, saturated fat and sodium are estimated with the meal. The rest come only from a label. Leave a row blank if you don't know it: blank is saved as not known, not as 0."
                     : "Per serving. Leave a row blank if you don't know it: blank is saved as not known, not as 0.")
            }
        }
    }

    private func detailRow(_ nutrient: Nutrient) -> some View {
        let text = Binding<String>(
            get: { detailText[nutrient] ?? "" },
            set: { detailText[nutrient] = $0 })
        let invalid = FoodDetailInput.isInvalid(text.wrappedValue, for: nutrient)
        return HStack {
            Text(nutrient.label)
                // Sub-rows sit under their parent the way the label indents them.
                .padding(.leading, nutrient.parent == .sugars ? 14 : 0)
                .foregroundStyle(invalid ? Theme.warning : Theme.textPrimary)
            Spacer()
            TextField("not known", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
                .accessibilityLabel("\(nutrient.label), \(nutrient.unit.rawValue), optional")
            Text(nutrient.unit.rawValue)
                .foregroundStyle(Theme.textSecondary)
                .font(.caption)
                .frame(width: 32, alignment: .leading)
        }
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
        let finalDetail = FoodDetailInput.detail(from: detailText)

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
            existing.detail = finalDetail
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
                photoData: photoData,
                additionalPhotoData: additionalPhotoData,
                detail: finalDetail
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

/// A row of tappable meal chips (Breakfast · Lunch · Dinner · Snack · Other), the selected one
/// filled. Each chip is sized to its own text with consistent padding (so "Breakfast" isn't cramped
/// the way equal-width made it) and the row wraps to a second line if they don't all fit. Shared by
/// the add-food sheet and the recents quick-log so the "which meal?" choice looks the same everywhere.
struct MealChipsRow: View {
    @Binding var selection: MealType
    var body: some View {
        MealFlowLayout(spacing: 8) {
            ForEach(MealType.allCases) { m in
                let selected = m == selection
                Button { selection = m } label: {
                    Text(m.label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(selected ? Theme.brand : Theme.brandSoft, in: Capsule())
                        .foregroundStyle(selected ? Color.white : Theme.textPrimary)
                        .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.brand.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A minimal wrap layout (chips flow left-to-right, drop to the next line when they'd overflow).
/// Mirrors the `FlowLayout`/`ChecklistFlowLayout` used elsewhere; kept local to the food flow.
fileprivate struct MealFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + bounds.width && x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
