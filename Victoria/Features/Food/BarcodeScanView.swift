import SwiftUI
import VisionKit

/// Barcode-based logging: scan an EAN/UPC barcode (or type one on devices
/// without a usable scanner, e.g. the Simulator), look it up on Open Food Facts,
/// then confirm in `AddFoodSheet`.
struct BarcodeScanView: View {
    @Environment(\.dismiss) private var dismiss

    /// The day to log the resulting entry to.
    let date: Date
    /// When set (she tapped a specific meal), the result lands in this meal.
    var preferredMeal: MealType? = nil

    @State private var manualCode: String = ""
    @State private var phase: Phase = .idle
    @State private var draft: FoodDraft?
    @State private var message: String?

    private enum Phase: Equatable {
        case idle          // scanning / waiting for input
        case looking       // network lookup in flight
    }

    /// DataScanner needs a supported device, camera permission, and availability.
    private var scannerUsable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.background)
                .navigationTitle("Scan Barcode")
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
            BarcodeScannerRepresentable { code in
                lookup(code)
            }
            .overlay(alignment: .top) {
                Text("Point your camera at a barcode")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 16)
            }

            manualEntryFooter
        }
    }

    private var manualEntryFooter: some View {
        VStack(spacing: 10) {
            Text("Can't scan it? Type the number below.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            manualField
        }
        .padding()
        .background(Theme.background)
    }

    // MARK: - Manual fallback

    private var manualView: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
                Text("Enter the barcode")
                    .font(.title3.weight(.semibold))
                Text("Live scanning isn't available here, but you can type the number printed under the barcode.")
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

    private func lookup(_ code: String) {
        guard phase != .looking else { return }
        phase = .looking
        message = nil
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
}

// MARK: - DataScanner wrapper

/// Wraps `DataScannerViewController` to recognize 1D grocery barcodes and report
/// the first stable result. Callers must check availability before presenting.
private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
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

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var handled = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(addedItems, in: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item], in: dataScanner)
        }

        private func handle(_ items: [RecognizedItem], in scanner: DataScannerViewController) {
            guard !handled else { return }
            for case let .barcode(barcode) in items {
                if let value = barcode.payloadStringValue, !value.isEmpty {
                    handled = true
                    scanner.stopScanning()
                    onScan(value)
                    return
                }
            }
        }
    }
}
