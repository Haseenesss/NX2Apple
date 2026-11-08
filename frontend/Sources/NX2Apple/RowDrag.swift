import AppKit
import SwiftUI

/// A card dragged along a horizontal row with the mouse after a long press, as icons are moved on an iPhone's home screen (#937):
/// console mode's row of games and the desktop library's collection. The card follows the pointer. When its middle passes the middle
/// of the card next to it, `step` says to move it one place, and the cards make room. Near either end of the visible row `onEdge`
/// is called every so often, to bring in the next card that way. Positions are in the row's own coordinate space (the scroll view's,
/// which does not scroll with the cards), so the card stays under the pointer while the row scrolls.
@MainActor final class RowDrag: ObservableObject {
    @Published private(set) var id: String?
    @Published private(set) var x: CGFloat = 0   // the pointer now
    private var startX: CGFloat = 0              // the pointer when the card was picked up
    private var startMinX: CGFloat = 0           // the card's place then
    private var width: CGFloat = 0               // the visible row
    private var anchored = false                 // startX is the pointer's: a long press ends before the first drag event
    private var timer: Timer?
    /// How near an end of the visible row the pointer scrolls it.
    let edge: CGFloat = 80
    var onEdge: (Int) -> Void = { _ in }

    var active: Bool { id != nil }

    /// `x` nil: the long press has ended but the pointer has not been reported yet; the first `moved` anchors it.
    func begin(_ id: String, frame: CGRect?, at x: CGFloat?, rowWidth: CGFloat) {
        self.id = id
        anchored = x != nil
        startX = x ?? 0
        self.x = startX
        startMinX = frame?.minX ?? startX
        width = rowWidth
        Self.haptic(.generic)
    }

    func moved(to x: CGFloat, rowWidth: CGFloat) {
        guard active else { return }
        if !anchored { anchored = true; startX = x }
        self.x = x
        width = rowWidth
        let way = edgeDirection
        if way == 0 { timer?.invalidate(); timer = nil }
        else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.32, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { if let self, self.edgeDirection != 0 { self.onEdge(self.edgeDirection) } }
            }
            onEdge(way)
        }
    }

    func end() {
        timer?.invalidate(); timer = nil
        id = nil
    }

    /// Which way the row scrolls now: the pointer near its left end (-1), its right end (+1), or neither (0).
    var edgeDirection: Int { !active ? 0 : (x < edge ? -1 : (x > width - edge ? 1 : 0)) }

    /// How far the card is drawn from its place in the layout, so it stays under the pointer as the cards and the row move.
    func offset(for id: String, frames: [String: CGRect]) -> CGFloat {
        guard id == self.id, let frame = frames[id] else { return 0 }
        return startMinX + (x - startX) - frame.minX
    }

    /// The place the card should go now, one at a time: +1 when its middle has passed the middle of the next card, -1 the previous
    /// one, else 0. `order` is the row as shown.
    func step(order: [String], frames: [String: CGRect]) -> Int {
        guard let id, let at = order.firstIndex(of: id), let frame = frames[id] else { return 0 }
        let middle = startMinX + (x - startX) + frame.width / 2
        if at + 1 < order.count, let next = frames[order[at + 1]], middle > next.midX { return 1 }
        if at > 0, let previous = frames[order[at - 1]], middle < previous.midX { return -1 }
        return 0
    }

    /// The card to scroll to so the row moves one card `way`: the first one past the visible end, nil when there is none.
    static func nextCard(_ way: Int, order: [String], frames: [String: CGRect], rowWidth: CGFloat) -> String? {
        way > 0 ? order.first { (frames[$0]?.maxX ?? 0) > rowWidth - 4 } : order.last { (frames[$0]?.minX ?? 0) < 4 }
    }

    /// A tap of the trackpad when a card is picked up and when it passes another (no effect with a mouse).
    static func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

/// Where each card of a row is, by id, in the row's coordinate space (RowDrag).
struct RowFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { _, new in new } }
}
