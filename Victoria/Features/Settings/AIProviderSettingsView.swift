import SwiftUI

/// "AI Provider" — a standalone settings screen letting the user choose which LLM
/// vendor powers the app (Anthropic or OpenAI), paste that provider's own API key, and
/// optionally override the model. Warm, bring-your-own-key framing.
///
/// Design: native insetGrouped `Form` over `Theme.background`, the same tinted-icon
/// `row(...)` rhythm + uppercase section headers as `SettingsView`. Theme-aware (reads
/// the active skin), so it looks right in both the cute and cool palettes.
///
/// State model: the picked provider is persisted immediately to `AIConfig.provider`.
/// The key + model fields reflect the *selected* provider and reload when it changes;
/// the key is held only in memory while editing and written to the Keychain on save.
struct AIProviderSettingsView: View {

    @State private var provider: AIProvider = AIConfig.provider

    // Key: held in memory while typing; persisted to Keychain on save. `keyStored`
    // tracks whether the *selected* provider already has a key on this device.
    @State private var keyDraft = ""
    @State private var keyStored = false

    // Model override for the selected provider's STRONG (coach/food) model. Empty =
    // use the provider's sensible default (shown as the placeholder).
    @State private var modelDraft = ""

    @State private var saveTick = 0

    /// Live result of pinging the API to confirm the saved key actually authenticates.
    @State private var keyCheck: KeyCheck = .idle
    private enum KeyCheck: Equatable { case idle, checking, ok, failed(String) }

    var body: some View {
        Form {
            builtInSection
            providerSection
            keySection
            modelSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("AI Provider")
        .navigationBarTitleDisplayMode(.large)
        .tint(Theme.brand)
        .onAppear(perform: loadForSelectedProvider)
        .onChange(of: provider) { _, newValue in
            // Persist the choice, then reload the fields to reflect the new provider.
            AIConfig.provider = newValue
            loadForSelectedProvider()
        }
        .sensoryFeedback(.success, trigger: saveTick)
    }

    // MARK: - Built-in AI

    /// Shown when Sprout's own gateway covers the chosen provider (`AIGateway`): nothing to set
    /// up. A key saved below is used instead of it.
    @ViewBuilder private var builtInSection: some View {
        if AIGateway.covers(provider) {
            Section {
                row(icon: keyStored ? "person.badge.key.fill" : "sparkles", tint: Theme.positive) {
                    LabeledContent("Built-in AI") {
                        Text(keyStored ? "Using your key" : "On")
                            .foregroundStyle(keyStored ? Theme.textSecondary : Theme.positive)
                    }
                }
            } footer: {
                footer(keyStored
                       ? "Your own \(provider.label) key is saved, so Sprout uses it. Remove it to go back to the built-in AI."
                       : "Vita, meal photos and your daily note work with no key. There's a daily limit; if you'd rather have none, add your own \(provider.label) key below.")
            }
        }
    }

    // MARK: - Provider picker

    private var providerSection: some View {
        Section {
            Picker("Provider", selection: $provider) {
                ForEach(AIProvider.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Theme.card)
        } header: {
            sectionHeader("Provider")
        } footer: {
            footer("Pick whose models power your coach, daily note, and meal-photo estimates. You bring your own key, so you’re only ever billed by \(provider.label) directly — at their cost, with no markup.")
        }
    }

    // MARK: - API key

    private var keySection: some View {
        Section {
            row(icon: "key.fill") {
                SecureField(provider.keyHint, text: $keyDraft)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(Theme.textPrimary)
                    .submitLabel(.done)
                    .onSubmit(saveKey)
            }

            Button(action: saveKey) {
                Label(keyStored ? "Update key" : "Save key", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.brand)
            }
            .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)

            row(icon: keyStored ? "checkmark.circle.fill" : "circle.dashed",
                tint: keyStored ? Theme.positive : Theme.textSecondary) {
                LabeledContent("Status") {
                    Text(keyStored ? "Saved" : "Not saved")
                        .foregroundStyle(keyStored ? Theme.positive : Theme.textSecondary)
                }
            }

            keyCheckRow

            if keyStored {
                Button(action: verifyKey) {
                    Label("Verify key works", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(Theme.brand)
                }
                .disabled(keyCheck == .checking)

                Button(role: .destructive, action: removeKey) {
                    Label("Remove key", systemImage: "trash")
                }
            }
        } header: {
            sectionHeader("\(provider.label) API key")
        } footer: {
            footer("Get a key at \(provider.consoleName). It’s stored only in this device’s Keychain — never uploaded, never shared, and easy to remove anytime.")
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - Model override

    private var modelSection: some View {
        Section {
            row(icon: "cpu") {
                LabeledContent("Model") {
                    TextField(provider.defaultCoachModel, text: $modelDraft)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(Theme.textPrimary)
                        .submitLabel(.done)
                        .onSubmit(saveModel)
                }
            }

            if !modelDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Reset to default (\(provider.defaultCoachModel))") {
                    modelDraft = ""
                    saveModel()
                }
                .foregroundStyle(Theme.brand)
            }
        } header: {
            sectionHeader("Model")
        } footer: {
            footer("Leave blank to use the recommended model (\(provider.defaultCoachModel)). Advanced: type any \(provider.label) model name to override it. The short daily note uses a cheaper model automatically.")
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Text("Your key powers meal-photo estimates and your coach. Estimates only — not medical advice.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    /// Load the key-stored flag + the model override for whatever provider is selected.
    /// Clears the in-memory key draft (we never surface a stored secret back into a field).
    private func loadForSelectedProvider() {
        keyStored = KeychainStore.hasAPIKey(for: provider)
        keyDraft = ""
        keyCheck = .idle
        modelDraft = AIConfig.modelOverride(for: provider, tier: .coach) ?? ""
    }

    // MARK: - Key verification

    /// Live result of the API ping confirming the saved key works.
    @ViewBuilder private var keyCheckRow: some View {
        switch keyCheck {
        case .idle:
            EmptyView()
        case .checking:
            row(icon: "arrow.triangle.2.circlepath", tint: Theme.textSecondary) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking your key…").foregroundStyle(Theme.textSecondary)
                }
            }
        case .ok:
            row(icon: "checkmark.seal.fill", tint: Theme.positive) {
                Text("Key works — Vita's ready 💚").foregroundStyle(Theme.positive)
            }
        case .failed(let msg):
            row(icon: "exclamationmark.triangle.fill", tint: .red) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Key didn't work").foregroundStyle(.red)
                    Text(msg).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    /// Ping the selected provider's API to confirm the SAVED key authenticates. Auto-runs
    /// after Save and on the manual "Verify key works" button.
    private func verifyKey() {
        guard KeychainStore.hasAPIKey(for: provider) else { return }
        keyCheck = .checking
        let selected = provider
        Task {
            do {
                switch selected {
                case .anthropic: try await AnthropicClient().validate()
                case .openai:    try await OpenAIClient().validate()
                }
                keyCheck = .ok
                saveTick += 1
            } catch {
                keyCheck = .failed(Self.friendlyMessage(error))
            }
        }
    }

    private static func friendlyMessage(_ error: Error) -> String {
        if case AIConfig.AIError.badResponse(let m) = error { return String(m.prefix(180)) }
        if case AIConfig.AIError.missingKey = error { return "No key saved yet." }
        if error is URLError { return "Couldn't reach the server — check your connection, then tap Verify again." }
        return error.localizedDescription
    }

    private func saveKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.setAPIKey(trimmed, for: provider)
        keyDraft = ""
        keyStored = KeychainStore.hasAPIKey(for: provider)
        saveTick += 1
        verifyKey()   // immediately confirm the saved key actually authenticates
    }

    private func removeKey() {
        KeychainStore.setAPIKey(nil, for: provider)
        keyDraft = ""
        keyStored = KeychainStore.hasAPIKey(for: provider)
        keyCheck = .idle
        saveTick += 1
    }

    private func saveModel() {
        // Blank clears the override (→ provider default). Persist per-provider so each
        // vendor keeps its own model string.
        AIConfig.setModelOverride(modelDraft, for: provider, tier: .coach)
        modelDraft = AIConfig.modelOverride(for: provider, tier: .coach) ?? ""
        saveTick += 1
    }

    // MARK: - Row helpers (self-contained — mirrors SettingsView's look)

    private func row<Content: View>(icon: String,
                                    tint: Color = Theme.brand,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)
            content()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
    }
}
