import SwiftUI

/// Scroll bookkeeping for the chat that must not live in view state: reading a scroll
/// offset from `@State` would re-render the whole conversation on every frame of a scroll.
final class ChatScrollBox {
    /// How far the newest message is below the bottom edge of the view, written on every
    /// scroll frame. Zero (or less) at the very bottom.
    var distanceFromBottom: CGFloat = 0
    /// Whether the reader is within `topTrigger` of the top of what is loaded.
    var isNearTop = false

    /// DEBUG launches can keep the "load earlier" row on screen instead of loading at once.
    static var autoLoadDisabled = false

    /// How close to the newest message counts as "at the bottom" (about two short bubbles).
    static let bottomSlack: CGFloat = 120
    /// How close to the top of the loaded messages starts loading the page before them.
    static let topTrigger: CGFloat = 240

    // `ScrollGeometry.visibleRect` is the scroll view's whole frame in content coordinates,
    // bars and input bar included; `containerSize` (and `bounds`) is that frame minus the
    // insets. Measured on iOS 26.4 with the input bar as a bottom safe-area inset: visible
    // 874 pt, insets 116 + 193, container 565, and at the very bottom
    // `contentOffset.y + visibleRect.height == contentSize.height + contentInsets.bottom`.

    static func distanceFromBottom(_ geometry: ScrollGeometry) -> CGFloat {
        distanceFromBottom(contentHeight: geometry.contentSize.height, bottomInset: geometry.contentInsets.bottom,
                           offset: geometry.contentOffset.y, viewHeight: geometry.visibleRect.height)
    }

    static func isNearBottom(_ geometry: ScrollGeometry) -> Bool {
        nearBottom(contentHeight: geometry.contentSize.height, bottomInset: geometry.contentInsets.bottom,
                   offset: geometry.contentOffset.y, viewHeight: geometry.visibleRect.height)
    }

    static func isNearTop(_ geometry: ScrollGeometry) -> Bool {
        nearTop(contentHeight: geometry.contentSize.height, topInset: geometry.contentInsets.top,
                offset: geometry.contentOffset.y, viewHeight: geometry.visibleRect.height)
    }

    /// Points of content below the bottom edge of the view. Zero before the view has a size.
    static func distanceFromBottom(contentHeight: CGFloat, bottomInset: CGFloat, offset: CGFloat, viewHeight: CGFloat) -> CGFloat {
        guard viewHeight > 0 else { return 0 }
        return (contentHeight + bottomInset) - (offset + viewHeight)
    }

    /// Whether the newest message is on screen (within `bottomSlack`). A view that has not
    /// been sized yet counts as at the bottom: that is where the chat opens.
    static func nearBottom(contentHeight: CGFloat, bottomInset: CGFloat, offset: CGFloat, viewHeight: CGFloat) -> Bool {
        distanceFromBottom(contentHeight: contentHeight, bottomInset: bottomInset,
                           offset: offset, viewHeight: viewHeight) < bottomSlack
    }

    /// Whether the reader has scrolled to the top of what is loaded. Never true before the
    /// view has a size (the first layout passes run with none), and never true for content
    /// that does not fill the view, where there is nothing to scroll.
    static func nearTop(contentHeight: CGFloat, topInset: CGFloat, offset: CGFloat, viewHeight: CGFloat) -> Bool {
        guard viewHeight > 0, contentHeight > viewHeight else { return false }
        return offset + topInset < topTrigger
    }
}
