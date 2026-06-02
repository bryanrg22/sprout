import SwiftUI

/// Shared, skin-aware visual vocabulary for nudges so every place a `NudgeKind` shows up —
/// the send rail, the "friendly nudge" cards, and the inbox — uses the SAME warm tint and a
/// matching soft "icon disc". One source of truth keeps the Buddy surface cohesive across
/// the cute (warm pastel) and cool (dark) skins.
///
/// All colors are Theme tokens, so the palette re-skins automatically. Tints are chosen so
/// the five kinds stay distinguishable in BOTH skins (coral/sage/amber/lavender/blue in cute;
/// lime/green/amber/purple/blue in cool).
extension NudgeKind {
    /// A per-kind accent. Health-positive intents map to warm, friendly hues — never alarm
    /// colors. (Matches the inbox/challenge-card tints so the whole feature reads as one set.)
    var tint: Color {
        switch self {
        case .cheer:      return Theme.brand     // the signature accent — generic encouragement
        case .checkIn:    return Theme.info       // soft blue — "thinking of you"
        case .flex:       return Theme.warning    // warm amber — celebrate a win
        case .proudOfYou: return Theme.fat        // lavender — heartfelt
        case .letsMove:   return Theme.positive   // sage/green — movement
        }
    }
}

/// A soft, tinted "icon disc" used by nudge chips, the friendly-nudge card, and inbox cards
/// so they all share one cute, cohesive look. A gently top-lit filled circle with a hairline
/// ring, holding either an SF symbol (in its own tint) or an emoji — warmer than a flat
/// circle, and identical across both skins.
struct NudgeIconDisc: View {
    /// What sits in the disc: a tinted SF symbol, or an emoji glyph.
    enum Glyph {
        case symbol(String)
        case emoji(String)
    }

    let glyph: Glyph
    let tint: Color
    var size: CGFloat = 46
    /// Pops a checkmark instead of the glyph (used by the send rail's "just sent!" flash).
    var showsCheck: Bool = false

    /// Convenience for the common SF-symbol case.
    init(systemImage: String, tint: Color, size: CGFloat = 46, showsCheck: Bool = false) {
        self.glyph = .symbol(systemImage)
        self.tint = tint
        self.size = size
        self.showsCheck = showsCheck
    }

    /// Convenience for an emoji glyph (e.g. the friendly-nudge cards).
    init(emoji: String, tint: Color, size: CGFloat = 46) {
        self.glyph = .emoji(emoji)
        self.tint = tint
        self.size = size
        self.showsCheck = false
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    // A soft top-lit wash in the kind's tint — reads as a cute, dimensional
                    // pill in both skins (lighter at the top, a touch deeper at the base).
                    LinearGradient(
                        colors: [tint.opacity(0.26), tint.opacity(0.14)],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay(Circle().strokeBorder(tint.opacity(0.32), lineWidth: 1))
                .frame(width: size, height: size)
            glyphView
        }
    }

    @ViewBuilder
    private var glyphView: some View {
        switch glyph {
        case .symbol(let name):
            // One Image whose symbol name is conditional, so check ⇄ icon morphs via the
            // symbol-replace transition (rather than swapping two separate views).
            Image(systemName: showsCheck ? "checkmark" : name)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolRenderingMode(.hierarchical)
        case .emoji(let e):
            // Emoji discs never show the "sent" check (only the tappable send-rail chips do).
            Text(e)
                .font(.system(size: size * 0.42))
        }
    }
}
