import SwiftUI
import PhotosUI
import UIKit

/// The photo-based logging flow: snap or pick one or MORE photos of the same meal,
/// optionally add a note, send them together to the AI estimator for one combined
/// estimate, then confirm in `AddFoodSheet`.
struct PhotoFoodFlow: View {
    @Environment(\.dismiss) private var dismiss

    /// The day to log the resulting entry to.
    let date: Date
    /// When set (e.g. she tapped an empty "Lunch" section), the result lands in this meal.
    var preferredMeal: MealType? = nil

    /// Most people photograph a meal from a couple of angles / a few plates — more than a
    /// handful is noise and bloats the estimate request, so we cap it.
    private let maxPhotos = 4

    @State private var phase: Phase = .choosing
    @State private var note: String = ""
    @State private var images: [UIImage] = []
    @State private var jpegs: [Data] = []
    @FocusState private var noteFocused: Bool

    // Picker presentation
    @State private var showingCamera = false
    @State private var showingLibrary = false

    // Result
    @State private var draft: FoodDraft?
    @State private var errorMessage: String?

    private enum Phase {
        case choosing      // pick sources + optional note
        case analyzing     // awaiting AI
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.background)
                .navigationTitle("Photo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(phase == .analyzing)
                    }
                    // A "Done" above the keyboard so the Estimate button below the field is
                    // always reachable when describing a meal.
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { noteFocused = false }
                    }
                }
        }
        // Camera (real device only). Simulator falls back to the library button.
        .fullScreenCover(isPresented: $showingCamera) {
            ImagePicker(sourceType: .camera) { image in
                append([image])
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingLibrary) {
            PhotoLibraryPicker(selectionLimit: max(1, maxPhotos - images.count)) { picked in
                append(picked)
            }
        }
        // Once we have an estimate, hand off to the editable confirm sheet.
        .sheet(item: $draft, onDismiss: { dismiss() }) { draft in
            AddFoodSheet(draft: draft, date: date)
        }
        .alert("Couldn't estimate", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .choosing:
            choosingView
        case .analyzing:
            analyzingView
        }
    }

    // MARK: - Choosing

    private var choosingView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if images.isEmpty {
                    placeholder
                    sourceButtons
                } else {
                    thumbnailStrip
                }

                if !ImagePicker.cameraAvailable && images.isEmpty {
                    Text("No camera here — pick a photo from your library instead.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Or just describe it")
                        .font(.subheadline.weight(.semibold))
                    TextField("e.g. Chipotle chicken burrito with guac", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($noteFocused)
                        .padding(10)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("Add a note to sharpen a photo estimate — or skip the photo and just describe your meal here.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                if canEstimate {
                    Button {
                        analyze()
                    } label: {
                        Label(images.isEmpty ? "Estimate from description" : "Estimate nutrition",
                              systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.primary)
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The two ways to add the FIRST photo. Once there's at least one, the thumbnail
    /// strip's "+" tile takes over (so the screen isn't crowded with big buttons).
    private var sourceButtons: some View {
        VStack(spacing: 12) {
            Button {
                showingCamera = true
            } label: {
                Label("Take a photo", systemImage: "camera.fill")
            }
            .buttonStyle(.primary)
            .disabled(!ImagePicker.cameraAvailable)

            Button {
                showingLibrary = true
            } label: {
                Label("Choose from library", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.primary)
        }
    }

    /// Horizontal strip of the chosen photos, each removable, with a "+" tile to add
    /// more of the SAME meal (up to `maxPhotos`).
    private var thumbnailStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { idx, img in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 104, height: 104)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Button {
                                remove(at: idx)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                                    .padding(5)
                            }
                            .accessibilityLabel("Remove photo \(idx + 1)")
                        }
                    }

                    if images.count < maxPhotos {
                        addMoreTile
                    }
                }
                .padding(.vertical, 2)
            }
            Text("\(images.count) of \(maxPhotos) photos · all treated as one meal")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var addMoreTile: some View {
        Menu {
            if ImagePicker.cameraAvailable {
                Button { showingCamera = true } label: { Label("Take a photo", systemImage: "camera") }
            }
            Button { showingLibrary = true } label: { Label("Choose from library", systemImage: "photo.on.rectangle") }
        } label: {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.accentSoft)
                .frame(width: 104, height: 104)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                        Text("Add")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.accent)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5]))
                )
        }
        .accessibilityLabel("Add another photo")
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .fill(Theme.accentSoft)
            .frame(height: 220)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accent)
                    Text("Snap or choose photos of your meal")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            )
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 18) {
            if let first = images.first {
                Image(uiImage: first)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .opacity(0.85)
            }
            ProgressView()
                .controlSize(.large)
            Text(images.count > 1 ? "Estimating your meal from \(images.count) photos…" : "Estimating your meal…")
                .font(.headline)
            Text("This is just a starting point you'll be able to edit.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logic

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    /// Downscale + encode each picked image and append, respecting the cap.
    private func append(_ picked: [UIImage]) {
        for image in picked {
            guard images.count < maxPhotos else { break }
            let scaled = image.downscaled(maxEdge: 1024)
            guard let data = scaled.jpegData(compressionQuality: 0.7) else { continue }
            images.append(scaled)
            jpegs.append(data)
        }
    }

    private func remove(at index: Int) {
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
        jpegs.remove(at: index)
    }

    /// We can estimate from photos, a typed description, or both.
    private var canEstimate: Bool {
        !jpegs.isEmpty || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func analyze() {
        guard canEstimate else { return }
        let photos = jpegs
        let desc = note.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .analyzing
        Task {
            do {
                let result: FoodPhotoAnalysis
                if !photos.isEmpty {
                    result = try await FoodPhotoAnalyzer.analyze(
                        imagesData: photos, userNote: desc.isEmpty ? nil : desc)
                } else {
                    // Text-only "just describe it" path.
                    result = try await FoodPhotoAnalyzer.analyze(description: desc)
                }
                await MainActor.run {
                    draft = makeDraft(from: result, jpegs: photos)
                }
            } catch AIConfig.AIError.missingKey {
                await MainActor.run {
                    phase = .choosing
                    errorMessage = "Add your AI key in More → AI to use AI estimates."
                }
            } catch {
                await MainActor.run {
                    phase = .choosing
                    errorMessage = "We couldn't estimate this one. Try again, or add it manually."
                }
            }
        }
    }

    /// Convert the AI analysis into a single summarizing draft for the confirm sheet.
    /// `jpegs` is empty for the text-only "describe it" path; otherwise the first photo
    /// becomes the cover and the rest ride along as additional photos.
    private func makeDraft(from a: FoodPhotoAnalysis, jpegs: [Data]) -> FoodDraft {
        var notesParts: [String] = []
        if !a.notes.isEmpty { notesParts.append(a.notes) }
        if let assumptions = a.assumptions, !assumptions.isEmpty {
            notesParts.append("Assumptions: " + assumptions.joined(separator: "; "))
        }

        // Vet the AI's totals: fill calories if it omitted them, and downgrade confidence
        // with a "double-check" note if the numbers are physically implausible.
        let grams = a.items.reduce(0) { $0 + $1.estimated_grams }
        let sanity = NutritionSanity.check(
            calories: a.totalCalories, protein: a.totalProteinG,
            carbs: a.totalCarbsG, fat: a.totalFatG,
            grams: grams > 0 ? grams : nil)
        if let note = sanity.reason { notesParts.append(note) }
        let combinedNotes = notesParts.isEmpty ? nil : notesParts.joined(separator: "\n")

        let name = a.items.first.map { item -> String in
            a.items.count > 1 ? "\(item.name) + \(a.items.count - 1) more" : item.name
        } ?? "Meal from photo"

        return FoodDraft(
            name: name,
            meal: preferredMeal ?? MealTime.current(),
            servingDescription: a.items.first?.quantity ?? "",
            quantity: 1,
            calories: sanity.calories,
            proteinG: a.totalProteinG,
            carbsG: a.totalCarbsG,
            fatG: a.totalFatG,
            caloriesLow: a.caloriesLow,
            caloriesHigh: a.caloriesHigh,
            source: .photo,
            confidence: sanity.isSuspicious ? .low : a.confidenceLevel,
            barcode: nil,
            notes: combinedNotes,
            photoData: jpegs.first,
            additionalPhotoData: jpegs.count > 1 ? Array(jpegs.dropFirst()) : nil,
            // Only the four the estimator is asked for, and only those it gave a basis for.
            detail: a.detail
        )
    }
}

// MARK: - Camera picker (UIImagePickerController)

/// Wraps `UIImagePickerController` for camera capture (one shot per presentation).
/// Shared with the Vita chat's in-conversation photo attach.
struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPick: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    static var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPick(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Library picker (PHPickerViewController)

/// Wraps `PHPickerViewController` for choosing one or more images from the library.
/// Shared with the Vita chat's in-conversation photo attach.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    /// How many images may be selected this time (the caller passes the remaining slots).
    let selectionLimit: Int
    let onPick: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = selectionLimit
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker
        init(_ parent: PhotoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let providers = results.map(\.itemProvider).filter { $0.canLoadObject(ofClass: UIImage.self) }
            guard !providers.isEmpty else {
                parent.dismiss()
                return
            }
            // Load all selections, preserving the order the user picked them in.
            let group = DispatchGroup()
            var loaded = [Int: UIImage]()
            let lock = NSLock()
            for (index, provider) in providers.enumerated() {
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        lock.lock(); loaded[index] = image; lock.unlock()
                    }
                    group.leave()
                }
            }
            let parent = self.parent
            group.notify(queue: .main) {
                let ordered = loaded.sorted { $0.key < $1.key }.map(\.value)
                parent.onPick(ordered)
                parent.dismiss()
            }
        }
    }
}

// MARK: - Helpers

extension UIImage {
    /// Returns a copy scaled so its longest edge is at most `maxEdge` points.
    func downscaled(maxEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxEdge, longest > 0 else { return self }
        let scale = maxEdge / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// Picks a sensible default meal type based on the current hour.
enum MealTime {
    static func current(_ date: Date = .now) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<17: return .snack
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}
