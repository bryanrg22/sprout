import SwiftUI
import UIKit

/// The steps of "make my character", shared by onboarding and Settings → You.
///
/// The rules it holds (the owner's decisions, tested in `AvatarCreationModelTests`):
/// - Nothing is sent until the person has picked a photo AND ticked the consent that says
///   the photo goes to OpenAI.
/// - The photo lives in this object's memory only, and is dropped as soon as a character
///   is accepted or the person chooses a built-in one. Only the accepted PNG leaves.
/// - No state is a dead end: with no key, a refusal, a network failure or a bad image,
///   `fallbackAvatar` is what the person gets, and leaving the step is always possible.
@MainActor
@Observable
final class AvatarCreationModel {

    enum Phase: Equatable {
        /// No OpenAI key is stored.
        case needsKey
        /// Consent, pick a photo, "Make my character".
        case start
        case working
        /// A character came back and passed validation; not adopted yet.
        case preview(AvatarGenerator.Character)
        /// The person chose "Use this".
        case accepted(AvatarGenerator.Character)
        /// The call failed; the built-in character stands.
        case failed(AvatarGenerator.Failure)
        /// The person chose a built-in character instead.
        case declined
    }

    private(set) var phase: Phase
    /// The picked photo. Memory only; never written anywhere by the app.
    private(set) var photo: UIImage?
    /// Ticked by the person: "send this photo to OpenAI".
    var consented = false
    /// The look the built-in fallback goes with.
    var theme: ThemeStyle

    private var task: Task<Void, Never>?
    private let hasKey: () -> Bool

    init(theme: ThemeStyle, hasKey: @escaping () -> Bool = { AvatarCreationModel.defaultHasKey() }) {
        self.theme = theme
        self.hasKey = hasKey
        phase = hasKey() ? .start : .needsKey
    }

    nonisolated static func defaultHasKey() -> Bool {
        #if DEBUG
        if let stubbed = AvatarDebug.hasKeyOverride { return stubbed }
        #endif
        return AIConfig.hasImageKey
    }

    // MARK: Derived

    /// The built-in character the person has whenever there is no accepted custom one.
    var fallbackAvatar: CompanionAvatar { .builtIn(for: theme) }

    /// The PNG to store on the profile, or nil to keep the built-in character.
    var acceptedPNG: Data? {
        if case .accepted(let character) = phase { return character.png }
        return nil
    }

    var canGenerate: Bool { phase == .start && photo != nil && consented }

    // MARK: Actions

    func pick(_ image: UIImage) {
        photo = image
        if case .failed = phase { phase = .start }
    }

    func removePhoto() {
        photo = nil
    }

    /// Store a pasted OpenAI key (Keychain) and move on to the photo step.
    func saveKey(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.setAPIKey(trimmed, for: .openai)
        if phase == .needsKey { phase = .start }
    }

    /// Re-check the key (it may have been added in Settings while this was open).
    func refreshKeyState() {
        if phase == .needsKey, hasKey() { phase = .start }
    }

    /// Start a generation. Does nothing without a photo and consent.
    func generate() {
        guard canGenerate, let photo else { return }
        phase = .working
        let theme = theme
        task = Task { [weak self] in
            let outcome = await Self.run(photo: photo, theme: theme)
            guard let self, !Task.isCancelled, self.phase == .working else { return }
            switch outcome {
            case .custom(let character):       self.phase = .preview(character)
            case .builtIn(_, because: .missingKey): self.phase = .needsKey
            case .builtIn(_, because: let failure): self.phase = .failed(failure)
            }
        }
    }

    /// Runs one generation to its end (tests await this instead of polling).
    func generateAndWait() async {
        generate()
        await task?.value
    }

    private nonisolated static func run(photo: UIImage, theme: ThemeStyle) async -> AvatarGenerator.Outcome {
        #if DEBUG
        if let runtime = AvatarDebug.stubRuntime {
            return await AIRuntime.$current.withValue(runtime) {
                await AvatarGenerator.outcome(for: photo, theme: theme)
            }
        }
        #endif
        return await AvatarGenerator.outcome(for: photo, theme: theme)
    }

    /// Stop waiting for an image in flight and go back to the photo step.
    func cancel() {
        task?.cancel()
        task = nil
        if phase == .working { phase = .start }
    }

    /// "Use this": adopt the previewed character. The photo is no longer needed.
    func accept() {
        guard case .preview(let character) = phase else { return }
        photo = nil
        phase = .accepted(character)
    }

    /// "Try again": another image from the same photo (preview), or another go after a failure.
    func tryAgain() {
        switch phase {
        case .preview, .failed:
            phase = .start
            if canGenerate { generate() }
        case .needsKey, .start, .working, .accepted, .declined:
            break
        }
    }

    /// "Use a built-in character instead": drop the photo and anything generated.
    func useBuiltIn() {
        task?.cancel()
        task = nil
        photo = nil
        consented = false
        phase = .declined
    }

    /// Back to the beginning from an accepted or declined state.
    func startOver() {
        task?.cancel()
        task = nil
        photo = nil
        consented = false
        phase = hasKey() ? .start : .needsKey
    }
}
