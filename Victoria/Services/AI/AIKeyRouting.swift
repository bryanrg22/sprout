import Foundation

/// Where a pasted API key goes, and which provider is active when only one has a key.
///
/// The provider choice lives in UserDefaults and the keys live in the Keychain. Deleting
/// the app clears the first and keeps the second, so after a reinstall an OpenAI user is
/// back on the default provider (Anthropic) with an OpenAI key still stored. Two things
/// follow from that, and both are decided here:
///
/// - a key pasted into a field that has no provider picker (onboarding, the Today setup
///   card) is filed by what the key is, not by which provider happens to be active;
/// - at launch, an active provider with no key gives way to the other one if it has a key.
///
/// The two decisions are pure functions; the two wrappers below them touch the Keychain
/// and UserDefaults.
enum AIKeyRouting {

    /// The provider a key belongs to, read from the key itself. Anthropic keys start
    /// `sk-ant-`; any other `sk-` key is OpenAI's (`sk-proj-…`, `sk-svcacct-…`, and the
    /// older bare `sk-…`). Anything else cannot be told apart, and goes to `active`.
    static func provider(forKey key: String, active: AIProvider) -> AIProvider {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("sk-ant-") { return .anthropic }
        if trimmed.hasPrefix("sk-") { return .openai }
        return active
    }

    /// The provider that should be active given which providers have a key. The active one
    /// stays unless it has no key and exactly the other one does.
    static func reconciledProvider(active: AIProvider, hasKey: (AIProvider) -> Bool) -> AIProvider {
        guard !hasKey(active) else { return active }
        return AIProvider.allCases.first { $0 != active && hasKey($0) } ?? active
    }

    // MARK: - Applied to the Keychain and UserDefaults

    /// Stores a key the user pasted or typed, under the provider it belongs to, and makes
    /// that provider the active one. Returns the provider, or nil for an empty key.
    @discardableResult
    static func savePastedKey(_ key: String) -> AIProvider? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let target = provider(forKey: trimmed, active: AIConfig.provider)
        KeychainStore.setAPIKey(trimmed, for: target)
        if AIConfig.provider != target { AIConfig.provider = target }
        return target
    }

    /// Once per launch, before any view asks `AIConfig.hasActiveKey`.
    static func reconcileProviderAtLaunch() {
        guard !didReconcile else { return }
        didReconcile = true
        let active = AIConfig.provider
        // The built-in gateway counts as a key for the providers it covers.
        let next = reconciledProvider(active: active, hasKey: { KeychainStore.hasAPIKey(for: $0) || AIGateway.covers($0) })
        if next != active {
            AIConfig.provider = next
            Diagnostics.shared.log("AI provider switched to \(next.rawValue) at launch: \(active.rawValue) has no key", .app)
        }
    }

    private static var didReconcile = false
}
