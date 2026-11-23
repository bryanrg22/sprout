import SwiftUI

/// The rows below the macros, in the order the label prints them, drawn the same way
/// wherever they appear (a day on the Nutrients tab, one food's detail card).
///
/// A nutrient no food states reads "not known". It is never drawn as 0, and a total that
/// does not cover every food says how many it covers.
struct NutrientLinesView: View {
    let lines: [NutrientTotals.Line]
    /// Off for a single food, where "from 1 of 1 foods" would be noise.
    var showsCoverage = true
    /// The food card sets this to the quieter tone its macro rows use, so the two lists
    /// on that card read as one.
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    Divider().background(Theme.divider)
                }
                NutrientLineRow(line: line, showsCoverage: showsCoverage, valueColor: valueColor)
            }
        }
    }
}

private struct NutrientLineRow: View {
    let line: NutrientTotals.Line
    let showsCoverage: Bool
    let valueColor: Color

    /// The dot ties a row to the macro it is part of on the label: saturated and trans fat
    /// to fat, fiber and sugars to carbohydrate. The rest stand on their own.
    private var dotColor: Color {
        switch line.nutrient.parent {
        case .fat: return Theme.fat
        case .carbs, .sugars: return Theme.carbs
        case nil: return Theme.textSecondary.opacity(0.55)
        }
    }

    /// "Includes added sugars" sits inside total sugars on the label; it is indented here too.
    private var isSubRow: Bool { line.nutrient.parent == .sugars }

    private var note: String? {
        guard showsCoverage, line.known > 0 else { return nil }
        return line.coverageNote
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.sm) {
            Circle()
                .fill(dotColor)
                .frame(width: isSubRow ? 6 : 8, height: isSubRow ? 6 : 8)
                .padding(.leading, isSubRow ? 15 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.nutrient.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: Theme.Space.sm)
            if let value = line.valueText() {
                Text(value)
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(valueColor)
            } else {
                Text("not known")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsCoverage ? line.spoken : line.spokenValue)
    }
}

/// The Nutrients tab's card for one day: what the day's foods add up to for each label
/// nutrient, with "from N of M foods" under every total that does not cover them all.
struct DayNutrientDetailCard: View {
    let totals: NutrientTotals
    /// Remembered across launches: the card can be folded away by someone who only wants macros.
    @AppStorage("nutrients.detailExpanded") private var expanded = true
    /// The five core rows are always listed; the other six (trans fat, cholesterol, vitamin D,
    /// calcium, iron, potassium) come mostly from a full label and are one tap away.
    @AppStorage("nutrients.detailShowAll") private var showAll = false

    private var coreLines: [NutrientTotals.Line] {
        totals.lines.filter { Nutrient.core.contains($0.nutrient) }
    }
    /// The rows beyond the core that at least one food states.
    private var moreCount: Int { totals.displayed.count - coreLines.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            header
            if expanded {
                if totals.isEmpty {
                    Text("None of this day's foods list these yet. A scanned barcode or label fills them in, a photo or description estimates four of them, and you can type them in when you edit a food.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    NutrientLinesView(lines: showAll ? totals.displayed : coreLines)
                    if moreCount > 0 {
                        Button {
                            showAll.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Text(showAll ? "Show fewer" : "Show \(moreCount) more")
                                Image(systemName: showAll ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.bold))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.brand)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Theme.brandSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Trans fat, cholesterol, vitamin D, calcium, iron and potassium")
                    }
                    Text("A total counts only the foods that list it. Nothing is assumed to be zero.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: expanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: showAll)
    }

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 30, height: 30)
                    .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("More nutrients")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    if !expanded, let summary = collapsedSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More nutrients")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Shows or hides fiber, sugars, sodium and the rest")
    }

    /// Folded away, the card still says what it holds: the first two totals it knows.
    private var collapsedSummary: String? {
        let known = totals.displayed.filter { $0.total != nil }.prefix(2).compactMap { line -> String? in
            line.valueText().map { "\(line.nutrient.label) \($0)" }
        }
        return known.isEmpty ? nil : known.joined(separator: " · ")
    }
}

/// One food's label nutrients, for its detail card. The amounts are for what was logged
/// (per serving × servings), like the calories above them.
struct FoodNutrientDetailCard: View {
    let entry: FoodEntry

    private var totals: NutrientTotals { NutrientTotals([entry]) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Label("More nutrients", systemImage: "list.bullet.rectangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            if totals.isEmpty {
                Text("Fiber, sugars, sodium and the rest aren't known for this food. A scanned barcode or label fills them in, or you can add them in Edit.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                NutrientLinesView(lines: totals.displayed, showsCoverage: false, valueColor: Theme.textSecondary)
                if let footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    /// Says where the numbers came from when that changes how far to trust them.
    private var footnote: String? {
        switch entry.source {
        case .photo:
            return "Estimated with the meal, like its calories. Added sugars and the vitamins and minerals are never estimated."
        default:
            return nil
        }
    }
}
