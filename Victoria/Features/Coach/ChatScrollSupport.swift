import SwiftUI

/// Scroll bookkeeping for the chat that must not live in view state: reading a scroll
/// offset from `@State` would re-render the whole conversation on every frame of a scroll.
final class ChatScrollBox {
    /// How far the view is from the newest message, written on every scroll frame. Zero (or
    /// less) at the newest message.
    var distanceFromNewest: CGFloat = 0
    /// Whether the reader is within `oldestTrigger` of the oldest loaded message.
    var isNearOldest = false

    /// DEBUG launches can keep the "load earlier" row on screen instead of loading at once.
    static var autoLoadDisabled = false

    /// How close to the newest message counts as "at the newest" (about two short bubbles).
    static let newestSlack: CGFloat = 120
    /// How close to the oldest loaded message starts loading the page before it.
    static let oldestTrigger: CGFloat = 240

    // The list is FLIPPED (CoachView.conversation): the newest message is the START of the
    // content (offset 0 side) and the oldest loaded one is its END. `ScrollGeometry` is in the
    // scroll view's own, flipped, coordinates. At the content start
    // `contentOffset.y == -contentInsets.top`; at its end
    // `contentOffset.y + visibleRect.height == contentSize.height + contentInsets.bottom`
    // (`visibleRect` is the whole frame, insets included).

    static func distanceFromNewest(_ geometry: ScrollGeometry) -> CGFloat {
        distanceFromNewest(startInset: geometry.contentInsets.top, offset: geometry.contentOffset.y,
                           viewHeight: geometry.visibleRect.height)
    }

    static func isNearNewest(_ geometry: ScrollGeometry) -> Bool {
        nearNewest(startInset: geometry.contentInsets.top, offset: geometry.contentOffset.y,
                   viewHeight: geometry.visibleRect.height)
    }

    static func isNearOldest(_ geometry: ScrollGeometry) -> Bool {
        nearOldest(contentHeight: geometry.contentSize.height, endInset: geometry.contentInsets.bottom,
                   offset: geometry.contentOffset.y, viewHeight: geometry.visibleRect.height)
    }

    /// Points scrolled away from the newest message. Zero before the view has a size.
    static func distanceFromNewest(startInset: CGFloat, offset: CGFloat, viewHeight: CGFloat) -> CGFloat {
        guard viewHeight > 0 else { return 0 }
        return offset + startInset
    }

    /// Whether the newest message is on screen (within `newestSlack`). A view that has not
    /// been sized yet counts as at the newest: that is where the chat opens.
    static func nearNewest(startInset: CGFloat, offset: CGFloat, viewHeight: CGFloat) -> Bool {
        distanceFromNewest(startInset: startInset, offset: offset, viewHeight: viewHeight) < newestSlack
    }

    /// Whether the reader has scrolled to the oldest loaded message. Never true before the
    /// view has a size (the first layout passes run with none), and never true for content
    /// that does not fill the view, where there is nothing to scroll.
    static func nearOldest(contentHeight: CGFloat, endInset: CGFloat, offset: CGFloat, viewHeight: CGFloat) -> Bool {
        guard viewHeight > 0, contentHeight > viewHeight else { return false }
        return (contentHeight + endInset) - (offset + viewHeight) < oldestTrigger
    }
}

extension View {
    /// Turn a view upside down (vertically only). Applied to the chat's scroll view and again
    /// to each row, so the rows read the right way up in a list that grows from the bottom.
    func chatFlipped() -> some View {
        scaleEffect(x: 1, y: -1, anchor: .center)
    }

    /// iOS 26 blurs scroll content under the bars (the scroll edge effect). Its mask is laid
    /// out in the scroll view's own coordinates, so in the flipped chat it comes out inverted:
    /// the whole conversation blurred and the text under the title sharp (seen on iOS 26.4).
    /// The chat hides it and draws its own bar backgrounds instead.
    @ViewBuilder
    func chatEdgeEffectsHidden() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}

