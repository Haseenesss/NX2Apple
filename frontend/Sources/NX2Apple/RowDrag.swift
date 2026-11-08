import AppKit
import SwiftUI

/// A card dragged along a horizontal row with the mouse after a long press, as icons are moved on an iPhone's home screen (#937):
/// console mode's row of games and the desktop library's collection.
///
/// The long press is SwiftUI's; from then on the drag follows AppKit's own mouse events (a local monitor for drags and the release),
/// not a SwiftUI drag gesture: picking a card up changes the row's layout (console mode starts arranging), and SwiftUI cancelled the
/// gesture then, so the release never came and the card stayed picked up.
///
/// The card follows the pointer. When its middle passes the middle of the card next to it, `step` says to move it one place and the
/// cards make room; the place it moves to is taken at once (`stepped`), not one frame later when the new frames come back, so the card
/// does not jump. Near either end of the visible row `onEdge` is called every so often, to bring in the next card that way. Positions
/// are in the row's own coordinate space (the scroll view's, which does not scroll with the cards).
@MainActor final class RowDrag: ObservableObject {
    @Published private(set) var id: String?
    @Published private(set) var x: CGFloat = 0   // the pointer now, in the row
    /// The card under a long press that has not finished yet: it grows a little, so it feels picked up.
    @Published var pressing: String?
    private var startX: CGFloat = 0              // the pointer when the card was picked up
    private var startMinX: CGFloat = 0           // the card's place then
    private var placeMinX: CGFloat = 0           // where the card's place is now (moved by a step before its frame comes back)
    private var waitingForLayout = false         // a step was taken and the frames have not come back yet
    private var rowOriginX: CGFloat = 0          // the row's left edge in the window
    private var width: CGFloat = 0               // the visible row
    private var timer: Timer?
    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    private var onMove: () -> Void = {}
    private var onRelease: () -> Void = {}
    /// How near an end of the visible row the pointer scrolls it.
    let edge: CGFloat = 80
    var onEdge: (Int) -> Void = { _ in }

    var active: Bool { id != nil }

    /// The long press has picked up `id`. `pointerX` is the pointer in the row (nil: read from the window); `rowOriginX` is where the
    /// row starts in the window. `onMove` runs after each move of the pointer, `onRelease` when the button comes up.
    func begin(_ id: String, frame: CGRect?, rowOriginX: CGFloat, rowWidth: CGFloat, pointerX: CGFloat? = nil,
               onMove: @escaping () -> Void = {}, onRelease: @escaping () -> Void = {}) {
        end()
        self.id = id
        pressing = nil
        self.rowOriginX = rowOriginX
        width = rowWidth
        let windowX = (NSApp.keyWindow ?? NSApp.mainWindow)?.mouseLocationOutsideOfEventStream.x
        startX = pointerX ?? windowX.map { $0 - rowOriginX } ?? frame?.midX ?? 0
        x = startX
        startMinX = frame?.minX ?? startX
        placeMinX = startMinX
        waitingForLayout = false
        self.onMove = onMove
        self.onRelease = onRelease
        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.moved(to: event.locationInWindow.x - (self?.rowOriginX ?? 0)) }
            return event
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.release() }
            return event
        }) { monitors.append(m) }
        // a release this app does not see (another app came forward mid-drag) still puts the card down
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.release() }
        }) { monitors.append(m) }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.release() }
        }
        Self.haptic(.generic)
    }

    /// The pointer moved, in the row's coordinates.
    func moved(to x: CGFloat) {
        guard active else { return }
        self.x = x
        let way = edgeDirection
        if way == 0 { timer?.invalidate(); timer = nil }
        else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.32, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if NSEvent.pressedMouseButtons & 1 == 0 { self.release(); return }   // the button came up where no event told us
                    if self.edgeDirection != 0 { self.onEdge(self.edgeDirection) }
                }
            }
            onEdge(way)
        }
        onMove()
    }

    /// The button came up: the card is put down where it is.
    func release() {
        guard active else { return }
        let done = onRelease
        end()
        done()
    }

    /// Stops following the mouse, without putting anything down (`release` does).
    func end() {
        timer?.invalidate(); timer = nil
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        onMove = {}; onRelease = {}
        id = nil
    }

    /// The row moved in the window or changed width while a card is held: picking a game up in console mode starts arranging, which
    /// widens the scroll area to the screen's edges. What was measured in the old row is taken into the new one, so the card stays
    /// under the pointer (it had jumped by the page margin).
    func rowMoved(originX: CGFloat, rowWidth: CGFloat) {
        width = rowWidth
        guard active, originX != rowOriginX else { rowOriginX = originX; return }
        let shift = rowOriginX - originX
        rowOriginX = originX
        startX += shift; x += shift; startMinX += shift
    }

    /// Which way the row scrolls now: the pointer near its left end (-1), its right end (+1), or neither (0).
    var edgeDirection: Int { !active ? 0 : (x < edge ? -1 : (x > width - edge ? 1 : 0)) }

    /// How far the card is drawn from its place, so it stays under the pointer as the cards and the row move.
    func offset(for id: String) -> CGFloat { id == self.id ? startMinX + (x - startX) - placeMinX : 0 }

    /// The frames came back: the card's place is where the layout put it.
    func framesChanged(_ frames: [String: CGRect]) {
        guard let id, let frame = frames[id] else { return }
        placeMinX = frame.minX
        waitingForLayout = false
    }

    /// The place the card should go now, one at a time: +1 when its middle has passed the middle of the next card, -1 the previous
    /// one, else 0. `order` is the row as shown. Nothing while a step is waiting for its frames.
    func step(order: [String], frames: [String: CGRect]) -> Int {
        guard let id, !waitingForLayout, let at = order.firstIndex(of: id), let frame = frames[id] else { return 0 }
        let middle = startMinX + (x - startX) + frame.width / 2
        if at + 1 < order.count, let next = frames[order[at + 1]], middle > next.midX { return 1 }
        if at > 0, let previous = frames[order[at - 1]], middle < previous.midX { return -1 }
        return 0
    }

    /// A step was taken: the card's place is now where the card it passed was (`neighbour`, its frame before the step).
    func stepped(into neighbour: CGRect?, step: Int, frame: CGRect?) {
        guard let neighbour, let frame else { return }
        // the card takes the room the other card had: to the right it ends where that card ended, to the left it starts where it started
        placeMinX = step > 0 ? neighbour.maxX - frame.width : neighbour.minX
        waitingForLayout = true
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

/// Where a row starts in the window (its scroll view's left edge), so the mouse's window position can be read in the row.
struct RowOriginKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    /// A click runs `tap`. A long press runs `pick` (the card is then dragged with the mouse, RowDrag), and while it is pressed the
    /// card grows a little.
    func rowCardGestures(id: String, drag: RowDrag, tap: @escaping () -> Void, pick: @escaping () -> Void) -> some View {
        onTapGesture(perform: tap)
            .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 12, perform: pick,
                                onPressingChanged: { down in
                                    if down { drag.pressing = id } else if drag.pressing == id { drag.pressing = nil }
                                })
    }
}
