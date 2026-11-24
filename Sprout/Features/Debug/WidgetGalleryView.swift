import SwiftUI
import WidgetKit

/// DEBUG-only preview of the widget views at true widget sizes, so we can verify
/// the design via screenshots (the Simulator has no CLI way to place a real
/// widget). Shown when the app is launched with `--widget-preview`.
///
/// Renders EVERY widget in BOTH skins — Cute (warm light) and Cool
/// (Bryan · dark) — because the widget runs in a separate process and must look
/// right for both users. Each skin section sets `Theme.current` to that skin so the
/// tiles + widget colors resolve exactly as they will on-device.
struct WidgetGalleryView: View {
    static var isRequested: Bool { CommandLine.arguments.contains("--widget-preview") }

    /// The cute sample (warm light skin, cute companion).
    private var cuteSnap: WidgetSnapshot {
        var s = WidgetSnapshot.placeholder
        s.themeStyleRaw = ThemeStyle.cute.rawValue
        s.companionAvatarRaw = "victoria"
        s.name = "Sam"
        return s
    }

    /// The cool/Bryan sample (dark skin, Bryan companion, gaining → rate is positive).
    private var coolSnap: WidgetSnapshot {
        var s = WidgetSnapshot.placeholder
        s.themeStyleRaw = ThemeStyle.cool.rawValue
        s.companionAvatarRaw = "bryan"
        s.name = "Alex"
        s.ratePerWeek = 0.4          // gaining, so the trend arrow/colour flips
        return s
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Widget Gallery").font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                skinSection("Cute", skin: .cute, snap: cuteSnap)
                skinSection("Cool · Bryan", skin: .cool, snap: coolSnap)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.5))   // neutral grey so BOTH skins are judged fairly
    }

    /// All families for one skin. Sets `Theme.current` up front so every Theme color
    /// (incl. the tile backgrounds) resolves in this skin, mirroring the live widget.
    @ViewBuilder
    private func skinSection(_ title: String, skin: ThemeSkin, snap: WidgetSnapshot) -> some View {
        let _ = (Theme.current = skin)
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased()).font(.headline.weight(.heavy)).tracking(1)

            group("Home · Small") {
                tile(170) { CompanionView(snap: snap, family: .systemSmall) }
                tile(170) { WeightTrendView(snap: snap, family: .systemSmall) }
            }
            group("Home · Medium · Companion (hero)") {
                tile(360, 170) { CompanionView(snap: snap, family: .systemMedium) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.bold)).tracking(1)
                .foregroundStyle(.white.opacity(0.7))
            // Each row scrolls horizontally so wide rows (e.g. 3 small widgets) never spill
            // off-screen — and, crucially, never force the whole page to center-shift left.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) { content() }
                    .padding(.trailing, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // A home-screen widget tile — uses the active skin's container background, exactly
    // like the real `.containerBackground(Theme.background, …)`.
    private func tile<Content: View>(_ w: CGFloat, _ h: CGFloat? = nil,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)   // simulate iOS 17's built-in 16pt widget content margin, so this
                           // preview matches how the real on-device widget is inset
            .frame(width: w, height: h ?? w)
            .background(Theme.widgetBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1))
    }

    // A lock-screen accessory tile (shown on a faux wallpaper, light vibrancy). Lock
    // widgets are system-tinted, so they look the same regardless of app skin.
    private func accessoryTile<Content: View>(_ w: CGFloat, _ h: CGFloat,
                                              @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(.white)
            .frame(width: w, height: h)
            .padding(8)
            .background(
                LinearGradient(colors: [Color(hex: 0x2A3550), Color(hex: 0x10151F)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }
}
