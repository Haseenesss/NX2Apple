import SwiftUI

/// The collection row's scroll state, read from its NSScrollView: SwiftUI's horizontal ScrollView does not
/// report its offset on macOS 13, so the pager chevrons follow the clip view's bounds instead.
package final class RowScroller: ObservableObject {
    package init() {}
    @Published package private(set) var canBack = false
    @Published package private(set) var canForward = false
    private weak var scrollView: NSScrollView?
    private var observers: [NSObjectProtocol] = []
    /// A mouse's wheel turned over the row scrolls it sideways (a row has nowhere to go up or down). A trackpad's two-finger swipe,
    /// which scrolls sideways by itself, is left alone.
    private var wheelMonitor: Any?

    package func attach(_ view: NSScrollView) {
        guard view !== scrollView else { return update() }
        observers.forEach(NotificationCenter.default.removeObserver)
        scrollView = view
        let clip = view.contentView
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        view.documentView?.postsFrameChangedNotifications = true
        observers = [(NSView.boundsDidChangeNotification, clip), (NSView.frameDidChangeNotification, clip),
                     (NSView.frameDidChangeNotification, view.documentView as Any)].map { name, object in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in self?.update() }
        }
        update()
        if wheelMonitor == nil {
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let view = self.scrollView, let window = view.window, event.window === window,
                      !event.hasPreciseScrollingDeltas, event.scrollingDeltaX == 0, event.scrollingDeltaY != 0,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return event }
                self.scroll(by: -event.scrollingDeltaY * 16, animated: false)
                return nil
            }
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
    }

    private func update() {
        guard let view = scrollView, let document = view.documentView else { return }
        let x = view.contentView.bounds.minX, end = document.frame.width - view.contentView.bounds.width
        if canBack != (x > 1) { canBack = x > 1 }
        if canForward != (x < end - 1) { canForward = x < end - 1 }
    }

    /// Scroll by the whole cards that fit in the row.
    package func page(_ direction: CGFloat, step: CGFloat) {
        guard let view = scrollView, let document = view.documentView else { return }
        let clip = view.contentView
        let distance = max(step, (clip.bounds.width / step).rounded(.down) * step)
        let target = min(max(0, clip.bounds.minX + direction * distance), max(0, document.frame.width - clip.bounds.width))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            clip.animator().setBoundsOrigin(NSPoint(x: target, y: clip.bounds.minY))
        }
        view.reflectScrolledClipView(clip)
    }

    /// Brings a card into view: `minX...maxX` is where it is drawn now, in the scroll view's own coordinates (a SwiftUI coordinate
    /// space on the ScrollView). It scrolls by the least that leaves `margin` beside it, or puts it in the middle (`center`). The
    /// AppKit scroll view is moved directly: SwiftUI's ScrollViewReader did not scroll a horizontal row inside a vertical
    /// ScrollView (console mode's row of games).
    package func reveal(minX: CGFloat, maxX: CGFloat, margin: CGFloat, center: Bool = false, animated: Bool = true) {
        guard let view = scrollView else { return }
        let x = view.contentView.bounds.minX, width = view.contentView.bounds.width
        let target: CGFloat
        if center { target = x + (minX + maxX) / 2 - width / 2 }
        else if minX < margin { target = x + minX - margin }
        else if maxX > width - margin { target = x + maxX - width + margin }
        else { return }
        scroll(to: target, animated: animated)
    }

    /// Scrolls by `distance` (a card's width while a card is dragged to the row's end).
    package func scroll(by distance: CGFloat, animated: Bool = true) {
        guard let view = scrollView else { return }
        scroll(to: view.contentView.bounds.minX + distance, animated: animated)
    }

    private func scroll(to x: CGFloat, animated: Bool) {
        guard let view = scrollView, let document = view.documentView else { return }
        let clip = view.contentView
        let target = min(max(0, x), max(0, document.frame.width - clip.bounds.width))
        guard abs(target - clip.bounds.minX) > 0.5 else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clip.animator().setBoundsOrigin(NSPoint(x: target, y: clip.bounds.minY))
            }
        } else {
            clip.setBoundsOrigin(NSPoint(x: target, y: clip.bounds.minY))
        }
        view.reflectScrolledClipView(clip)
    }
}

/// Hands the NSScrollView around this background view to the row's scroller once it is in a window.
package struct EnclosingScrollView: NSViewRepresentable {
    let row: RowScroller
    package init(row: RowScroller) { self.row = row }
    package final class Probe: NSView {
        package var row: RowScroller?
        package override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                if let view = self?.enclosingScrollView { self?.row?.attach(view) }
            }
        }
    }
    package func makeNSView(context: Context) -> Probe { let probe = Probe(); probe.row = row; return probe }
    package func updateNSView(_ probe: Probe, context: Context) {
        probe.row = row
        DispatchQueue.main.async { if let view = probe.enclosingScrollView { row.attach(view) } }
    }
}

/// The library's collection row reports its height, so the hero above it fills exactly what is left.
package struct CollectionHeightKey: PreferenceKey {
    package static var defaultValue: CGFloat = 0
    package static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
