import Foundation
import Security

/// Minimal Keychain wrapper for the secrets we hold: the per-provider LLM API keys
/// (Anthropic + OpenAI). Keys live ONLY here — never in SwiftData or UserDefaults.
///
/// Each provider's key is a separate generic-password item under a distinct
/// service+account, so they coexist and a user can store both. The original
/// `apiKey()` / `setAPIKey(_:)` / `hasAPIKey` accessors are preserved verbatim and
/// continue to mean the *Anthropic* key (back-compat for existing call sites).
enum KeychainStore {
    private static let service = "com.bryanram.victoria"

    /// Per-provider account names (distinct rows under the same service).
    private static func account(for provider: AIProvider) -> String {
        switch provider {
        case .anthropic: return "anthropic_api_key"   // unchanged from the original
        case .openai:    return "openai_api_key"
        }
    }

    // MARK: - Generic per-provider accessors

    static func setAPIKey(_ key: String?, for provider: AIProvider) {
        let acct = account(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct,
        ]
        SecItemDelete(query as CFDictionary)
        guard let key, !key.isEmpty, let data = key.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func apiKey(for provider: AIProvider) -> String? {
        let acct = account(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    static func hasAPIKey(for provider: AIProvider) -> Bool {
        apiKey(for: provider)?.isEmpty == false
    }

    // MARK: - Generic secret storage (Data blobs, e.g. OAuth tokens)

    /// Store an arbitrary secret blob under `account` (nil deletes). Same service +
    /// accessibility as the API keys, so all secrets live under one Keychain umbrella.
    static func setSecret(_ data: Data?, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let data, !data.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func secret(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    // MARK: - Back-compat accessors (Anthropic)
    //
    // These keep the original signatures so existing call sites (SettingsView,
    // InsightPhraser, OnboardingCoachMessage, the old AnthropicClient init path) compile
    // and behave exactly as before. They are thin shims over the Anthropic provider.

    static func setAPIKey(_ key: String?) { setAPIKey(key, for: .anthropic) }
    static func apiKey() -> String? { apiKey(for: .anthropic) }
    static var hasAPIKey: Bool { hasAPIKey(for: .anthropic) }
}
