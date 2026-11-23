import SwiftUI

/// Where two friends connect. Shows MY pairing code to share, and a field to type in my
/// buddy's code → `link(usingCode:)`. Warm copy throughout; errors are handled kindly
/// (never a scary alert — just a gentle inline banner from the view model).
struct PairingView: View {
    @Bindable var model: BuddyViewModel
    /// Whether "Share my full stats with your buddy" is on, so this screen says what a
    /// buddy will actually see.
    var sharesFullStats: Bool = false
    /// So a successful link can pop this sheet/screen back to the hub.
    var onLinked: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var enteredCode = ""
    @State private var copied = false
    @State private var diagRunning = false
    @State private var diagReport: String?
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.lg) {
                intro
                if let problem = model.accountProblem { accountNotice(problem) }
                myCodeCard
                connector
                enterCodeCard
            }
            .padding(.horizontal)
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(backdrop)
        .navigationTitle("Pair with a buddy")
        .navigationBarTitleDisplayMode(.inline)
        // Kind inline banner for successes/errors.
        .safeAreaInset(edge: .bottom) {
            if let banner = model.banner {
                BuddyBannerView(banner: banner) { model.banner = nil }
                    .padding(.horizontal)
                    .padding(.bottom, Theme.Space.sm)
            }
        }
        // When linking succeeds, the VM flips `isLinked` — bounce back to the hub.
        .onChange(of: model.isLinked) { _, linked in
            if linked {
                codeFieldFocused = false
                onLinked()
                dismiss()
            }
        }
        // Auto-detect when a buddy claims MY code, so the code-GENERATOR connects without
        // reopening the app. Polls while this screen is up; stops the moment we're linked
        // (the screen dismisses) or the view goes away (`.task` is cancelled).
        .task {
            while !Task.isCancelled && !model.isLinked {
                await model.refresh()
                if model.isLinked { break }
                try? await Task.sleep(for: .seconds(4))
            }
        }
        // A failure stays on screen until the code is changed: it has to be read.
        .onChange(of: enteredCode) { _, _ in model.clearLinkError() }
        #if DEBUG
        .task {
            // DEBUG: `--demo-buddy-ui pairing-<wrong|own|claimed|shape>` types that code and
            // taps Connect, so each failure can be looked at without tapping.
            guard case .pairing(let attempt)? = BuddyDemoUI.requested, enteredCode.isEmpty else { return }
            enteredCode = attempt.code(mine: model.myPairingCode)
            // Let the edit settle first: changing the text clears the last failure.
            try? await Task.sleep(for: .milliseconds(400))
            await model.link(usingCode: enteredCode)
        }
        #endif
    }

    /// Signed out of iCloud: said at the top for as long as it is true, since neither
    /// showing a code nor typing one can work until the user signs in.
    private func accountNotice(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "person.icloud")
                .foregroundStyle(Theme.warning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.md)
        .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: Theme.Space.sm) {
            Text("🐼💛")
                .font(.system(size: 52))
                .popIn(true)
            Text("Find your accountability buddy")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Share your code with a friend, or enter theirs. You'll keep each other going — and grow a little panda together.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Space.sm)
    }

    // MARK: My code

    private var myCodeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Label("Your code", systemImage: "qrcode")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            Text(model.myPairingCode)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .monospaced()
                .tracking(2)
                .foregroundStyle(Theme.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.md)
                .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.brand.opacity(0.30), lineWidth: 1)
                )
                .accessibilityLabel("Your pairing code is \(spelledOut(model.myPairingCode))")

            HStack(spacing: Theme.Space.sm) {
                Button {
                    UIPasteboard.general.string = model.myPairingCode
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.bordered)
                .tint(Theme.brand)

                ShareLink(item: shareMessage) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.brand)
            }

            // The waiting state, said out loud — without this the code-owner stares at a
            // static code wondering if anything is happening.
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Watching for your buddy — the moment they enter this code, you're connected. ✨")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .cardElevated()
    }

    // MARK: Connector

    private var connector: some View {
        HStack(spacing: Theme.Space.sm) {
            line
            Text("or enter theirs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()
            line
        }
    }
    private var line: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }

    // MARK: Enter buddy's code

    private var enterCodeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Label("Buddy's code", systemImage: "person.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            TextField("VITA-XXXX", text: $enteredCode)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospaced()
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($codeFieldFocused)
                .onSubmit { connect() }
                .padding(.vertical, Theme.Space.sm)
                .padding(.horizontal, Theme.Space.md)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(model.linkError == nil ? Theme.divider : Theme.warning, lineWidth: 1)
                )

            // Why the last attempt failed, and what to do. Each failure has its own sentence
            // (`BuddyViewModel.message(for:)`); none of them says "connected".
            if let error = model.linkError {
                Label {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.warning)
                }
                .accessibilityElement(children: .combine)
            }

            Button { connect() } label: {
                HStack(spacing: 8) {
                    if model.isLinking { ProgressView().tint(.white) }
                    Text(model.isLinking ? "Connecting…" : "Connect 💛")
                }
            }
            .buttonStyle(.primary)
            .disabled(model.isLinking || enteredCode.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(enteredCode.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1)

            Text(sharesFullStats
                 ? "Your buddy will see your streak, steps, water and workouts. \"Share my full stats\" is on, so they will also see your weight trend, calories, macros and what you ate today. You can turn that off in Settings."
                 : "Your buddy will see your streak, steps, water and workouts. They won't see your weight, calories or food unless you turn on \"Share my full stats\" in Settings.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Escape hatch: two failed attempts usually means connection trouble (iCloud,
            // network, backend), not typing. Offer the real diagnosis instead of an endless
            // "check the code" loop.
            if model.linkFailureCount >= 2 {
                Button {
                    diagRunning = true
                    Task {
                        diagReport = await model.diagnoseCloudKit()
                        diagRunning = false
                    }
                } label: {
                    Label(diagRunning ? "Checking the connection…" : "Still stuck? Check the connection",
                          systemImage: "stethoscope")
                        .font(.caption.weight(.semibold))
                }
                .disabled(diagRunning)
                if let diagReport {
                    Text(diagReport)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
        .cardElevated()
    }

    private func connect() {
        codeFieldFocused = false
        Task { await model.link(usingCode: enteredCode) }
    }

    // MARK: Helpers

    private var shareMessage: String {
        "Be my accountability buddy on Sprout! I'll SHOW my code, you TYPE it in (Buddy → Pair): \(model.myPairingCode) — that's all it takes 💛🐼"
    }

    private var backdrop: some View {
        Theme.background
            .overlay(alignment: .top) {
                RadialGradient(colors: [Theme.brand.opacity(0.10), .clear],
                               center: .top, startRadius: 0, endRadius: 360)
                    .frame(height: 400)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }

    /// Spell a code out for VoiceOver ("V, I, T, A, dash, …").
    private func spelledOut(_ code: String) -> String {
        code.map { ch -> String in ch == "-" ? "dash" : String(ch) }.joined(separator: ", ")
    }
}

/// The shared kind banner (used on pairing + hub). Tappable to dismiss.
struct BuddyBannerView: View {
    let banner: BuddyBanner
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: banner.systemImage)
                .foregroundStyle(banner.tint)
            Text(banner.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(banner.tint.opacity(0.35), lineWidth: 1)
        )
        .popIn(true)
        .onTapGesture { onDismiss() }
        .task(id: banner.id) {
            // Auto-dismiss after a few seconds so it never lingers.
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

#if DEBUG
/// DEBUG: `--demo-buddy-ui <unpair|unpair-confirmed|pairing-wrong|pairing-own|pairing-claimed|pairing-shape>`
/// puts a Buddy screen straight into a state that otherwise takes taps to reach.
enum BuddyDemoUI: Equatable {
    /// A pairing attempt that fails, and why.
    enum Attempt: String {
        case wrong, own, claimed, shape

        func code(mine: String) -> String {
            switch self {
            case .wrong:   return "VITA-9999"
            case .own:     return mine
            case .claimed: return LocalMockSyncService.claimedCode
            case .shape:   return "VITA-10OL"
            }
        }
    }

    /// The unpair confirmation, open.
    case unpair
    /// The confirmation's Unpair button, pressed.
    case unpairConfirmed
    /// The pairing screen after a failed attempt.
    case pairing(Attempt)

    static var requested: BuddyDemoUI? {
        let arguments = CommandLine.arguments
        guard let i = arguments.firstIndex(of: "--demo-buddy-ui"), i + 1 < arguments.count else { return nil }
        let value = arguments[i + 1]
        if value == "unpair" { return .unpair }
        if value == "unpair-confirmed" { return .unpairConfirmed }
        if value.hasPrefix("pairing-"), let attempt = Attempt(rawValue: String(value.dropFirst("pairing-".count))) {
            return .pairing(attempt)
        }
        return nil
    }
}
#endif

#Preview("Pairing") {
    NavigationStack {
        PairingView(model: BuddyViewModel(service: LocalMockSyncService(), myUserID: "me"))
    }
}
