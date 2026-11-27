import AppKit
import SwiftUI
import XCTest
@testable import NX2Apple
@testable import NXCore
@testable import NXLauncher

/// #1513: while the home row slides to the next game, every cover keeps its caption under it, the covers never overlap, and the art
/// behind goes from the old game's to the new one's without a dark frame. Once the row settled it was right, but mid-move the focused
/// cover flew in from the last one's place (a matched geometry with nothing to match), the captions of the covers whose focus changed
/// drifted (their text interpolated outside the row's move), and the old art vanished at once while the new one faded in from black.
/// The motion is slowed tenfold (the state gallery's Slow motion), so the frames read mid-move on a slow machine too.
@MainActor final class ConsoleRowSlideTests: IsolatedDefaultsTestCase {
    private let size = CGSize(width: 1280, height: 800)
    private static let speed = 0.1

    private struct Hosted {
        let driver: MockConsoleDriver
        let focus: PadFocus
        let view: NSView
        let window: NSWindow
    }

    /// One solid, saturated color per game, so a cover, its neighbours and the art behind can be told apart by their pixels.
    private func art(_ index: Int) -> NSImage {
        NSImage(size: NSSize(width: 360, height: 200), flipped: false) { rect in
            NSColor(hue: CGFloat(index) / 6, saturation: 0.8, brightness: 0.9, alpha: 1).setFill(); rect.fill(); return true
        }
    }

    private func host() throws -> Hosted {
        let driver = MockConsoleDriver(scenario: .full, animated: false)
        let sample = try XCTUnwrap(driver.state.games.first)
        driver.state.games = (0..<6).map { index in
            var game = sample
            game.id = "slide.\(index)"; game.title = "Game \(index)"; game.status = .ready
            game.artwork = art(index); game.hero = nil
            return game
        }
        driver.state.focusedGameID = "slide.1"
        let focus = PadFocus()
        let view = NSHostingView(rootView: ConsoleView(driver: driver, lang: .en, padFocus: focus)
            .frame(width: size.width, height: size.height).dsMotionSpeed(Self.speed))
        let window = OffscreenWindow(size: size, styleMask: [.borderless])
        window.contentView = view; window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        focus.scope = "console"; focus.focused = "console.game.slide.1"
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        return Hosted(driver: driver, focus: focus, view: view, window: window)
    }

    private func close(_ hosted: Hosted) { hosted.window.contentView = nil; hosted.window.orderOut(nil); hosted.window.close() }

    private func capture(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func color(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> NSColor? {
        let scale = CGFloat(rep.pixelsWide) / size.width
        let px = Int(x * scale), py = Int(y * scale)
        guard px >= 0, py >= 0, px < rep.pixelsWide, py < rep.pixelsHigh else { return nil }
        return rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB)
    }

    /// The covers along one line through the row: runs of saturated pixels, in points.
    private func covers(_ rep: NSBitmapImageRep, y: CGFloat) -> [ClosedRange<CGFloat>] {
        var runs: [ClosedRange<CGFloat>] = [], start: CGFloat?
        for x in stride(from: CGFloat(0), through: size.width, by: 1) {
            let c = color(rep, x, y)
            let on = (c?.saturationComponent ?? 0) > 0.3 && (c?.brightnessComponent ?? 0) > 0.3
            if on, start == nil { start = x }
            if !on, let s = start { runs.append(s...(x - 1)); start = nil }
        }
        if let s = start { runs.append(s...size.width) }
        return runs.filter { $0.upperBound - $0.lowerBound > 20 }
    }

    /// Where a caption's text starts in the band under the covers: the leftmost light grey pixel within `range`.
    private func captionStart(_ rep: NSBitmapImageRep, band: ClosedRange<CGFloat>, in range: ClosedRange<CGFloat>) -> CGFloat? {
        for x in stride(from: max(0, range.lowerBound), through: min(size.width, range.upperBound), by: 0.5) {
            for y in stride(from: band.lowerBound, through: band.upperBound, by: 1) {
                if let c = color(rep, x, y), c.saturationComponent < 0.15, c.brightnessComponent > 0.45 { return x }
            }
        }
        return nil
    }

    private struct Row { let covers: [ClosedRange<CGFloat>]; let offsets: [CGFloat] }

    /// The covers along the row, and for each one wholly in the window how far its caption starts from its middle. The focus scale grows
    /// a cover about its middle, so that distance is the same for every cover, focused or not.
    private func row(_ rep: NSBitmapImageRep, card: CGRect) -> Row {
        let artHeight = card.width / 1.8
        let line = covers(rep, y: card.minY + artHeight - 8)   // low on the covers, where the art behind has faded out
        let band = (card.minY + artHeight + 12)...(card.minY + artHeight + 30)
        var offsets: [CGFloat] = []
        for cover in line where cover.lowerBound > 2 && cover.upperBound < size.width - 2 {
            if let start = captionStart(rep, band: band, in: (cover.lowerBound - 80)...(cover.lowerBound + 80)) {
                offsets.append(start - (cover.lowerBound + cover.upperBound) / 2)
            }
        }
        return Row(covers: line, offsets: offsets)
    }

    func testCoversAndCaptionsMoveTogetherAndTheArtNeverGoesDark() throws {
        let hosted = try host()
        defer { close(hosted) }
        let card = try XCTUnwrap(hosted.focus.frames["console"]?.first { $0.id == "console.game.slide.1" }?.frame)
        let settled = row(try capture(hosted.view), card: card)
        let offset = try XCTUnwrap(settled.offsets.first, "a caption is found under a settled cover")
        for o in settled.offsets { XCTAssertEqual(o, offset, accuracy: 3, "settled, every caption starts at the same place under its cover") }
        let artPoint = CGPoint(x: size.width - 280, y: 150)
        for (step, target) in [(1, "slide.2"), (-1, "slide.1")] {
            let start = try capture(hosted.view)
            let before = try XCTUnwrap(color(start, artPoint.x, artPoint.y))
            let lead = try XCTUnwrap(row(start, card: card).covers.first { $0.lowerBound > 2 })
            hosted.driver.focus(target); hosted.focus.focused = "console.game." + target
            var moving = 0
            for _ in 0..<6 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                let rep = try capture(hosted.view)
                let frame = row(rep, card: card)
                if let now = frame.covers.first(where: { $0.lowerBound > 2 }), abs(now.lowerBound - lead.lowerBound) > 8 { moving += 1 }
                for cover in frame.covers where cover.lowerBound > 2 && cover.upperBound < size.width - 2 {
                    XCTAssertLessThanOrEqual(cover.upperBound - cover.lowerBound, card.width * 1.06,
                                             "step \(step): a run wider than one cover is two covers overlapping")
                }
                for o in frame.offsets {
                    XCTAssertEqual(o, offset, accuracy: 4, "step \(step): a caption drifted from its cover while the row moved")
                }
                let art = try XCTUnwrap(color(rep, artPoint.x, artPoint.y))
                XCTAssertGreaterThan(art.brightnessComponent, min(before.brightnessComponent, 0.5),
                                     "step \(step): the art behind went dark between the two games")
            }
            XCTAssertGreaterThan(moving, 0, "step \(step): no frame caught the row moving")
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        }
    }

    /// Opt in with NX_CAPTURE_1513=<folder>: the frames of a move right and a move left, for the pull request.
    func testCaptureTheSlide() throws {
        guard let folder = ProcessInfo.processInfo.environment["NX_CAPTURE_1513"] else { throw XCTSkip("set NX_CAPTURE_1513 to a folder") }
        let hosted = try host()
        defer { close(hosted) }
        for (name, target) in [("right", "slide.2"), ("left", "slide.1")] {
            hosted.driver.focus(target); hosted.focus.focused = "console.game." + target
            let start = Date()
            for (frame, at) in [0.0, 0.4, 0.8, 1.2, 4.0].enumerated() {
                RunLoop.main.run(until: start.addingTimeInterval(at))
                let data = try XCTUnwrap(try capture(hosted.view).representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(frame).png"))
            }
        }
    }
}
