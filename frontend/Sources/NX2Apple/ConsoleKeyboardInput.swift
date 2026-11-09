import AppKit
import SwiftUI

/// A window-local keyboard adapter. A local monitor keeps navigation working after a click gives a
/// native button first-responder status; it never consumes another window's keys or global shortcuts.
/// `perform` gets the input and whether it is the key's auto-repeat (NSEvent.isARepeat), not a new press.
struct ConsoleKeyboardInput: NSViewRepresentable {
    var perform: (ConsoleInput, Bool) -> Void
    final class KeyView: NSView {
        var perform: (ConsoleInput, Bool) -> Void = { _, _ in }
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window, window.isKeyWindow,
                      NSApp.isActive, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                      let input = Self.input(event) else { return event }
                self.perform(input, event.isARepeat)
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
        private static func input(_ event: NSEvent) -> ConsoleInput? {
            switch event.keyCode {
            case 123: return .left
            case 124: return .right
            case 125: return .down
            case 126: return .up
            case 36, 76, 49: return .activate
            case 53: return .back
            case 115: return .first         // Home
            case 119: return .last          // End
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "y", "o": return .options
                case "m", "+", "=": return .menu
                case "f": return .displayMode
                default: return nil
                }
            }
        }
    }
    func makeNSView(context: Context) -> KeyView { let view = KeyView(); view.perform = perform; return view }
    func updateNSView(_ view: KeyView, context: Context) { view.perform = perform }
}
