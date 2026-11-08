import SwiftUI
import NXCore
import NXLauncher

/// Console mode's row of games under the title. A click plays a game (or, while arranging, picks it up and puts it down, as A does).
/// A long press with the mouse picks a game up and starts arranging; dragging moves it along the row, the other games making room
/// (RowDrag), and letting go puts it down there, in its group, as the controller's left and right do (#937).
@MainActor struct ConsoleGameRow<Driver: ConsoleDriver>: View {
    @ObservedObject var driver: Driver
    let lang: Lang
    let size: CGSize
    let compact: Bool
    let inset: CGFloat
    @StateObject private var drag = RowDrag()
    @State private var tileFrames: [String: CGRect] = [:]
    @State private var rowOriginX: CGFloat = 0
    @StateObject private var scroller = RowScroller()   // where the row starts in the window, for the mouse (RowDrag)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: ConsoleState { driver.state }
    private func t(_ key: String) -> String { L10n.string(key, lang) }
    static func cell(_ id: String) -> String { "console.row." + id }

    var body: some View {
        let width: CGFloat = compact ? size.width - inset * 2 - 16 : Self.tileWidth(rowWidth: size.width - inset * 2)
        let spacing: CGFloat = (compact ? 22 : 28) - 16
        // While arranging, the scroll area reaches the screen's edges and the page margin moves inside it: the tiles stay where they
        // were, and the game picked up grows into the margin instead of being cut at it. It grows only as much as that room allows.
        let clip: CGFloat = state.arranging ? 0 : inset - 8
        let lead = inset - 8 - clip
        let heldScale = ConsoleArrange.heldScale(width: width, room: inset)
        let rowWidth = size.width - 2 * clip
        let safe = 8 + lead   // a tile closer than this to the scroll area's edge is brought in
        let order = state.games.map(\.id)
        return ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(state.games) { game in
                        tile(game, width: width, scale: heldScale)
                            // the line between the games ready on this Mac and the others, which a game picked up does not cross
                            .overlay(alignment: .leading) {
                                if state.arranging, game.id == state.groupBoundaryID {
                                    Capsule().fill(.white.opacity(0.35)).frame(width: 3).padding(.vertical, 24)
                                        .offset(x: -(spacing + 16) / 2 - 1.5).transition(.opacity).accessibilityHidden(true)
                                }
                            }
                            // every tile carries its own 8 pt of room for the ring and the focus scale, and the scroll target is this
                            // padded cell, so a scroll to the first or last tile never pushes that room out of the clip
                            .padding(.horizontal, 8)
                            .id(Self.cell(game.id))
                    }
                }
                .padding(.top, state.arranging ? (compact ? 52 : 72) : 12).padding(.bottom, 12)   // room for the game picked up
                .padding(.horizontal, lead)
                .background(EnclosingScrollView(row: scroller))   // the AppKit scroll view, moved directly (RowScroller.reveal)
            }
            .coordinateSpace(name: "console.row")
            .background(GeometryReader { g in Color.clear.preference(key: RowOriginKey.self, value: g.frame(in: .global).minX) })
            .onPreferenceChange(RowOriginKey.self) { rowOriginX = $0 }
            .onPreferenceChange(ConsoleTileFramesKey.self) { frames in
                tileFrames = frames
                drag.framesChanged(frames)
                follow(order: order, frames: frames)   // the cards moved: the one dragged may have passed another
            }
            // where there are more games beyond an end, the row fades out toward it instead of ending in a hard cut
            .mask(Self.edgeFade(width: min(180, width * 0.55), leading: scroller.canBack, trailing: scroller.canForward))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: scroller.canBack)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: scroller.canForward)
            .padding(.horizontal, clip)   // the scroll area is the page margin, so tiles clip there and the title lines up with the first tile
            .onAppear {
                DispatchQueue.main.async { reveal(state.focusedGame?.id, margin: safe, center: true, animated: false) }
                drag.onEdge = { way in scroller.scroll(by: CGFloat(way) * (width + spacing + 16)) }   // near an end while dragging: one game that way
            }
            .onChange(of: state.focusedGame?.id) { id in
                // The ring moves across the visible tiles. The row scrolls only when the focused tile would leave the visible area, by
                // the least that brings it inside; while arranging it is brought to the middle, where a game picked up has room
                guard !drag.active else { return }
                reveal(id, margin: safe, center: state.arranging && !isInside(id, margin: safe, rowWidth: rowWidth))
            }
            .onChange(of: state.games.map(\.id)) { _ in   // the game being moved stays in view, with room to either side
                guard let id = state.heldGameID, !drag.active else { return }   // a drag scrolls at the ends instead
                DispatchQueue.main.async { reveal(id, margin: safe, center: true) }   // once its new frame is in
            }
            .onChange(of: state.heldGameID) { id in   // a game picked up at the edge of the view comes in before it grows
                guard let id, !drag.active, !isInside(id, margin: safe, rowWidth: rowWidth) else { return }
                reveal(id, margin: safe, center: true)
            }
            .onChange(of: state.arranging) { on in if !on, drag.active { drag.end() } }
            .onDisappear { drag.end() }
    }

    /// Scrolls the row so the game's tile is in view (RowScroller.reveal), by where its tile is now.
    private func reveal(_ id: String?, margin: CGFloat, center: Bool, animated: Bool = true) {
        guard let id, let frame = tileFrames[id] else { return }
        scroller.reveal(minX: frame.minX, maxX: frame.maxX, margin: margin, center: center, animated: animated && !reduceMotion)
    }

    private func isInside(_ id: String?, margin: CGFloat, rowWidth: CGFloat) -> Bool {
        guard let id, let frame = tileFrames[id] else { return true }
        return frame.minX >= margin && frame.maxX <= rowWidth - margin
    }

    private func tile(_ game: ConsoleGame, width: CGFloat, scale: CGFloat) -> some View {
        let selected = state.focusedGame?.id == game.id
        let held = state.heldGameID == game.id
        let dragged = drag.id == game.id
        let rowWidth = size.width - 2 * (state.arranging ? 0 : inset - 8)
        // a game cut at the row's edge is drawn smaller and fainter: there are more games that way, only not in view
        let shown = held || dragged ? 1 : Self.shownFraction(tileFrames[game.id], rowWidth: rowWidth)
        return ConsoleGameTile(game: game, compact: compact, lang: lang)
            .frame(width: width)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            // a click plays (or picks up and puts down while arranging, as A does); a long press picks the game up and the mouse drags it
            .rowCardGestures(id: game.id, drag: drag, tap: {
                driver.focus(game.id)   // brings a game cut at the edge into view
                guard shown > 0.98 else { return }   // a click on a game cut at the edge only scrolls to it
                if driver.state.arranging { driver.toggleHold() } else { driver.play(game.id) }
            }, pick: {
                driver.pickUp(game.id)
                guard driver.state.heldGameID == game.id else { return }
                drag.begin(game.id, frame: tileFrames[game.id], rowOriginX: rowOriginX, rowWidth: rowWidth,
                           onMove: { follow(order: driver.state.games.map(\.id), frames: tileFrames) },
                           onRelease: { driver.putDown() })
            })
            .scaleEffect(drag.pressing == game.id && !held ? 1.03 : 1)   // pressed: it starts to lift before it is picked up
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: drag.pressing)
            .padTarget("console.game." + game.id, scope: "console", radius: 16, activate: { driver.play(game.id) })
            .arrangeLook(arranging: state.arranging, focused: selected, held: held, anyHeld: state.heldGameID != nil,
                         canLeft: held && state.canMoveHeld(-1), canRight: held && state.canMoveHeld(1), scale: scale,
                         dragX: dragged ? drag.offset(for: game.id) : 0)
            .scaleEffect(0.86 + 0.14 * shown, anchor: .bottom)
            .opacity(0.6 + 0.4 * shown)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: shown)
            // the game being dragged follows the pointer at once; the others spring aside
            .transaction { if dragged { $0.animation = nil } }
            .background(GeometryReader { g in Color.clear.preference(key: ConsoleTileFramesKey.self, value: [game.id: g.frame(in: .named("console.row"))]) })
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(game.title + ", " + t(game.status.labelKey))
            .accessibilityHint(t("console.playHint"))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction { driver.focus(game.id); driver.play(game.id) }
            // VoiceOver moves a game one place from the actions menu, picked up and put down at once
            .accessibilityAction(named: t("console.arrange.moveLeft")) { moveByOne(game.id, -1) }
            .accessibilityAction(named: t("console.arrange.moveRight")) { moveByOne(game.id, 1) }
    }

    /// The dragged game takes one step toward the pointer when it has passed the next game, within its group (the state refuses to
    /// cross). Each step is kept at once, as a step of the controller's is; the new places come back as frames and call this again.
    private func follow(order: [String], frames: [String: CGRect]) {
        guard drag.active else { return }
        let step = drag.step(order: order, frames: frames)
        guard step != 0, driver.state.canMoveHeld(step), let id = drag.id, let at = order.firstIndex(of: id) else { return }
        drag.stepped(into: frames[order[at + step]], step: step, frame: frames[id])   // its new place at once: no jump while the frames come back
        driver.moveHeld(step)
        RowDrag.haptic(.alignment)
    }

    /// The row's mask: opaque, fading to clear over `width` at an end that has more games beyond it.
    static func edgeFade(width: CGFloat, leading: Bool, trailing: Bool) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [leading ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing).frame(width: width)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, trailing ? .clear : .black], startPoint: .leading, endPoint: .trailing).frame(width: width)
        }
    }

    /// A tile's width: about three and a half tiles in the row, so the next game shows at the edge, between 200 and 380 points.
    static func tileWidth(rowWidth: CGFloat) -> CGFloat {
        let gap: CGFloat = 28
        return min(380, max(200, (rowWidth - 3 * gap) / 3.5))
    }

    /// How much of a tile is inside the visible row, 0 to 1 (1 without a frame yet).
    static func shownFraction(_ frame: CGRect?, rowWidth: CGFloat) -> CGFloat {
        guard let frame, frame.width > 0 else { return 1 }
        let inside = max(0, min(frame.maxX, rowWidth) - max(frame.minX, 0))
        return min(1, inside / frame.width)
    }

    private func moveByOne(_ id: String, _ step: Int) {
        let wasArranging = state.arranging
        driver.pickUp(id)
        driver.moveHeld(step)
        driver.putDown()
        if !wasArranging { driver.toggleArranging() }
    }
}

struct ConsoleTileFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { _, new in new } }
}
