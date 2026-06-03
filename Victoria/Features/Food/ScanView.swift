import SwiftUI
import VisionKit

/// One unified "Scan" that auto-detects whether the camera is pointed at a
/// **barcode** or a **Nutrition Facts** label, in a single camera session.
///
/// Disambiguation is **barcode-first**: a `DataScannerViewController` recognizes
/// both `.barcode` and `.text` at once, and the moment a barcode appears in frame
/// we treat the scan as a barcode (look it up on Open Food Facts → `AddFoodSheet`
/// with source `.barcode`, which shows the "how many servings?" prompt). Only when
/// NO barcode is present do we fall to the label path: we keep reading text, and
/// once enough nutrition text is detected to parse confidently we surface a
/// "Use this label" affordance so a stray word never triggers a bogus draft.
///
/// Replaces the two former single-purpose views (`BarcodeScanView` +
/// `LabelScanView`); their lookup and parsing logic is ported here unchanged.
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss

    /// The day to log the resulting entry to.
    let date: Date
    /// When set (she tapped a specific meal), the result lands in this meal.
    var preferredMeal: MealType? = nil

    @State private var manualCode: String = ""
    @State private var phase: Phase = .idle
    @State private var draft: FoodDraft?
    @State private var message: String?
    /// The latest confident label parse, held back until she taps "Use this label"
    /// (so a stray word doesn't auto-fire a label draft, and a barcode can still win).
    @State private var pendingLabel: FoodDraft?

    private enum Phase: Equatable {
        case idle          // scanning / waiting for input
        case looking       // barcode network lookup in flight
    }

    /// DataScanner needs a supported device, camera permission, and availability.
    private var scannerUsable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.background)
                .navigationTitle("Scan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(phase == .looking)
                    }
                }
        }
        .sheet(item: $draft, onDismiss: { dismiss() }) { draft in
            AddFoodSheet(draft: draft, date: date)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .looking:
            lookingView
        case .idle:
            if scannerUsable {
                scannerView
            } else {
                manualView
            }
        }
    }

    // MARK: - Scanner

    private var scannerView: some View {
        VStack(spacing: 0) {
            ScanRepresentable(
                onBarcode: { code in lookup(code) },
                onText: { lines in handleText(lines) }
            )
            .overlay(alignment: .top) {
                Text("Point at a barcode or nutrition label")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 16)
            }
            // Once we've read enough of a Nutrition Facts panel to parse it, offer a
            // tap to use it. Held behind a button so a stray word can't trigger a
            // label draft, and so a barcode that appears later still takes priority.
            .overlay(alignment: .bottom) {
                if pendingLabel != nil {
                    Button {
                        draft = pendingLabel
                    } label: {
                        Label("Use this label", systemImage: "doc.text.viewfinder")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.primary)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }

            scannerFooter
        }
    }

    private var scannerFooter: some View {
        VStack(spacing: 8) {
            Text("Hold steady — point at a barcode, or a Nutrition Facts panel to read calories and macros.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Text("Can't scan it? Type the barcode number below.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            manualField
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
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
                Text("Enter the barcode")
                    .font(.title3.weight(.semibold))
                Text("Live scanning isn't available here, but you can type the number printed under the barcode — or add the item yourself.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                manualField
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Button {
                    addManually()
                } label: {
                    Label("Add it myself instead", systemImage: "square.and.pencil")
                }
                .padding(.top, 4)
            }
            .padding()
        }
    }

    private var manualField: some View {
        HStack {
            TextField("e.g. 0123456789012", text: $manualCode)
                .keyboardType(.numberPad)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button("Look up") {
                let trimmed = manualCode.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { lookup(trimmed) }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Looking up

    private var lookingView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Looking it up…")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logic

    /// Barcode path: look the code up on Open Food Facts, then present the confirm
    /// sheet (source `.barcode`, so the servings prompt appears). A barcode always
    /// wins over any in-progress label read — once we're here the session is stopped.
    private func lookup(_ code: String) {
        guard phase != .looking else { return }
        phase = .looking
        message = nil
        pendingLabel = nil
        Task {
            do {
                let product = try await OpenFoodFactsService.product(barcode: code)
                await MainActor.run {
                    if let product {
                        draft = makeDraft(from: product)
                    } else {
                        phase = .idle
                        message = "We couldn't find that one. You can type the code again or add it yourself."
                    }
                }
            } catch {
                await MainActor.run {
                    phase = .idle
                    message = "Lookup didn't work just now. Check your connection, or add it yourself."
                }
            }
        }
    }

    /// Label path: called with the latest accumulated text lines while scanning.
    /// We try to parse a full panel; the first time we get a confident parse (at
    /// least calories) we stage it behind the "Use this label" button rather than
    /// presenting immediately. Until then we keep scanning silently.
    private func handleText(_ lines: [String]) {
        guard draft == nil, pendingLabel == nil, phase == .idle else { return }
        if var parsed = Self.parseNutritionLabel(lines) {
            parsed.meal = preferredMeal ?? parsed.meal
            pendingLabel = parsed
        }
    }

    /// Open the confirm sheet with an empty manual draft so she can type it in.
    private func addManually() {
        let trimmed = manualCode.trimmingCharacters(in: .whitespaces)
        draft = FoodDraft(
            meal: preferredMeal ?? MealTime.current(),
            source: .manual,
            barcode: trimmed.isEmpty ? nil : trimmed
        )
    }

    private func makeDraft(from p: OFFProduct) -> FoodDraft {
        FoodDraft(from: p, meal: preferredMeal ?? MealTime.current(), source: .barcode)
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

// MARK: - DataScanner wrapper (barcode + text)

/// Wraps `DataScannerViewController` recognizing **both** 1D grocery barcodes and
/// text in one session. Disambiguation is **barcode-first**: any frame containing a
/// barcode fires `onBarcode` once and stops the session; otherwise the accumulated
/// text transcripts are streamed via `onText` for label parsing. A label's rows fill
/// in over several frames, so we accumulate distinct lines rather than only
/// forwarding the latest frame. Callers must check availability before presenting.
private struct ScanRepresentable: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void
    let onText: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce]), .text()],
            qualityLevel: .balanced,
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

    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode, onText: onText) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onBarcode: (String) -> Void
        let onText: ([String]) -> Void
        /// Set once a barcode has fired, so we never double-handle or keep streaming
        /// text after we've committed to the barcode path.
        private var handled = false
        /// All distinct text transcripts seen so far, in first-seen order. A panel's
        /// rows often appear across consecutive frames, so we accumulate rather than
        /// only forwarding the latest frame's items.
        private var seen: [String] = []
        private var seenSet: Set<String> = []

        init(onBarcode: @escaping (String) -> Void, onText: @escaping ([String]) -> Void) {
            self.onBarcode = onBarcode
            self.onText = onText
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems, in: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems, in: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item], in: dataScanner)
        }

        /// Barcode-first: if any item in the batch is a barcode, commit to the barcode
        /// path immediately (stop scanning, fire once). Otherwise ingest text lines.
        private func handle(_ items: [RecognizedItem], in scanner: DataScannerViewController) {
            guard !handled else { return }
            for case let .barcode(barcode) in items {
                if let value = barcode.payloadStringValue, !value.isEmpty {
                    handled = true
                    scanner.stopScanning()
                    onBarcode(value)
                    return
                }
            }
            ingestText(items)
        }

        private func ingestText(_ items: [RecognizedItem]) {
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
    ScanView(date: .now)
}
