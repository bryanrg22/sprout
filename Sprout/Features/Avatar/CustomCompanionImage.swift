import SwiftUI
import UIKit

/// The person's own character, drawn wherever a built-in character would be.
///
/// Version 1 has ONE image per person (the owner's decision), so this view takes no mood
/// and no blink: where `PixelCuteView` / `PixelBryanView` swap frames, this shows the
/// same picture.
///
/// The PNG comes from `UserProfile.customAvatarPNG`. A view that has the profile passes
/// it; the buddy and companion views that only know a `CompanionAvatar` read it from the
/// environment, where `RootView` puts it once for the whole app.
struct CustomCompanionImage: View {
    /// Pass the PNG when the caller has it; nil reads the environment.
    var png: Data? = nil
    @Environment(\.customCompanionPNG) private var environmentPNG

    var body: some View {
        if let data = png ?? environmentPNG, let image = CustomCompanionImageCache.image(for: data) {
            Image(uiImage: image)
                .interpolation(.none)          // hard pixel edges, like the grid characters
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)     // the surrounding card supplies the spoken label
        } else {
            // `CompanionAvatar.resolve` never yields `.custom` without an image, so this is
            // only reachable when a view is drawn outside the app's root. Say nothing about
            // anyone rather than draw someone else's character.
            Image(systemName: "leaf.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Theme.textSecondary)
                .padding(12)
                .accessibilityHidden(true)
        }
    }
}

private struct CustomCompanionPNGKey: EnvironmentKey {
    static let defaultValue: Data? = nil
}

extension EnvironmentValues {
    /// The current profile's custom character PNG, or nil when it has none.
    var customCompanionPNG: Data? {
        get { self[CustomCompanionPNGKey.self] }
        set { self[CustomCompanionPNGKey.self] = newValue }
    }
}

/// Decodes the character once and keeps it: the same `Data` is asked for on every redraw
/// of every view that shows the companion (the companion card redraws on a blink timer).
/// One entry is enough, since there is one profile.
enum CustomCompanionImageCache {
    private static let lock = NSLock()
    private static var last: (data: Data, image: UIImage)?

    static func image(for data: Data) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        if let last, last.data == data { return last.image }
        guard let image = UIImage(data: data) else { return nil }
        last = (data, image)
        return image
    }
}
