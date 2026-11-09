import SwiftUI
import NXCore
import NXLauncher

/// The library page over the whole screen: the home row's last tile and down on the row open it. The title and its count at the
/// top, the display chips (the order, Only built games) at their right, then every game in a grid of covers, each with its cloud
/// save's dot (ConsoleSaveDot): four across on a TV, three in a Mac window, two in a narrow one. The focus stays in the grid: A on a
/// game takes it back to the home screen, first in the row and focused (ConsoleState.pickFromLibrary); Y opens its options, ZL and
/// ZR go to the first or last game, B goes back home with the focus on the library tile. The grid does not go round at its edges. R3 (or F) moves the focus to the chips (`displayMode`): left and right between
/// them, A picks, B or R3 gives the focus back to the game it was on.
@MainActor struct ConsoleLibraryGrid<Driver: ConsoleDriver>: View {
    @ObservedObject var driver: Driver
    let lang: Lang
    let compact: Bool
    let size: CGSize
    let glyphs: ConsoleGlyphs
    /// The chips have the focus: the grid takes no direction.
    var displayMode = false
    @EnvironmentObject private var pad: PadFocus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var scope: String { "console.grid" }
    private var scope: String { Self.scope }
    private func t(_ key: String) -> String { L10n.string(key, lang) }
    private var state: ConsoleState { driver.state }
    private var inset: CGFloat { compact ? 24 : 64 }

    static func gameTarget(_ id: String) -> String { "console.grid.game." + id }
    static func gameID(of target: String?) -> String? {
        guard let target, target.hasPrefix("console.grid.game.") else { return nil }
        return String(target.dropFirst("console.grid.game.".count))
    }
    /// The scroll position of a game's cell (its cover and its name), apart from the cover's pad target id.
    static func cellID(_ target: String) -> String { "console.grid.cell." + target }
    static var firstChip: String { "console.grid.sort." + ConsoleLibrarySort.recent.rawValue }

    /// Four across on a screen as wide as a TV's, two in a narrow window, three otherwise.
    static func columns(width: CGFloat, compact: Bool) -> Int { compact ? 2 : width >= 1600 ? 4 : 3 }
    static func spacing(compact: Bool) -> CGFloat { compact ? 16 : 28 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, inset).padding(.top, compact ? 28 : 48).padding(.bottom, compact ? 16 : 28)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    if state.libraryGames.isEmpty {
                        Text(t("console.empty")).font(.manrope(compact ? 18 : 22)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, inset).padding(.top, 24)
                    } else {
                        grid.padding(.horizontal, inset).padding(.vertical, 12)
                    }
                }
                .consoleScrollFade()
                .opacity(displayMode ? 0.55 : 1)
                .onChange(of: pad.focused) { id in
                    guard let id, Self.gameID(of: id) != nil else { return }
                    withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.18)) { proxy.scrollTo(Self.cellID(id), anchor: .center) }
                }
                .onAppear { if let id = pad.focused, Self.gameID(of: id) != nil { proxy.scrollTo(Self.cellID(id), anchor: .center) } }
            }
            hints.padding(.horizontal, inset).padding(.bottom, compact ? 20 : 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LauncherPalette.background)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.15), value: displayMode)
    }

    // MARK: Title and chips

    /// The title and its count, the chips at their right (under them when narrow), and the close button for the pointer (B closes).
    @ViewBuilder private var header: some View {
        let title = VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            Text(t("console.menu.library")).font(.manrope(compact ? 30 : 44, .bold)).tracking(-0.8).accessibilityAddTraits(.isHeader)
            Text(String(format: t("console.library.count"), state.games.count, state.builtCount))
                .font(.manrope(compact ? 15 : 19, .semibold)).foregroundStyle(LauncherPalette.cream).lineLimit(1)
        }
        let close = Button { driver.back() } label: {
            Image(systemName: "xmark").font(.system(size: compact ? 16 : 18)).frame(width: compact ? 40 : 44, height: compact ? 40 : 44)
                .background(.white.opacity(0.075), in: Circle()).contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(t("console.close"))
        if compact {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) { title; Spacer(minLength: 8); close }
                chips
            }
        } else {
            HStack(alignment: .center, spacing: 20) { title; Spacer(minLength: 16); chips; close }
        }
    }

    /// The R3 hint, the order (two chips, the one in use cream) and Only built games, small. Brighter while they have the focus.
    private var chips: some View {
        let built = state.prefs[.onlyBuilt]
        return HStack(spacing: compact ? 6 : 8) {
            ConsoleGlyphView(glyph: glyphs.rightStickPress, size: compact ? 16 : 20)
                .frame(height: compact ? 28 : 32).padding(.horizontal, compact ? 8 : 10)
                .background(.white.opacity(displayMode ? 0.16 : 0.07), in: Capsule())
                .accessibilityLabel(t("console.grid.display"))
            ForEach(ConsoleLibrarySort.allCases, id: \.self) { sort in
                chip("console.grid.sort." + sort.rawValue, title: t(sort.titleKey), on: state.librarySort == sort) { driver.setLibrarySort(sort) }
            }
            chip("console.grid.onlyBuilt", symbol: built ? "checkmark.circle.fill" : "circle", title: t(ConsolePref.onlyBuilt.titleKey), on: built) {
                driver.setPref(.onlyBuilt, on: !built)
            }
            .accessibilityValue(built ? "1" : "0")
        }
        .padding(4)
        .background(.white.opacity(displayMode ? 0.08 : 0), in: Capsule())
        .fixedSize()
    }

    private func chip(_ id: String, symbol: String? = nil, title: String, on: Bool, action: @escaping () -> Void) -> some View {
        let height: CGFloat = compact ? 28 : 32
        return Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: compact ? 11 : 13, weight: .semibold)).accessibilityHidden(true) }
                Text(title).font(.manrope(compact ? 12 : 14, on ? .bold : .semibold)).lineLimit(1)
            }
            .padding(.horizontal, compact ? 10 : 12).frame(height: height)
            .foregroundStyle(on ? LauncherPalette.background : .white.opacity(displayMode ? 0.95 : 0.8))
            // the outline is a filled pill under the chip's own, 1 pt larger: a stroked pill drew marks at its ends
            .background(on ? LauncherPalette.cream : Color(white: displayMode ? 0.17 : 0.125), in: Capsule()).padding(on ? 0 : 1)
            .background(on ? .clear : Color(white: displayMode ? 0.32 : 0.24), in: Capsule()).padding(on ? 1 : 0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title).accessibilityAddTraits(on ? .isSelected : [])
        .padTarget(id, scope: scope, radius: height / 2 + 1, when: displayMode, activate: action)   // targets only while they have the focus
    }

    // MARK: Grid

    /// Every row is drawn (not lazily), so the focus can move to any game, however far down, and L / R land on a drawn tile.
    private var grid: some View {
        let columns = Self.columns(width: size.width, compact: compact), spacing = Self.spacing(compact: compact)
        let games = state.libraryGames
        let rows = stride(from: 0, to: games.count, by: columns).map { Array(games[$0..<min($0 + columns, games.count)]) }
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(rows[r]) { game in tile(game) }
                    ForEach(0..<(columns - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
            }
        }
    }

    private func tile(_ game: ConsoleGame) -> some View {
        let id = Self.gameTarget(game.id)
        let pick = { driver.pickFromLibrary(game.id) }
        return VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Button(action: pick) {
                ConsoleGameTile(game: game, compact: compact, lang: lang, showsSaveDot: true).contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padTarget(id, scope: scope, radius: 16, when: !displayMode, activate: pick)   // not while the chips have the focus
            .id(id)
            Text(game.title).font(.manrope(compact ? 14 : 18, .semibold)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                .padding(.horizontal, 4).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ConsoleSaveDot.accessibilityLabel(game, lang: lang))
        .accessibilityHint(t("console.grid.pick"))
        .id(Self.cellID(id))
    }

    // MARK: Hints

    private var hints: some View {
        let swap = state.menuSwapAB
        let a = glyphs.glyph(for: .activate, on: ConsoleButtons.button(for: .activate, swapAB: swap))
        let b = glyphs.glyph(for: .back, on: ConsoleButtons.button(for: .back, swapAB: swap))
        let items = Group {
            if displayMode {
                hint([a], "console.grid.choose")
                hint([b, glyphs.rightStickPress], "console.grid.done")
            } else {
                hint([a], "console.grid.pick")
                hint([glyphs.glyph(for: .options, on: ConsoleButtons.button(for: .options, swapAB: swap))], "console.options")
                if !compact { hint([glyphs.shoulder("ZL"), glyphs.shoulder("ZR")], "console.grid.ends") }
                hint([glyphs.rightStickPress], "console.grid.display")
                hint([b], "console.close")
            }
        }
        return VStack(spacing: compact ? 12 : 20) {
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
            if compact { LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 8) { items } }
            else { HStack(spacing: min(size.width * 0.03, 40)) { items }.frame(maxWidth: .infinity, alignment: .trailing) }
        }
    }

    private func hint(_ glyphs: [ConsoleGlyphs.Glyph], _ key: String) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) { ForEach(glyphs.indices, id: \.self) { ConsoleGlyphView(glyph: glyphs[$0], size: compact ? 20 : 24) } }
            Text(t(key)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.manrope(compact ? 15 : 20, .semibold)).foregroundStyle(.white.opacity(0.75))
        .frame(minHeight: compact ? 36 : 48)
        .accessibilityElement(children: .combine)
    }
}

extension ConsoleGlyphs {
    /// The right stick pressed (R3), or F on the keyboard.
    var rightStickPress: Glyph { family == .keyboard ? .key("F") : .symbol("r.joystick.press.down") }

    /// A shoulder button or trigger ("L", "R", "ZL", "ZR") as the controller's family prints it, or its key on the keyboard (Page Up,
    /// Page Down, Home, End).
    func shoulder(_ name: String) -> Glyph {
        let symbols: [String: String]
        switch family {
        case .keyboard: return .key(["L": "\u{21DE}", "R": "\u{21DF}", "ZL": "\u{2196}", "ZR": "\u{2198}"][name] ?? name)
        case .xbox: symbols = ["L": "lb", "R": "rb", "ZL": "lt", "ZR": "rt"]
        case .playStation: symbols = ["L": "l1", "R": "r1", "ZL": "l2", "ZR": "r2"]
        case .nintendo: symbols = ["L": "l", "R": "r", "ZL": "zl", "ZR": "zr"]
        case .neutral: return .letter(name)
        }
        guard let base = symbols[name] else { return .letter(name) }
        return .symbol(base + (name.hasPrefix("Z") ? ".rectangle.roundedtop" : ".rectangle.roundedbottom"))
    }
}

extension View {
    /// A pad target only while `on`: the library page's chips and games take turns (ConsoleLibraryGrid.displayMode).
    @ViewBuilder func padTarget(_ id: String, scope: String, radius: CGFloat, when on: Bool, activate: @escaping () -> Void) -> some View {
        if on { padTarget(id, scope: scope, radius: radius, activate: activate) } else { self }
    }
}
