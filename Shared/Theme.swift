import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue:  Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

/// Which user's look the app is wearing. Same layout / flow everywhere — only the
/// palette + color scheme change.
enum ThemeStyle: String, Codable, CaseIterable {
    case cute   // Victoria — soft, warm, pastel (light)
    case cool   // Bryan — bold, dark, electric (dark)

    var skin: ThemeSkin { self == .cool ? .cool : .cute }
    var label: String { self == .cute ? "Cute" : "Cool" }
    var blurb: String {
        self == .cute ? "Soft, warm & pastel" : "Bold, dark & electric"
    }
}

/// A full color palette ("skin"). The app ships two; everything reads its colors
/// from `Theme.current`, so swapping one value re-skins the whole UI.
struct ThemeSkin {
    let brand, brandDeep, brandSoft: Color
    let positive, warning, info: Color
    let calories, protein, carbs, fat, water: Color
    let background, card, cardRaised: Color
    let textPrimary, textSecondary, divider: Color
    let colorScheme: ColorScheme

    /// BOLD · DARK · ELECTRIC — near-black canvas, high-voltage lime. (Bryan)
    static let cool = ThemeSkin(
        brand:      Color(hex: 0xC6FF3D),
        brandDeep:  Color(hex: 0x8BE000),
        brandSoft:  Color(hex: 0x1E2A10),
        positive:   Color(hex: 0x57E389),
        warning:    Color(hex: 0xFFB23E),
        info:       Color(hex: 0x4DA3FF),
        calories:   Color(hex: 0xC6FF3D),
        protein:    Color(hex: 0x4DA3FF),
        carbs:      Color(hex: 0xFFB23E),
        fat:        Color(hex: 0xC78BFF),
        water:      Color(hex: 0x35D6E8),
        background: Color(hex: 0x0A0C0B),
        card:       Color(hex: 0x16191B),
        cardRaised: Color(hex: 0x1C2023),
        textPrimary:   Color(hex: 0xF2F5F3),
        textSecondary: Color(hex: 0x8C948D),
        divider:    Color.white.opacity(0.08),
        colorScheme: .dark)

    /// SOFT · WARM · PASTEL — cream canvas, cozy coral + sage. (Victoria)
    static let cute = ThemeSkin(
        brand:      Color(hex: 0xF2976F),   // warm coral
        brandDeep:  Color(hex: 0xE07A50),
        brandSoft:  Color(hex: 0xFCE8DD),   // peach wash for tinted surfaces
        positive:   Color(hex: 0x8BBE82),   // sage
        warning:    Color(hex: 0xE0A23C),   // warm amber
        info:       Color(hex: 0x7FB2E8),   // soft blue
        calories:   Color(hex: 0xF2976F),   // coral hero
        protein:    Color(hex: 0x7FA9E0),   // soft blue
        carbs:      Color(hex: 0xE6B45A),   // butter
        fat:        Color(hex: 0xC2A0E0),   // lavender
        water:      Color(hex: 0x73C9D6),   // soft cyan
        background: Color(hex: 0xF8F1E7),   // warm cream
        card:       Color(hex: 0xFFFCF6),   // soft cream-white
        cardRaised: Color(hex: 0xFFFFFF),
        textPrimary:   Color(hex: 0x483F37),   // warm dark brown
        // Was 0x9A8C7C: 3.2:1 on the card and 2.9:1 on the page, under WCAG's 4.5:1 for body
        // text. 0x76695B is the same warm brown, darker: 5.2:1 and 4.75:1 (EVAL_REPORT 29).
        textSecondary: Color(hex: 0x76695B),
        divider:    Color.black.opacity(0.06),
        colorScheme: .light)
}

/// The app's design tokens. COLORS read from the active `Theme.current` skin (so the
/// whole UI re-skins by swapping one value); spacing/radius are layout constants.
enum Theme {
    /// The active skin. Set once per launch from the profile (see RootView). Defaults
    /// to `.cool` so the widget extension (which never sets it) stays on-brand dark.
    static var current: ThemeSkin = .cool

    // Brand
    static var brand: Color      { current.brand }
    static var brandDeep: Color  { current.brandDeep }
    static var brandSoft: Color  { current.brandSoft }

    // Semantics
    static var positive: Color   { current.positive }
    static var warning: Color    { current.warning }
    static var info: Color       { current.info }

    // Metric colors
    static var calories: Color   { current.calories }
    static var protein: Color    { current.protein }
    static var carbs: Color      { current.carbs }
    static var fat: Color        { current.fat }
    static var water: Color      { current.water }

    // Surfaces
    static var background: Color { current.background }
    static var card: Color       { current.card }
    static var cardRaised: Color { current.cardRaised }

    /// Widget container surface. Matches `background` for the light (cute) skin, but on the
    /// dark (cool) skin it uses a softer charcoal instead of the near-black canvas — the
    /// pure-black background reads too harsh in a small home-screen tile, so widgets get a
    /// more elevated, Google-Calendar-style gray.
    static var widgetBackground: Color {
        current.colorScheme == .dark ? Color(hex: 0x2A2A2E) : current.background
    }

    // Text + lines (in the shared file so BOTH app + widget targets resolve them)
    static var textPrimary: Color   { current.textPrimary }
    static var textSecondary: Color { current.textSecondary }
    static var divider: Color       { current.divider }

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brand, brandDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var positiveGradient: LinearGradient {
        LinearGradient(colors: [positive, positive.opacity(0.7)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Spacing / radius (layout constants — identical across skins)
    enum Space { static let xs: CGFloat = 6; static let sm: CGFloat = 10; static let md: CGFloat = 16; static let lg: CGFloat = 22; static let xl: CGFloat = 30 }
    enum Radius { static let sm: CGFloat = 10; static let md: CGFloat = 18; static let lg: CGFloat = 26; static let pill: CGFloat = 999 }
}

extension View {
    /// Standard card surface (skin-aware hairline for gentle depth).
    func card(padding: CGFloat = Theme.Space.md) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
    }
}
