import XCTest
@testable import Victoria

/// EVAL_REPORT 3, L-B9: after a delete and reinstall the provider choice (UserDefaults) is
/// back to Anthropic while the keys (Keychain) are still there, and the two paste fields
/// with no provider picker stored an OpenAI key in the Anthropic slot.
///
/// `AIKeyRouting` decides both things from values, so they are tested without a Keychain.
final class AIKeyRoutingTests: XCTestCase {

    // MARK: - Where a pasted key goes

    func testAnAnthropicKeyGoesToAnthropicWhateverIsActive() {
        XCTAssertEqual(AIKeyRouting.provider(forKey: "sk-ant-api03-not-a-real-key", active: .anthropic), .anthropic)
        XCTAssertEqual(AIKeyRouting.provider(forKey: "sk-ant-api03-not-a-real-key", active: .openai), .anthropic)
    }

    /// The defect: active is Anthropic (the default after a reinstall) and the key is OpenAI's.
    func testAnOpenAIKeyGoesToOpenAIWhateverIsActive() {
        for key in ["sk-proj-not-a-real-key", "sk-svcacct-not-a-real-key", "sk-notarealkey0000"] {
            XCTAssertEqual(AIKeyRouting.provider(forKey: key, active: .anthropic), .openai, key)
            XCTAssertEqual(AIKeyRouting.provider(forKey: key, active: .openai), .openai, key)
        }
    }

    func testAKeyThatCannotBeToldApartGoesToTheActiveProvider() {
        for key in ["a-proxy-token", "SK-ANT-uppercase-is-not-a-key-prefix", "ant-sk-", "sk"] {
            XCTAssertEqual(AIKeyRouting.provider(forKey: key, active: .anthropic), .anthropic, key)
            XCTAssertEqual(AIKeyRouting.provider(forKey: key, active: .openai), .openai, key)
        }
    }

    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(AIKeyRouting.provider(forKey: "  sk-proj-not-a-real-key\n", active: .anthropic), .openai)
        XCTAssertEqual(AIKeyRouting.provider(forKey: "\tsk-ant-not-a-real-key ", active: .openai), .anthropic)
    }

    // MARK: - Which provider is active at launch

    private func reconciled(active: AIProvider, keys: Set<AIProvider>) -> AIProvider {
        AIKeyRouting.reconciledProvider(active: active) { keys.contains($0) }
    }

    /// The reinstall: Anthropic by default, an OpenAI key in the Keychain.
    func testActiveWithoutAKeyGivesWayToTheProviderThatHasOne() {
        XCTAssertEqual(reconciled(active: .anthropic, keys: [.openai]), .openai)
        XCTAssertEqual(reconciled(active: .openai, keys: [.anthropic]), .anthropic)
    }

    func testActiveWithAKeyStays() {
        XCTAssertEqual(reconciled(active: .anthropic, keys: [.anthropic]), .anthropic)
        XCTAssertEqual(reconciled(active: .openai, keys: [.openai]), .openai)
        // Both stored: the user's choice stands.
        XCTAssertEqual(reconciled(active: .anthropic, keys: [.anthropic, .openai]), .anthropic)
        XCTAssertEqual(reconciled(active: .openai, keys: [.anthropic, .openai]), .openai)
    }

    func testNoKeyAnywhereChangesNothing() {
        XCTAssertEqual(reconciled(active: .anthropic, keys: []), .anthropic)
        XCTAssertEqual(reconciled(active: .openai, keys: []), .openai)
    }

    /// The two decisions together, as the reinstall plays out: launch moves the provider to
    /// the stored key, and a key pasted before or after that lands in its own slot.
    func testReinstallAsAnOpenAIUser() {
        var active = AIProvider.anthropic                 // UserDefaults was cleared
        var stored: Set<AIProvider> = [.openai]            // the Keychain was not
        active = AIKeyRouting.reconciledProvider(active: active) { stored.contains($0) }
        XCTAssertEqual(active, .openai, "the app opens with a working provider")

        // Had the key been removed too, pasting it again must not land in the Anthropic slot.
        active = .anthropic
        stored = []
        let target = AIKeyRouting.provider(forKey: "sk-proj-not-a-real-key", active: active)
        stored.insert(target)
        active = target
        XCTAssertEqual(stored, [.openai])
        XCTAssertEqual(active, .openai)
    }
}
