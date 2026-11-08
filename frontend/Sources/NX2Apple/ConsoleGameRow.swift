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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: ConsoleState { driver.state }
    private func t(_ key: String) -> String { L10n.string(key, lang) }
    static func cell(_ id: String) -> String { "console.row." + id }

    var body: some View {
        let width: CGFloat = compact ? size.width - inset * 2 - 16 : min(470, size.width * 0.32)
        let spacing: CGFloat = (compact ? 22 : 28) - 16
        // While arranging, the scroll area reaches the screen's edges and the page margin moves inside it: the tiles stay where they
        // were, and the game picked up grows into the margin instead of being cut at it. It grows only as much as that room allows.
        let clip: CGFloat = state.arranging ? 0 : inset - 8
        let lead = inset - 8 - clip
        let heldScale = ConsoleArrange.heldScale(width: width, room: inset)
        let rowWidth = size.width - 2 * clip
        let safe = 8 + lead   // a tile closer than this to the scroll area's edge is brought in
        let order = state.games.map(\.id)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
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
            }
            .coordinateSpace(name: "console.row")
            .onPreferenceChange(ConsoleTileFramesKey.self) { frames in
                tileFrames = frames
                follow(order: order, frames: frames)   // the cards moved: the one dragged may have passed another
            }
            .padding(.horizontal, clip)   // the scroll area is the page margin, so tiles clip there and the title lines up with the first tile
            .onAppear {
                if let id = state.focusedGame?.id { proxy.scrollTo(Self.cell(id), anchor: .center) }
                drag.onEdge = { way in   // near an end of the row while dragging: bring in the next game that way
                    guard let id = RowDrag.nextCard(way, order: driver.state.games.map(\.id), frames: tileFrames, rowWidth: rowWidth) else { return }
                    withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.28)) { proxy.scrollTo(Self.cell(id), anchor: way > 0 ? .trailing : .leading) }
                }
            }
            .onChange(of: state.focusedGame?.id) { id in
                // The ring moves across the visible tiles. The row scrolls only when the focused tile would leave the visible area, by
                // the least that brings it inside, and a new focus replaces the running scroll (held repeats do not queue).
                guard let id, !drag.active else { return }
                guard let frame = tileFrames[id] else { proxy.scrollTo(Self.cell(id), anchor: .center); return }
                // while arranging a tile is brought to the middle, where a game picked up has room on both sides
                let anchor: UnitPoint? = frame.minX < safe ? (state.arranging ? .center : .leading)
                    : (frame.maxX > rowWidth - safe ? (state.arranging ? .center : .trailing) : nil)
                if let anchor { withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.2)) { proxy.scrollTo(Self.cell(id), anchor: anchor) } }
            }
            .onChange(of: state.games.map(\.id)) { _ in   // the game being moved stays in view, with room to either side
                guard let id = state.heldGameID, !drag.active else { return }   // a drag scrolls at the ends instead
                withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.25)) { proxy.scrollTo(Self.cell(id), anchor: .center) }
            }
            .onChange(of: state.heldGameID) { id in   // a game picked up at the edge of the view comes in before it grows
                guard let id, !drag.active, let frame = tileFrames[id], frame.minX < safe || frame.maxX > rowWidth - safe else { return }
                withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.25)) { proxy.scrollTo(Self.cell(id), anchor: .center) }
            }
            .onChange(of: state.arranging) { on in if !on, drag.active { drag.end() } }
        }
    }

    private func tile(_ game: ConsoleGame, width: CGFloat, scale: CGFloat) -> some View {
        let selected = state.focusedGame?.id == game.id
        let held = state.heldGameID == game.id
        let dragged = drag.id == game.id
        let rowWidth = size.width - 2 * (state.arranging ? 0 : inset - 8)
        return ConsoleGameTile(game: game, compact: compact, lang: lang)
            .frame(width: width)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .gesture(
                LongPressGesture(minimumDuration: 0.35)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("console.row")))
                    .onChanged { value in
                        guard case let .second(true, move) = value else { return }
                        if !drag.active {
                            driver.pickUp(game.id)
                            guard driver.state.heldGameID == game.id else { return }
                            drag.begin(game.id, frame: tileFrames[game.id], at: move?.location.x, rowWidth: rowWidth)
                        } else if let move {
                            drag.moved(to: move.location.x, rowWidth: rowWidth)
                            follow(order: driver.state.games.map(\.id), frames: tileFrames)
                        }
                    }
                    .onEnded { _ in
                        guard drag.active else { return }
                        drag.end()
                        driver.putDown()
                    }
                    .exclusively(before: TapGesture().onEnded {
                        driver.focus(game.id)
                        if state.arranging { driver.toggleHold() } else { driver.play(game.id) }
                    })
            )
            .padTarget("console.game." + game.id, scope: "console", radius: 16, activate: { driver.play(game.id) })
            .arrangeLook(arranging: state.arranging, focused: selected, held: held, anyHeld: state.heldGameID != nil,
                         canLeft: held && state.canMoveHeld(-1), canRight: held && state.canMoveHeld(1), scale: scale,
                         dragX: dragged ? drag.offset(for: game.id, frames: tileFrames) : 0)
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
        guard step != 0, driver.state.canMoveHeld(step) else { return }
        driver.moveHeld(step)
        RowDrag.haptic(.alignment)
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
