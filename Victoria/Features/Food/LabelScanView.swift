import SwiftUI
import VisionKit

/// Nutrition-label logging: point the camera at a packaged food's **Nutrition
/// Facts** panel, OCR the text, parse calories + macros, then confirm in
/// `AddFoodSheet`. This is the LABEL path for foods that lack a usable barcode
/// (the barcode path lives in `BarcodeScanView`).
///
/// Mirrors `BarcodeScanView`: a `DataScannerViewController` wrapped in a
/// `UIViewControllerRepresentable`, gated by device availability, with a warm
/// manual fallback for devices without a usable camera (e.g. the Simulator).
struct LabelScanView: View {
    @Environment(\.dismiss) private var dismiss

    /// The day to log the resulting entry to.
    let date: Date
    /// When set (she tapped a specific meal), the result lands in this meal.
    var preferredMeal: MealType? = nil

    @State private var draft: FoodDraft?

    /// DataScanner needs a supported device, camera permission, and availability.
    private var scannerUsable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.background)
                .navigationTitle("Scan Label")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .sheet(item: $draft, onDismiss: { dismiss() }) { draft in
            AddFoodSheet(draft: draft, date: date)
        }
    }

    @ViewBuilder
    private var content: some View {
        if scannerUsable {
            scannerView
        } else {
            manualView
        }
    }

    // MARK: - Scanner

    private var scannerView: some View {
        VStack(spacing: 0) {
            LabelTextScannerRepresentable { lines in
                handle(lines)
            }
            .overlay(alignment: .top) {
                Text("Point at the Nutrition Facts panel")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 16)
            }

            scannerFooter
        }
    }

    private var scannerFooter: some View {
        VStack(spacing: 8) {
            Text("Hold steady — we'll read the calories and macros automatically.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                addManually()
            } label: {
                Label("Add it myself instead", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    // MARK: - Manual fallback (Simulator / no camera)

    private var manualView: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
                Text("Scan a Nutrition Facts label")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Live scanning isn't available here, but you can type the values from the label yourself.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    addManually()
                } label: {
                    Label("Enter the values", systemImage: "square.and.pencil")
                }
                .buttonStyle(.primary)
                .padding(.top, 4)
            }
            .padding()
        }
    }

    // MARK: - Logic

    /// Called with the latest batch of recognized text lines. We try to parse a
    /// full panel; the first time we get a confident parse (at least calories),
    /// we present the confirm sheet. Until then we keep scanning silently.
    private func handle(_ lines: [String]) {
        guard draft == nil else { return }
        if var parsed = Self.parseNutritionLabel(lines) {
            parsed.meal = preferredMeal ?? parsed.meal
            draft = parsed
        }
    }

    /// Open the confirm sheet with an empty manual draft so she can type it in.
    private func addManually() {
        draft = FoodDraft(
            meal: preferredMeal ?? MealTime.current(),
            source: .manual
        )
    }

    // MARK: - Parsing

    /// Parses a standard US **Nutrition Facts** panel from OCR'd text lines.
    ///
    /// Tolerant of common OCR noise (e.g. letter `O`/`o`/`Q` read for `0`, `l`/`I`
    /// for `1`, `S` for `5`, stray spaces). Takes the **first plausible match** for
    /// each nutrient and requires at least a calories value to be considered a
    /// success — so a stray "protein" word alone won't produce a bogus draft.
    ///
    /// Returns `nil` when calories can't be found, signalling "keep scanning".
    static func parseNutritionLabel(_ rawLines: [String]) -> FoodDraft? {
        // Normalise: collapse whitespace, drop empties. Keep original-ish text for
        // brand detection; lowercase copies are used for keyword matching.
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        // Search across the whole joined panel too, because OCR frequently splits a
        // label like "Calories 230" across columns or merges several rows onto one
        // line. We try per-line first (more precise) then fall back to the blob.
        let blob = lines.joined(separator: "\n")

        guard let calories = firstCalories(in: lines, blob: blob) else { return nil }

        let protein = firstGrams(of: ["protein"], in: lines, blob: blob)
        // "Total Carbohydrate" / "Carbs" — match the longer phrase first.
        let carbs = firstGrams(of: ["total carbohydrate", "carbohydrate", "total carb", "carbs", "carb"],
                               in: lines, blob: blob)
        // "Total Fat" / "Fat" — but NOT "saturated/trans/unsaturated" fat lines,
        // which are sub-rows, not the total we want for a macro.
        let fat = firstFat(in: lines, blob: blob)

        let serving = firstServing(in: lines)
        let brand = firstBrand(in: lines)

        // Vet the OCR'd numbers: fill calories from macros if the calorie line was
        // missed, and flag the entry low-confidence with a note if they're implausible
        // (e.g. a "% Daily Value" got grabbed as grams).
        let sanity = NutritionSanity.check(
            calories: calories, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)

        return FoodDraft(
            name: brand ?? "Scanned label",
            meal: MealTime.current(),
            servingDescription: serving ?? "",
            quantity: 1,
            calories: sanity.calories,
            proteinG: sanity.protein,
            carbsG: sanity.carbs,
            fatG: sanity.fat,
            // A label is a precise, packaged source — NOT an AI estimate. Use the
            // same source the barcode path uses so the confirm sheet treats it as
            // exact (no "estimated range" framing) — unless sanity flagged it.
            source: .barcode,
            confidence: sanity.isSuspicious ? .low : nil,
            notes: sanity.reason
        )
    }

    // MARK: Parsing helpers

    /// OCR glyph → digit confusions. We only ever apply these to a token that
    /// ALREADY contains at least one real digit (see `repairNumericToken`), so the
    /// fix can recover "23O"→"230" or "4Sg"→"45g" without mangling normal words.
    ///
    /// `g` is deliberately absent: it's the gram unit printed right after the number
    /// on every macro line. Mapping `g`→`9` would turn "8g" into "89".
    private static let ocrDigitSwaps: [Character: Character] = [
        "o": "0", "q": "0", "d": "0",
        "l": "1", "i": "1", "|": "1",
        "s": "5",
        "b": "8",
    ]

    /// Repairs OCR letter→digit confusions inside a single token, but ONLY when the
    /// token already has a digit (so a pure word like "serving" is never turned into
    /// a number). Trailing unit/percent characters (g, %, etc.) are preserved.
    private static func repairNumericToken(_ token: String) -> String {
        let lower = token.lowercased()
        guard lower.contains(where: \.isNumber) else { return lower }
        return String(lower.map { ocrDigitSwaps[$0] ?? $0 })
    }

    /// Parses the first plausible number out of a fragment. Splits into whitespace
    /// tokens, finds the first token that contains a digit, repairs OCR confusions
    /// within just that token, and reads the leading number. Handles an optional
    /// decimal (e.g. "0.5g"). Returns nil if no digit-bearing token is found.
    private static func number(in fragment: String) -> Double? {
        for raw in fragment.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            let token = repairNumericToken(String(raw))
            guard token.contains(where: \.isNumber) else { continue }
            if let range = token.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) {
                return Double(token[range])
            }
        }
        return nil
    }

    /// Finds calories: a line/blob containing "calories" followed by a number.
    /// Allows noise between the word and the value ("Calories  230", "Calories 230kcal").
    private static func firstCalories(in lines: [String], blob: String) -> Double? {
        // Per-line: take the number that appears AFTER the word "calories".
        // We match and extract on the SAME lowercased string so all indices stay
        // valid (digits are identical in either case).
        for line in lines {
            let lower = line.lowercased()
            guard let r = lower.range(of: "calories") else { continue }
            let after = String(lower[r.upperBound...])
            if let n = number(in: after), isPlausibleCalories(n) {
                return n.rounded()
            }
            // Sometimes the number sits BEFORE the word on the same line.
            let before = String(lower[..<r.lowerBound])
            if let n = number(in: before), isPlausibleCalories(n) {
                return n.rounded()
            }
        }
        // Blob fallback: first number after the first "calories" anywhere.
        let lowerBlob = blob.lowercased()
        if let r = lowerBlob.range(of: "calories") {
            let after = String(lowerBlob[r.upperBound...])
            if let n = number(in: after), isPlausibleCalories(n) {
                return n.rounded()
            }
        }
        return nil
    }

    /// A sane per-serving calorie range — guards against grabbing a "% Daily Value"
    /// or a serving-weight number by mistake.
    private static func isPlausibleCalories(_ n: Double) -> Bool {
        n >= 1 && n <= 9999
    }

    /// Finds the first "<keyword> … <number> g" match for a macro. Keywords are
    /// tried in order (longest/most-specific first by caller).
    private static func firstGrams(of keywords: [String], in lines: [String], blob: String) -> Double? {
        for keyword in keywords {
            if let v = gramsAfter(keyword, in: lines) { return v }
        }
        // Blob fallback for the first keyword only (least ambiguous phrasing).
        if let first = keywords.first, let v = gramsAfter(first, in: [blob]) { return v }
        return nil
    }

    /// Grams value appearing after `keyword` on any line. Prefers a number that's
    /// immediately followed by a "g" unit; otherwise takes the first number after
    /// the keyword (labels often print "Protein 5g" or "Protein 5 g").
    private static func gramsAfter(_ keyword: String, in lines: [String]) -> Double? {
        for line in lines {
            let lower = line.lowercased()
            guard let r = lower.range(of: keyword) else { continue }
            // Skip sub-nutrient rows that merely CONTAIN the keyword as a suffix
            // handled by the caller (e.g. fat). Here we just read after the match.
            // Extract from `lower` (the string we matched on) so indices stay valid;
            // case doesn't matter for number/unit parsing.
            let after = String(lower[r.upperBound...])
            // Prefer "<num>g" so we don't grab a trailing % daily value.
            if let v = gramsWithUnit(after) { return v }
            if let v = number(in: after), isPlausibleGrams(v) { return v }
        }
        return nil
    }

    /// Matches a number directly followed by a gram unit, e.g. "230g", "45g", "0.5 g".
    /// Repairs OCR confusions token-by-token (so "4sg" → "45g") before testing the
    /// "<number> g" shape, which lets us prefer the grams value over a trailing
    /// "% Daily Value" number on the same row.
    private static func gramsWithUnit(_ fragment: String) -> Double? {
        // Repair each token that holds a digit, then re-join so "45 g" and "45g"
        // both present a clean "<num>g" run to the regex.
        let repaired = fragment
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map { repairNumericToken(String($0)) }
            .joined(separator: " ")
        guard let range = repaired.range(
            of: #"\d+(?:\.\d+)?\s*g\b"#,
            options: .regularExpression
        ) else { return nil }
        let match = String(repaired[range])
        guard let v = number(in: match), isPlausibleGrams(v) else { return nil }
        return v
    }

    /// A sane per-serving macro range in grams.
    private static func isPlausibleGrams(_ n: Double) -> Bool {
        n >= 0 && n <= 999
    }

    /// Total Fat, excluding the saturated/trans/unsaturated sub-rows.
    private static func firstFat(in lines: [String], blob: String) -> Double? {
        // Prefer an explicit "total fat" line.
        if let v = gramsAfter("total fat", in: lines) { return v }
        // Otherwise a "fat" line that isn't a sub-type.
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("fat") else { continue }
            if lower.contains("saturated") || lower.contains("trans") || lower.contains("unsaturated") || lower.contains("poly") || lower.contains("mono") {
                continue
            }
            if let r = lower.range(of: "fat") {
                let after = String(lower[r.upperBound...])
                if let v = gramsWithUnit(after) { return v }
                if let v = number(in: after), isPlausibleGrams(v) { return v }
            }
        }
        // Blob fallback.
        if let v = gramsAfter("total fat", in: [blob]) { return v }
        return nil
    }

    /// Optional serving-size line, e.g. "Serving size 1 cup (240ml)". We match
    /// case-insensitively directly on `line` so the returned range indexes into the
    /// original string and the value keeps its original casing ("1 cup").
    private static func firstServing(in lines: [String]) -> String? {
        for line in lines {
            guard let r = line.range(of: "serving size", options: .caseInsensitive) else { continue }
            let value = String(line[r.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " :\t"))
            if !value.isEmpty { return value }
        }
        // Some labels print "Serving Size" and the value on the next line; also
        // accept a bare "Serving" prefix.
        for line in lines {
            guard let r = line.range(of: "serving", options: .caseInsensitive) else { continue }
            let value = String(line[r.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " :\t"))
            // Avoid "Servings Per Container" being treated as a description.
            if value.lowercased().hasPrefix("per") || value.lowercased().hasPrefix("s per") { continue }
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Best-effort brand/product name: the first line that looks like words (not a
    /// nutrition keyword, not mostly digits). Falls back to nil → "Scanned label".
    private static func firstBrand(in lines: [String]) -> String? {
        let blocked = ["nutrition", "facts", "serving", "servings", "calories",
                       "amount per", "total fat", "saturated", "trans", "cholesterol",
                       "sodium", "carbohydrate", "fiber", "sugars", "protein",
                       "daily value", "% dv", "ingredients", "vitamin", "calcium",
                       "iron", "potassium"]
        for line in lines {
            let lower = line.lowercased()
            if blocked.contains(where: { lower.contains($0) }) { continue }
            let letters = line.filter { $0.isLetter }.count
            let digits = line.filter { $0.isNumber }.count
            // Needs real words and not be a number row; keep it short-ish.
            guard letters >= 3, letters > digits, line.count <= 40 else { continue }
            return line.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}

// MARK: - DataScanner wrapper (text mode)

/// Wraps `DataScannerViewController` in **text** mode and streams the currently
/// recognized text lines to the caller. Unlike the barcode wrapper (which fires
/// once on the first stable code), a label has many lines that fill in over a few
/// frames, so we keep reporting the accumulated set until the caller is satisfied.
/// Callers must check availability before presenting.
private struct LabelTextScannerRepresentable: UIViewControllerRepresentable {
    let onText: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        try? uiViewController.startScanning()
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onText: ([String]) -> Void
        /// All distinct transcripts seen so far, in first-seen order. A panel's
        /// rows often appear across consecutive frames, so we accumulate rather
        /// than only forwarding the latest frame's items.
        private var seen: [String] = []
        private var seenSet: Set<String> = []

        init(onText: @escaping ([String]) -> Void) { self.onText = onText }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            ingest(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            ingest(allItems)
        }

        private func ingest(_ items: [RecognizedItem]) {
            var changed = false
            for case let .text(text) in items {
                let value = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, !seenSet.contains(value) else { continue }
                seenSet.insert(value)
                seen.append(value)
                changed = true
            }
            if changed {
                onText(seen)
            }
        }
    }
}

#Preview {
    LabelScanView(date: .now)
}
