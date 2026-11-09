import SwiftUI
import NXCore
import NXLauncher

/// The library page over the whole screen: the home row's last tile and down on the row open it. A row of chips at the top (the
/// order, Only built games), then every game in a grid of covers, each with its cloud save's dot (ConsoleSaveDot): four across on a TV, three in a
/// Mac window, two in a narrow one. A on a game takes it back to the home screen, first in the row and focused (ConsoleState
/// .pickFromLibrary); Y opens its options, L and R go a screen back or on, ZL and ZR to the first or last game, B goes back home
/// with the focus on the library tile. The grid does not go round at its edges.
@MainActor struct ConsoleLibraryGrid<Driver: ConsoleDriver>: View {
    @ObservedObject var driver: Driver
    let lang: Lang
    let compact: Bool
    let size: CGSize
    let glyphs: ConsoleGlyphs
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
    static var firstChip: String { "console.grid.sort." + ConsoleLibrarySort.recent.rawValue }

    /// Four across on a screen as wide as a TV's, two in a narrow window, three otherwise.
    static func columns(width: CGFloat, compact: Bool) -> Int { compact ? 2 : width >= 1600 ? 4 : 3 }
    static func spacing(compact: Bool) -> CGFloat { compact ? 16 : 28 }
    /// How many games a screen of the grid shows (whole rows), which L and R move by.
    static func pageSize(size: CGSize, compact: Bool) -> Int {
        let columns = columns(width: size.width, compact: compact)
        let inset: CGFloat = compact ? 24 : 64, spacing = spacing(compact: compact)
        let tileWidth = (size.width - 2 * inset - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let rowHeight = tileWidth / 1.8 + (compact ? 34 : 44) + spacing   // the cover, its name, the gap
        let gridHeight = size.height - (compact ? 260 : 330)   // the title, the chips and the hints
        return columns * max(1, Int(gridHeight / max(rowHeight, 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConsolePageHeader(title: t("console.menu.library"), subtitle: String(format: t("console.library.count"), state.games.count, state.builtCount),
                              compact: compact, closeLabel: t("console.close"), closeID: "console.grid.close", scope: scope, close: { driver.back() })
            chips.padding(.horizontal, inset).padding(.bottom, compact ? 16 : 24)
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
                .onChange(of: pad.focused) { id in
                    guard let id, Self.gameID(of: id) != nil else { return }
                    withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.18)) { proxy.scrollTo(id, anchor: .center) }
                }
                .onAppear { if let id = pad.focused, Self.gameID(of: id) != nil { proxy.scrollTo(id, anchor: .center) } }
            }
            hints.padding(.horizontal, inset).padding(.bottom, compact ? 20 : 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LauncherPalette.background)
    }

    // MARK: Chips

    /// The order (two chips, the one in use cream) and Only built games. The cloud saves page is General's (each cover has its dot).
    @ViewBuilder private var chips: some View {
        let order = HStack(spacing: 10) {
            ForEach(ConsoleLibrarySort.allCases, id: \.self) { sort in
                chip("console.grid.sort." + sort.rawValue, title: t(sort.titleKey), on: state.librarySort == sort) { driver.setLibrarySort(sort) }
            }
        }
        let built = state.prefs[.onlyBuilt]
        let rest = HStack(spacing: 10) {
            chip("console.grid.onlyBuilt", symbol: built ? "checkmark.circle.fill" : "circle", title: t(ConsolePref.onlyBuilt.titleKey), on: built) {
                driver.setPref(.onlyBuilt, on: !built)
            }
            .accessibilityValue(built ? "1" : "0")
        }
        if compact { VStack(alignment: .leading, spacing: 10) { order; rest } }   // narrow: the order on a line of its own
        else { HStack(spacing: 24) { order; rest; Spacer(minLength: 0) } }
    }

    private func chip(_ id: String, symbol: String? = nil, title: String, on: Bool, action: @escaping () -> Void) -> some View {
        let height: CGFloat = compact ? 40 : 48
        return Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: compact ? 14 : 17, weight: .semibold)).accessibilityHidden(true) }
                Text(title).font(.manrope(compact ? 15 : 18, on ? .bold : .semibold)).lineLimit(1)
            }
            .padding(.horizontal, compact ? 14 : 18).frame(height: height)
            .foregroundStyle(on ? LauncherPalette.background : .white.opacity(0.88))
            // the outline is a filled pill under the chip's own, 1 pt larger: a stroked pill drew marks at its ends
            .background(on ? LauncherPalette.cream : Color(white: 0.125), in: Capsule()).padding(on ? 0 : 1)
            .background(on ? .clear : Color(white: 0.24), in: Capsule()).padding(on ? 1 : 0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title).accessibilityAddTraits(on ? .isSelected : [])
        .padTarget(id, scope: scope, radius: height / 2 + 1, activate: action)
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
                ConsoleGameTile(game: game, compact: compact, lang: lang).contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padTarget(id, scope: scope, radius: 16, activate: pick)
            Text(game.title).font(.manrope(compact ? 14 : 18, .semibold)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                .padding(.horizontal, 4).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ConsoleSaveDot.accessibilityLabel(game, lang: lang))
        .accessibilityHint(t("console.grid.pick"))
        .id(id)
    }

    // MARK: Hints

    private var hints: some View {
        let swap = state.menuSwapAB
        let items = Group {
            hint([glyphs.glyph(for: .activate, on: ConsoleButtons.button(for: .activate, swapAB: swap))], "console.grid.pick")
            hint([glyphs.glyph(for: .options, on: ConsoleButtons.button(for: .options, swapAB: swap))], "console.options")
            hint([glyphs.shoulder("L"), glyphs.shoulder("R")], "console.grid.page")
            if !compact { hint([glyphs.shoulder("ZL"), glyphs.shoulder("ZR")], "console.grid.ends") }
            hint([glyphs.glyph(for: .back, on: ConsoleButtons.button(for: .back, swapAB: swap))], "console.close")
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
