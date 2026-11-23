import SwiftUI
import UIKit

/// "Make my character": the card shown as an onboarding step (after the key step) and in
/// Settings → You. All of its rules live in `AvatarCreationModel`; this is the look.
///
/// States: no OpenAI key · consent + pick a photo · drawing · preview (Use this / Try
/// again / Use a built-in character instead) · accepted · failed (the built-in character
/// stands) · declined. Every state leaves a way forward, and the host (the onboarding
/// footer, the sheet's Close) can always leave.
struct AvatarCreationView: View {
    @Bindable var model: AvatarCreationModel
    /// Called when the person taps "Use this" (Settings applies it and closes).
    var onAccepted: (Data) -> Void = { _ in }
    /// Called when the person chooses a built-in character instead.
    var onChoseBuiltIn: () -> Void = {}

    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var keyDraft = ""
    @FocusState private var keyFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
            stage
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.86), value: model.phase)
        .sheet(isPresented: $showLibrary) {
            PhotoLibraryPicker(selectionLimit: 1) { images in
                if let first = images.first { model.pick(first) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { model.pick($0) }
                .ignoresSafeArea()
        }
        .onAppear {
            model.refreshKeyState()
            #if DEBUG
            runDebugScript()
            #endif
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            ZStack {
                Circle().fill(Theme.brand.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: "wand.and.stars").font(.headline).foregroundStyle(Theme.brand)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Text("Optional").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if case .accepted = model.phase {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Theme.brand)
            }
        }
    }

    private var title: String {
        switch model.phase {
        case .needsKey:  return "This needs an OpenAI key"
        case .start, .working: return "Make your character"
        case .preview:   return "Here's your character"
        case .accepted:  return "This is your character"
        case .failed:    return "That didn't work"
        case .declined:  return "A built-in character it is"
        }
    }

    // MARK: - Stage

    @ViewBuilder private var stage: some View {
        switch model.phase {
        case .needsKey:               needsKeyStage
        case .start:                  startStage
        case .working:                workingStage
        case .preview(let character): previewStage(character)
        case .accepted(let character): acceptedStage(character)
        case .failed(let failure):    failedStage(failure)
        case .declined:               declinedStage
        }
    }

    // MARK: Start: consent + photo

    private var startStage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Pick a clear photo of your face and I'll turn it into a pixel character, like the built-in ones.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            photoToCharacter

            HStack(spacing: Theme.Space.sm) {
                outlineButton(title: model.photo == nil ? "Choose a photo" : "Change photo",
                              icon: "photo.on.rectangle") { showLibrary = true }
                if ImagePicker.cameraAvailable {
                    outlineButton(title: "Take a photo", icon: "camera.fill") { showCamera = true }
                }
            }

            consentBox

            Button { model.generate() } label: {
                Label("Make my character", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 22)
            }
            .buttonStyle(.primary)
            .disabled(!model.canGenerate)
            .opacity(model.canGenerate ? 1 : 0.45)
            .accessibilityHint(model.canGenerate ? "" : "Pick a photo and tick the box first")
        }
    }

    /// Photo → character: what goes in and what comes out, at a glance.
    private var photoToCharacter: some View {
        HStack(spacing: Theme.Space.md) {
            well {
                if let photo = model.photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
            }
            .accessibilityLabel(model.photo == nil ? "No photo picked yet" : "Your photo")

            Image(systemName: "arrow.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .accessibilityHidden(true)

            well {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Theme.brand.opacity(0.85))
            }
            .accessibilityLabel("Your character will appear here")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.sm)
    }

    private func well<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: 96, height: 96)
            .background(Theme.brandSoft)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.brand.opacity(0.30),
                                           style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    /// The consent, in plain words, with the tick that unlocks the button. Nothing is
    /// sent until it is ticked (`AvatarCreationModel.canGenerate`).
    private var consentBox: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Image(systemName: "arrow.up.forward.circle.fill")
                    .foregroundStyle(Theme.brand)
                Text("**Your photo is sent to OpenAI** to draw your character, using your OpenAI key. Sprout doesn't keep the photo. Only the finished character is saved.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                model.consented.toggle()
            } label: {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: model.consented ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(model.consented ? Theme.brand : Theme.textSecondary)
                    Text("OK, send my photo to OpenAI")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(model.consented ? .isSelected : [])
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .fill(Theme.brand.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .strokeBorder(Theme.brand.opacity(0.18), lineWidth: 1))
    }

    // MARK: No key

    private var needsKeyStage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Your character is drawn by OpenAI's image model, so this one step uses an OpenAI key, even if you chat with another provider. The key stays on your phone, in the Keychain.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Space.sm) {
                SecureField("Paste your OpenAI key", text: $keyDraft)
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.brand)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($keyFocused)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.cardRaised))
                    .overlay(Capsule().strokeBorder(Theme.brand.opacity(keyFocused ? 0.45 : 0.12), lineWidth: 1))

                Button {
                    if let pasted = UIPasteboard.general.string {
                        keyDraft = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.brand)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Theme.brandSoft))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste from clipboard")
            }

            Button {
                keyFocused = false
                model.saveKey(keyDraft)
                keyDraft = ""
            } label: {
                Text("Save key").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 22)
            }
            .buttonStyle(.primary)
            .disabled(keyDraftIsEmpty)
            .opacity(keyDraftIsEmpty ? 0.45 : 1)

            fallbackRow("No key? Skip this. You'll start with this built-in character and can make your own later in More → You.")
        }
    }

    private var keyDraftIsEmpty: Bool {
        keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Drawing

    private var workingStage: some View {
        VStack(spacing: Theme.Space.md) {
            ZStack {
                if let photo = model.photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: 148, height: 148)
                        .blur(radius: 6)
                        .opacity(0.55)
                }
                Circle().fill(Theme.background.opacity(0.35))
                ProgressView().controlSize(.large).tint(Theme.brand)
            }
            .frame(width: 148, height: 148)
            .background(Theme.brandSoft)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.brand.opacity(0.35), lineWidth: 2))

            VStack(spacing: 4) {
                Text("Drawing your character…")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("This usually takes under half a minute. You don't have to wait here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            outlineButton(title: "Cancel", icon: "xmark") { model.cancel() }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Preview / accepted

    private func previewStage(_ character: AvatarGenerator.Character) -> some View {
        VStack(spacing: Theme.Space.md) {
            portrait(character.png)

            Button {
                model.accept()
                onAccepted(character.png)
            } label: {
                Label("Use this", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 22)
            }
            .buttonStyle(.primary)

            outlineButton(title: "Try again", icon: "arrow.clockwise") { model.tryAgain() }

            Button {
                model.useBuiltIn()
                onChoseBuiltIn()
            } label: {
                Text("Use a built-in character instead")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func acceptedStage(_ character: AvatarGenerator.Character) -> some View {
        VStack(spacing: Theme.Space.md) {
            portrait(character.png)
            Label("You'll see it on Today, with your buddy and on your widgets.",
                  systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.brand)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            outlineButton(title: "Make a different one", icon: "arrow.clockwise") { model.startOver() }
        }
        .frame(maxWidth: .infinity)
    }

    /// The character, large, on the skin's tinted disc: how it will sit in the app.
    private func portrait(_ png: Data) -> some View {
        CustomCompanionImage(png: png)
            .padding(18)
            .frame(width: 176, height: 176)
            .background(Theme.brandSoft, in: Circle())
            // A character's shoulders reach the corners of its square; keep them inside the ring.
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.brand.opacity(0.45), lineWidth: 2))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Your pixel character")
    }

    // MARK: Failed / declined

    private func failedStage(_ failure: AvatarGenerator.Failure) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                Text(failure.errorDescription ?? "The character couldn't be made.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            fallbackRow("Nothing's lost: you'll start with this built-in character, and you can make your own any time in More → You.")

            HStack(spacing: Theme.Space.sm) {
                if failure.isWorthRetrying, model.photo != nil {
                    outlineButton(title: "Try again", icon: "arrow.clockwise") { model.tryAgain() }
                }
                outlineButton(title: "Another photo", icon: "photo.on.rectangle") { showLibrary = true }
            }
        }
    }

    private var declinedStage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            fallbackRow("This is your character. You can make your own from a photo any time in More → You.")
            outlineButton(title: "Make one from a photo after all", icon: "wand.and.stars") { model.startOver() }
        }
    }

    /// The built-in character the person has when there is no custom one, with a line
    /// saying so. Shown in every state that does not end with a custom character.
    private func fallbackRow(_ text: String) -> some View {
        HStack(spacing: Theme.Space.md) {
            BuiltInCompanionThumb(avatar: model.fallbackAvatar)
                .frame(width: 44, height: 53)
                .frame(width: 64, height: 64)
                .background(Theme.brandSoft, in: Circle())
                .overlay(Circle().strokeBorder(Theme.divider, lineWidth: 1))
                .clipShape(Circle())
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.sm)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.cardRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .strokeBorder(Theme.divider, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pieces

    /// A tinted, outlined secondary button, the same shape onboarding's Connect step uses.
    private func outlineButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: icon).font(.subheadline.weight(.semibold))
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.brand)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.brand.opacity(0.10), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.brand.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    #if DEBUG
    /// Drives the step from launch arguments, for screenshots (see `AvatarDebug`).
    private func runDebugScript() {
        guard AvatarDebug.mode != nil else { return }
        if AvatarDebug.wantsSamplePhoto, model.photo == nil, model.phase == .start {
            model.pick(AvatarDebug.samplePhoto())
            model.consented = true
        }
        guard AvatarDebug.wantsAutostart, model.canGenerate else { return }
        Task {
            await model.generateAndWait()
            if AvatarDebug.wantsAccept, case .preview(let character) = model.phase {
                model.accept()
                onAccepted(character.png)
            }
        }
    }
    #endif
}

/// One of the hand-drawn characters as a small still. A custom avatar draws the person's
/// own image, so this view is safe to hand any `CompanionAvatar`.
struct BuiltInCompanionThumb: View {
    let avatar: CompanionAvatar

    var body: some View {
        switch avatar {
        case .victoria:
            PixelArtView(rows: PixelVictoria.rows(mood: .happy, eyesOpen: true), palette: PixelVictoria.palette)
        case .bryan:
            PixelArtView(rows: PixelBryan.rows(mood: .happy, eyesOpen: true), palette: PixelBryan.palette)
        case .custom:
            CustomCompanionImage()
        }
    }
}

/// Settings → You → "Make my character": the same flow, in a sheet, applied to the
/// profile the moment the person taps "Use this".
struct AvatarCreationSheet: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var model: AvatarCreationModel

    init(profile: UserProfile) {
        self.profile = profile
        _model = State(initialValue: AvatarCreationModel(theme: profile.themeStyle))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    AvatarCreationView(
                        model: model,
                        onAccepted: { png in
                            profile.useCustomAvatar(png: png)
                            try? context.save()
                            WidgetDataWriter.refresh(context: context, profile: profile)
                        },
                        onChoseBuiltIn: {
                            profile.companionAvatar = model.fallbackAvatar
                            try? context.save()
                            WidgetDataWriter.refresh(context: context, profile: profile)
                        })
                    if profile.customAvatarPNG != nil, case .start = model.phase {
                        Text("Making a new character replaces the one you have.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, Theme.Space.xs)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Your character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isDone ? "Done" : "Close") { dismiss() }
                        .fontWeight(isDone ? .semibold : .regular)
                }
            }
        }
        .tint(Theme.brand)
    }

    private var isDone: Bool {
        switch model.phase {
        case .accepted, .declined: return true
        case .needsKey, .start, .working, .preview, .failed: return false
        }
    }
}
