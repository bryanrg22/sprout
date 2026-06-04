import SwiftUI
import SwiftData

/// The "card" you get when you tap a logged food: the full picture — calories, every
/// macro, the serving, any photos, notes — with **Edit**, **Delete**, and **Ask Vita**
/// right there. Editing is deferred to the parent (so the editor opens cleanly after
/// this sheet closes); delete + Ask Vita are handled here.
struct FoodDetailView: View {
    let entry: FoodEntry
    /// Name of the coach for the "Ask …" button (Vita / Bryan's coach).
    var coachName: String = "Vita"
    /// Called when she taps Edit; the parent opens `AddFoodSheet(editing:)` after dismissal.
    var onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AskVitaCenter.self) private var askVita: AskVitaCenter?

    @State private var showDeleteConfirm = false

    /// Cover photo first, then any extras.
    private var photos: [Data] {
        var all: [Data] = []
        if let cover = entry.photoData { all.append(cover) }
        all.append(contentsOf: entry.additionalPhotoData ?? [])
        return all
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    header
                    heroCard
                    if !photos.isEmpty { photoStrip }
                    macroBreakdown
                    if let notes = entry.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        notesCard(notes)
                    }
                    actions
                }
                .padding(.horizontal)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.brand)
                }
            }
            .confirmationDialog("Delete this food?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(displayName) will be removed from this day.")
            }
        }
    }

    // MARK: - Sections

    private var displayName: String { entry.name.isEmpty ? "Untitled food" : entry.name }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Space.sm) {
                mealPill
                // The serving chip is hidden for an AI-combined multi-item meal: there the
                // stored `servingDescription` is just the FIRST item's weight (e.g. the
                // nuggets' "170 g"), not the whole order — showing it reads as a wrong total.
                // The real per-item portions live in the breakdown below instead.
                if !entry.servingDescription.isEmpty && !isMultiItemMeal {
                    detailChip(entry.servingDescription, systemImage: "scalemass")
                }
                if entry.quantity != 1 {
                    detailChip("×\(formattedQuantity)", systemImage: "number")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mealPill: some View {
        Label(entry.mealType.label, systemImage: entry.mealType.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.brand)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.brandSoft, in: Capsule())
    }

    private func detailChip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.card, in: Capsule())
    }

    /// Big calories number + the confidence badge, mirroring the estimate sheet's hero.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(entry.totalCalories.rounded()))")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("kcal")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                if let confidence = entry.confidence {
                    ConfidenceBadge(confidence: confidence)
                }
            }
            if let low = entry.caloriesLow, let high = entry.caloriesHigh, high >= low {
                Text("Estimated range \(Int(low.rounded()))–\(Int(high.rounded())) kcal")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(photos.enumerated()), id: \.offset) { _, data in
                    if let image = UIImage(data: data) {
                        photoTile(image)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// A framed photo thumbnail. Scanned receipts/order screenshots are often mostly
    /// white, which without a frame reads as a raw white rectangle on the dark theme and
    /// a tall one gets its text cropped by a square fill. So the image is fit (not filled)
    /// inside a themed card with a hairline border — it always looks like an intentional
    /// thumbnail in BOTH skins, and the whole shot stays visible (no cut-off text).
    private func photoTile(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 120, height: 120)
            .background(Theme.cardRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
    }

    private var macroBreakdown: some View {
        VStack(spacing: 0) {
            macroRow("Protein", grams: entry.totalProteinG, color: Theme.protein)
            Divider().background(Theme.divider)
            macroRow("Carbs", grams: entry.totalCarbsG, color: Theme.carbs)
            Divider().background(Theme.divider)
            macroRow("Fat", grams: entry.totalFatG, color: Theme.fat)
        }
        .cardElevated()
    }

    private func macroRow(_ label: String, grams: Double, color: Color) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(Int(grams.rounded())) g")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, Theme.Space.sm)
    }

    /// The AI's notes carry the real breakdown of a scanned meal — its one-line summary,
    /// then an "Assumptions: a; b; c" line (each item's portion/scale guess), then any
    /// sanity flag, joined by newlines. We surface that as readable text instead of
    /// leaving it trapped only inside the (often white) order screenshot: the summary
    /// lines stay as sentences and the assumptions become a tidy bulleted list. Falls
    /// back to plain text for a normal single-line note.
    private func notesCard(_ notes: String) -> some View {
        let blocks = notesBlocks(notes)
        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Label(isMultiItemMeal ? "What's in this" : "Notes",
                  systemImage: isMultiItemMeal ? "list.bullet" : "note.text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let line):
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    case .bullets(let title, let items):
                        VStack(alignment: .leading, spacing: 6) {
                            if let title {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                bulletRow(item)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Theme.brand)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.sm) {
            Button {
                onEdit()
                dismiss()
            } label: {
                Label("Edit", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)

            HStack(spacing: Theme.Space.sm) {
                Button {
                    askVita?.ask(vitaTopic)
                    dismiss()
                } label: {
                    Label("Ask \(coachName)", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .foregroundStyle(Theme.brand)
                }
                .buttonStyle(.plain)
                .disabled(askVita == nil)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .foregroundStyle(Theme.warning)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Theme.Space.xs)
    }

    // MARK: - Logic

    /// True for an AI photo/scan estimate that combined several foods into one entry. The
    /// log flow names those `"<first item> + N more"`, so we detect that suffix. Such an
    /// entry's `servingDescription` is only the first item's weight (misleading as a meal
    /// total), and its notes hold the real component breakdown — both handled above.
    private var isMultiItemMeal: Bool {
        entry.source == .photo && Self.multiItemSuffix.firstMatch(
            in: entry.name, range: NSRange(entry.name.startIndex..., in: entry.name)) != nil
    }

    /// Matches the " + N more" tail the photo flow appends for a combined meal.
    private static let multiItemSuffix = try! NSRegularExpression(
        pattern: #"\+\s*\d+\s+more\s*$"#, options: [.caseInsensitive])

    /// One rendered piece of the notes card: either a sentence or a (titled) bullet list.
    private enum NotesBlock {
        case text(String)
        case bullets(title: String?, items: [String])
    }

    /// Splits the stored notes into display blocks. Newline-separated lines become
    /// sentences, except an `"Assumptions: a; b; c"` line, which becomes a "Assumptions"
    /// titled bullet list (one bullet per `;`-separated item) so each item's portion guess
    /// is easy to scan. A plain note with no such line just renders as its line(s).
    private func notesBlocks(_ notes: String) -> [NotesBlock] {
        notes
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                if let range = line.range(of: "Assumptions:") {
                    let body = String(line[range.upperBound...])
                    let items = body
                        .split(separator: ";")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    if !items.isEmpty {
                        return .bullets(title: "Assumptions", items: items)
                    }
                }
                return .text(line)
            }
    }

    private var vitaTopic: AskVitaTopic { askVitaTopic(for: entry) }

    private func delete() {
        context.delete(entry)
        try? context.save()
        dismiss()
    }

    private func g(_ value: Double) -> String { "\(Int(value.rounded()))" }
    private var formattedQuantity: String {
        entry.quantity == entry.quantity.rounded()
            ? String(Int(entry.quantity))
            : String(format: "%.2g", entry.quantity)
    }
}

/// Builds the "Ask Vita about this food" topic — shared by the row's long-press menu
/// and the detail card so the question is identical wherever she asks. EDUCATE-first:
/// it asks how the food fits her goals and for an easy improvement, never to judge it.
func askVitaTopic(for entry: FoodEntry) -> AskVitaTopic {
    func g(_ v: Double) -> String { "\(Int(v.rounded()))" }
    let name = entry.name.isEmpty ? "Untitled food" : entry.name
    let macros = "P \(g(entry.totalProteinG)) · C \(g(entry.totalCarbsG)) · F \(g(entry.totalFatG))"
    return AskVitaTopic(
        name: name,
        icon: entry.mealType.systemImage,
        value: "\(Int(entry.totalCalories.rounded())) kcal · \(macros)",
        question: "I logged \"\(name)\" for \(entry.mealType.label): about "
            + "\(Int(entry.totalCalories.rounded())) kcal, \(g(entry.totalProteinG))g protein, "
            + "\(g(entry.totalCarbsG))g carbs, \(g(entry.totalFatG))g fat. How does this fit my goals, "
            + "and is there an easy way to make it a little better?"
    )
}
