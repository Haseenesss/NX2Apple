import SwiftUI
import NXCore
import NXLauncher

// The console's cards: a game's cover (generated from its title when it has none), and the home row's library tile.

/// Reusable 1.8:1 presentation; nil artwork uses the same quiet surface as the desktop library.
/// A cover drawn from the title alone, in the launcher's palette: a dark gradient tinted by one of its accents, and the name.
/// Nothing is loaded or bundled. The same title always gets the same colors.
enum ConsolePlaceholder {
    static func colors(for title: String) -> [Color] {
        let accents = [LauncherPalette.cream, LauncherPalette.ready, LauncherPalette.building, LauncherPalette.unbuilt]
        let seed = title.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        let accent = accents[abs(seed) % accents.count]
        return [accent.opacity(0.42), LauncherPalette.surface, LauncherPalette.background]
    }
}

struct ConsoleArtwork: View {
    let image: NSImage?
    var title = ""
    var focus = UnitPoint.center
    var body: some View {
        GeometryReader { geometry in
            if let image { ArtworkFill(image: image, focus: focus).frame(width: geometry.size.width, height: geometry.size.height) }
            else {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: ConsolePlaceholder.colors(for: title), startPoint: .topLeading, endPoint: .bottomTrailing)
                    if title.isEmpty { Image(systemName: "gamecontroller").font(.system(size: 50)).foregroundStyle(.secondary) }
                    else {
                        Text(title).font(.manrope(max(14, geometry.size.width / 11), .bold)).foregroundStyle(LauncherPalette.cream.opacity(0.9))
                            .lineLimit(3).minimumScaleFactor(0.6).padding(geometry.size.width / 18)
                    }
                }
            }
        }
    }
}

/// A game's cover alone: the focused game's name is the big title above the row, so no tile carries a caption.
struct ConsoleGameTile: View {
    let game: ConsoleGame
    let compact: Bool
    let lang: Lang
    /// The cloud save's dot (ConsoleSaveDot): on the library page, not on the home row.
    var showsSaveDot = false
    var body: some View {
        ConsoleArtwork(image: game.artwork, title: game.title, focus: game.artworkFocus).aspectRatio(1.8, contentMode: .fit)
            .opacity(game.status == .ready ? 1 : 0.45)   // not playable on this Mac: dimmed, its status on top
            .overlay(alignment: .bottomLeading) {
                if game.status != .ready {
                    Text(L10n.string(game.status.labelKey, lang)).font(.manrope(compact ? 14 : 18, .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(LauncherPalette.background.opacity(0.93), in: Capsule()).padding(14)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12), lineWidth: 1))
            // the cloud save's dot, 12 pt in from the bottom left; at the bottom right where the status capsule takes that corner
            .overlay(alignment: game.status == .ready ? .bottomLeading : .bottomTrailing) {
                if showsSaveDot, let dot = ConsoleSaveDot(game.save?.status) { ConsoleSaveDotView(dot: dot, compact: compact).padding(12) }
            }
    }
}

/// The home row's last tile, the size of a game's: the library's symbol, its name and its count, on a dark card.
struct ConsoleLibraryTile: View {
    let title: String
    let count: String
    let compact: Bool
    var body: some View {
        Color.clear.aspectRatio(1.8, contentMode: .fit)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                    Image(systemName: "square.grid.2x2.fill").font(.system(size: compact ? 26 : 34, weight: .medium))
                        .foregroundStyle(LauncherPalette.cream.opacity(0.9)).padding(.bottom, compact ? 2 : 6).accessibilityHidden(true)
                    Text(title).font(.manrope(compact ? 19 : 24, .bold)).foregroundStyle(LauncherPalette.cream).lineLimit(1).minimumScaleFactor(0.7)
                    Text(count).font(.manrope(compact ? 13 : 16, .medium)).foregroundStyle(.white.opacity(0.62)).lineLimit(2).minimumScaleFactor(0.8)
                }
                .padding(compact ? 18 : 26)
            }
            .background(LinearGradient(colors: [Color(red: 0.125, green: 0.141, blue: 0.169), Color(red: 0.067, green: 0.075, blue: 0.09)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LauncherPalette.cream.opacity(0.25), lineWidth: 1))
    }
}

/// A cover's dot for its cloud save (ConsoleGame.save): green in step with the cloud, yellow a save on this Mac the cloud does not
/// have yet (waiting, failed, not synced, the folder missing), grey no save found. No dot without a save row (not built, or cloud
/// saves off for the game: nothing is known).
enum ConsoleSaveDot: Equatable {
    case synced, localOnly, noSave

    init?(_ status: ConsoleSaveStatus?) {
        switch status {
        case .synced?: self = .synced
        case .pending?, .failed?, .notSynced?, .missingFolder?: self = .localOnly
        case .noSave?, .notPlayed?: self = .noSave
        case .off?, nil: return nil
        }
    }

    var color: Color {
        switch self {
        case .synced: return LauncherPalette.ready
        case .localOnly: return CloudSavesCard.attention
        case .noSave: return .white.opacity(0.35)
        }
    }

    /// The game's name, its status, and its save's state when it has a dot (VoiceOver).
    static func accessibilityLabel(_ game: ConsoleGame, lang: Lang) -> String {
        var parts = [game.title, L10n.string(game.status.labelKey, lang)]
        if let save = game.save, ConsoleSaveDot(save.status) != nil { parts.append(L10n.string(save.status.key, lang)) }
        return parts.joined(separator: ", ")
    }
}

struct ConsoleSaveDotView: View {
    let dot: ConsoleSaveDot
    let compact: Bool
    var body: some View {
        Circle().fill(dot.color).frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
            .overlay(Circle().strokeBorder(LauncherPalette.background.opacity(0.85), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// The width each button of the Home button hint was drawn at, by its pad id: ConsoleTests checks that it is the same in every language.
struct ConsoleButtonWidths: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue()) { _, new in new } }
    static func reader(_ id: String) -> some View { GeometryReader { g in Color.clear.preference(key: ConsoleButtonWidths.self, value: [id: g.size.width]) } }
}

struct ConsoleTileFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { _, new in new } }
}
