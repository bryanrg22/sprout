import SwiftUI

/// A rare "guest star" drop-by — ONE visiting artist (Peso / Tito / …) shown in its OWN
/// compact card right below the companion, so Sprout is never displaced. The guest
/// auto-greets with their signature line on arrival; tap to hear another. Only ever one
/// guest at a time (the dashboard decides who, via `CameoDirector`).
struct GuestCameoCard: View {
    let artist: ArtistCameo

    @State private var appeared = false
    @State private var blink = false
    /// The line currently shown beside the guest; nil = just the "tap to say hi" hint.
    @State private var speech: String?
    /// Supersedes a previous auto-hide timer so a fresh tap restarts the window.
    @State private var speechToken = 0
    /// A light haptic on each tap.
    @State private var talkTrigger = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let blinkTimer = Timer.publish(every: 3.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            // The visiting artist — always cheerful (guests only drop by on a good day),
            // blinking on the shared timer; PNG-frame guests also open their mouth while talking.
            artist.portrait(blinking: blink, talking: speech != nil)
                .frame(width: 92, height: 104)
                .breathing()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(artist.displayName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    guestTag
                }
                // While speaking, the line shows as a little quote bubble; otherwise a hint.
                if let speech {
                    Text(speech)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule(style: .continuous).fill(Theme.cardRaised))
                        .overlay(Capsule(style: .continuous).strokeBorder(Theme.brand.opacity(0.28), lineWidth: 1))
                        .id(speech)   // re-pop when the line changes on a quick re-tap
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Text("stopped by to hype you up — tap to say hi! 🎤")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { talk() }
        .sensoryFeedback(.impact(weight: .light), trigger: talkTrigger)
        .cardElevated(padding: Theme.Space.md)
        .bouncyPress()
        .popIn(appeared)
        .onAppear {
            appeared = true
            autoGreet()
        }
        .onReceive(blinkTimer) { _ in doBlink() }
        .fontDesign(.rounded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(artist.displayName), a guest star, stopped by. Tap to hear them.")
    }

    /// A little "guest star" badge beside the name.
    private var guestTag: some View {
        Text("✨ Guest")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.brand)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.brand.opacity(0.16)))
            .overlay(Capsule().strokeBorder(Theme.brand.opacity(0.30), lineWidth: 1))
    }

    /// Tap → a fresh catchphrase (never an immediate repeat).
    private func talk() { say(artist.randomLine(excluding: speech)) }

    /// On arrival, greet with the artist's signature opener a beat after the card springs in.
    private func autoGreet() {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                guard speech == nil else { return }   // user tapped first — don't clobber their line
                say(artist.lines.first ?? "")
            }
        }
    }

    /// Show one line, hold ~5s, then fade. A newer line supersedes the prior timer.
    private func say(_ phrase: String) {
        talkTrigger += 1
        speechToken += 1
        let token = speechToken
        withAnimation(.spring(response: 0.34, dampingFraction: 0.6)) { speech = phrase }
        Task {
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                guard speechToken == token else { return }
                withAnimation(.easeOut(duration: 0.3)) { speech = nil }
            }
        }
    }

    private func doBlink() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.09)) { blink = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            withAnimation(.easeInOut(duration: 0.12)) { blink = false }
        }
    }
}
