import SwiftUI

/// Vita's face — the **Sprout mascot** (the app's seedling), in a soft, theme-tinted disc.
///
/// This replaces the old generic SF-Symbol heart so the coach has a real, branded identity
/// that matches the app's name and icon. It reuses the same pixel-art seedling the app icon
/// is built from (`PixelSprout`) rendered through `PixelArtView`, so Vita, the icon, and the
/// brand all read as one character. Theme-tinted via `Theme.brand*`, so she fits both the
/// cute (cream/coral) and cool (dark/lime) skins.
struct VitaAvatar: View {
    var size: CGFloat = 40
    /// A tiny sparkle accent off her shoulder (skip it for very small placements).
    var showsSparkle: Bool = true

    var body: some View {
        ZStack {
            Circle().fill(Theme.brandSoft)
            Circle().strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1)

            // The seedling, inset so it sits comfortably inside the disc.
            PixelArtView(rows: PixelSprout.rows, palette: PixelSprout.palette)
                .padding(size * 0.18)

            if showsSparkle {
                Image(systemName: "sparkle")
                    .font(.system(size: max(8, size * 0.2), weight: .bold))
                    .foregroundStyle(Theme.brand)
                    .offset(x: size * 0.34, y: -size * 0.34)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.brand.opacity(0.25), radius: size * 0.1, x: 0, y: 2)
        .accessibilityHidden(true)
    }
}
