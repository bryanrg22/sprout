import SwiftUI

/// Shared "cuteness" vocabulary so every screen feels playful in the SAME way
/// (not five different interpretations). Layer these on top of the dark+lime Theme.
/// Everything respects Reduce Motion: when the user disables animation, the effects
/// degrade to instant/no-op rather than misbehaving.

// MARK: - Bounce / squish on tap

private struct BouncyPress: ViewModifier {
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduceMotion ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: pressed)
            .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {})
    }
}

extension View {
    /// Squishes inward while pressed, springs back on release — the "jelly" feel.
    /// Pair with a Button using `.buttonStyle(.plain)` for tappable cards/chips.
    func bouncyPress() -> some View { modifier(BouncyPress()) }
}

/// A playful primary button style: jelly squish + a soft lime glow.
struct JellyButtonStyle: ButtonStyle {
    var tint: Color = Theme.brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.0 : 0.35), radius: 10, y: 4)
    }
}
extension ButtonStyle where Self == JellyButtonStyle {
    static var jelly: JellyButtonStyle { JellyButtonStyle() }
    static func jelly(_ tint: Color) -> JellyButtonStyle { JellyButtonStyle(tint: tint) }
}

// MARK: - Pop-in (a single element springing in, e.g. an unlocked badge)

private struct PopIn: ViewModifier {
    let active: Bool
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .scaleEffect(active || reduceMotion ? 1 : 0.4)
            .opacity(active || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6).delay(delay), value: active)
    }
}
extension View {
    /// Springy scale-up-from-small entrance for celebratory elements.
    func popIn(_ active: Bool, delay: Double = 0) -> some View { modifier(PopIn(active: active, delay: delay)) }
}

// MARK: - Wiggle (gentle attention nudge, e.g. a happy mascot)

private struct Wiggle: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        // `.phaseAnimator` drives the loop as a PURE transform. The old
        // `.animation(.repeatForever, value:)` + `.onAppear` pattern could latch onto a stale
        // layout position captured mid-transition and animate the view around it forever — which
        // made icons drift wildly out of place (the Workouts empty-state dumbbell floating up off
        // the card / into the status bar). phaseAnimator can't drag layout, so it stays put.
        let on = active && !reduceMotion
        return content.phaseAnimator([false, true]) { view, flipped in
            view.rotationEffect(.degrees(on ? (flipped ? 2.5 : -2.5) : 0))
        } animation: { _ in on ? .easeInOut(duration: 0.5) : nil }
    }
}
extension View {
    /// A slow back-and-forth tilt — adorable for a happy companion/idle state.
    func wiggle(_ active: Bool = true) -> some View { modifier(Wiggle(active: active)) }
}

// MARK: - Breathing (gentle scale pulse, "alive" feel)

private struct Breathing: ViewModifier {
    var active: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        // See Wiggle: phaseAnimator keeps the pulse a pure transform, so it can never drag layout
        // (the old repeatForever-via-onAppear pattern could, causing animated icons to drift).
        // `active` lets a caller hold the idle until the view has SETTLED, so it never animates in
        // from a mid-transition position when the screen first appears.
        let on = active && !reduceMotion
        return content.phaseAnimator([false, true]) { view, big in
            view.scaleEffect(big && on ? 1.04 : 1.0)
        } animation: { _ in on ? .easeInOut(duration: 2.2) : nil }
    }
}
extension View {
    func breathing(_ active: Bool = true) -> some View { modifier(Breathing(active: active)) }
}

// MARK: - Confetti

/// A one-shot confetti burst. Bump `trigger` (e.g. on an achievement unlock or a
/// goal hit) to fire. Cheap: a fixed set of emoji/shape bits, no dependency.
struct ConfettiBurst: View {
    var trigger: Int
    var emojis: [String] = ["🎉", "✨", "💚", "⭐️", "🌟"]
    @State private var bits: [Bit] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Bit: Identifiable {
        let id = UUID()
        let emoji: String
        let xJitter: CGFloat
        let rotation: Double
        let scale: CGFloat
        let delay: Double
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(bits) { bit in
                    Text(bit.emoji)
                        .font(.system(size: 22 * bit.scale))
                        .modifier(FallingBit(width: geo.size.width, height: geo.size.height, bit: bit))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { fire() }
    }

    private func fire() {
        guard !reduceMotion else { return }
        bits = (0..<22).map { _ in
            Bit(emoji: emojis.indices.isEmpty ? "🎉" : emojis[bitIndex()],
                xJitter: .random(in: -1...1),
                rotation: .random(in: -180...180),
                scale: .random(in: 0.7...1.3),
                delay: .random(in: 0...0.15))
        }
        // Clear after the animation completes so the view stays light.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { bits = [] }
    }
    // Avoid Int.random (deterministic-safe enough for confetti); cycle by count.
    @State private var counter = 0
    private func bitIndex() -> Int { Int.random(in: 0..<emojis.count) }
}

private struct FallingBit: ViewModifier {
    let width: CGFloat
    let height: CGFloat
    let bit: ConfettiBurst.Bit
    @State private var fallen = false
    func body(content: Content) -> some View {
        content
            .position(x: width * (0.5 + bit.xJitter * 0.45),
                      y: fallen ? height + 40 : -40)
            .rotationEffect(.degrees(fallen ? bit.rotation : 0))
            .opacity(fallen ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: 1.4).delay(bit.delay)) { fallen = true }
            }
    }
}
