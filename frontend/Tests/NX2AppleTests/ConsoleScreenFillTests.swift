import XCTest
@testable import NX2Apple

/// Where a window covering a notched screen in console mode goes when the screens change, and where it goes back to on leaving.
/// The screens are given as frames, so nothing here needs a second display.
final class ConsoleScreenFillTests: XCTestCase {
    private let builtIn: CGDirectDisplayID = 1
    private let external: CGDirectDisplayID = 2

    /// The case that left the window off every screen: the built-in screen sat left of and below an external main screen, the
    /// external one was unplugged, and the built-in one became the main screen at the origin.
    func testFollowsTheCoveredScreenToItsNewOrigin() {
        let after = ConsoleScreenFill.refill(display: builtIn, screens: [(builtIn, NSRect(x: 0, y: 0, width: 1470, height: 956))])
        XCTAssertEqual(after?.display, builtIn)
        XCTAssertEqual(after?.frame, NSRect(x: 0, y: 0, width: 1470, height: 956))
    }

    func testKeepsTheCoveredScreenWhenAnotherOneIsAddedOrMoved() {
        let screens: [(display: CGDirectDisplayID?, frame: NSRect)] = [(external, NSRect(x: 0, y: 0, width: 1920, height: 1080)),
                                                                       (builtIn, NSRect(x: -1470, y: -956, width: 1470, height: 956))]
        let after = ConsoleScreenFill.refill(display: builtIn, screens: screens)
        XCTAssertEqual(after?.display, builtIn, "the covered screen, not the main one")
        XCTAssertEqual(after?.frame, NSRect(x: -1470, y: -956, width: 1470, height: 956))
    }

    func testCoversTheMainScreenWhenTheCoveredOneIsGone() {
        let screens: [(display: CGDirectDisplayID?, frame: NSRect)] = [(external, NSRect(x: 0, y: 0, width: 1920, height: 1080)),
                                                                       (3, NSRect(x: 1920, y: 0, width: 2560, height: 1440))]
        let after = ConsoleScreenFill.refill(display: builtIn, screens: screens)
        XCTAssertEqual(after?.display, external)
        XCTAssertEqual(after?.frame, NSRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertNil(ConsoleScreenFill.refill(display: builtIn, screens: []))
    }

    func testRestoresASavedFrameAScreenStillShows() {
        let saved = NSRect(x: 100, y: 80, width: 1200, height: 800)
        let visible = NSRect(x: 0, y: 0, width: 1470, height: 923)
        XCTAssertEqual(ConsoleScreenFill.restoredFrame(saved, screens: [NSRect(x: 0, y: 0, width: 1470, height: 956)], visible: visible), saved)
        let partly = NSRect(x: -600, y: 80, width: 1200, height: 800)
        XCTAssertEqual(ConsoleScreenFill.restoredFrame(partly, screens: [NSRect(x: 0, y: 0, width: 1470, height: 956)], visible: visible), partly,
                       "part of it shows: left where the person put it")
    }

    /// The saved frame from before the external screen was unplugged: centred on the screen the window is on, no bigger than it.
    func testCentresASavedFrameNoScreenShows() {
        let screens = [NSRect(x: 0, y: 0, width: 1470, height: 956)]
        let visible = NSRect(x: 0, y: 0, width: 1470, height: 923)
        XCTAssertEqual(ConsoleScreenFill.restoredFrame(NSRect(x: -1210, y: -921, width: 1380, height: 923), screens: screens, visible: visible),
                       NSRect(x: 45, y: 0, width: 1380, height: 923), "a 170 x 2 point corner on the screen is not enough to take hold of")
        XCTAssertEqual(ConsoleScreenFill.restoredFrame(NSRect(x: -3000, y: 0, width: 2000, height: 1200), screens: screens, visible: visible),
                       visible, "too big for the screen: as big as its visible frame")
    }
}
