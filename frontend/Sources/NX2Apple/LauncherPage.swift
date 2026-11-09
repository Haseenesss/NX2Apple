import SwiftUI
import NXCore

enum LauncherPage: String, CaseIterable {
    case library, builds, settings
    var symbol: String {
        switch self {
        case .library: return "gamecontroller"
        case .builds: return "shippingbox"
        case .settings: return "slider.horizontal.3"
        }
    }
}

/// The library's filter: every game in the games folder, or only those with a build. Remembered between launches. The game being
/// built shows under Built as well: its card is there from the start of the build, greyed, and comes to colour when it is done.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case owned, built
    var id: String { rawValue }
    var labelKey: String { "filter." + rawValue }

    /// Owned shows every game without reading its build, so the default filter costs nothing per card. `building` is the library
    /// entry of the build running now (GameLibrary.buildingID), nil with none.
    func includes(_ game: LibraryGame, building: UUID? = nil) -> Bool {
        self == .owned || game.isReady || game.hasIOSBuild || game.id == building
    }

    /// The games this filter shows, in `order` (by name unless asked otherwise).
    func visibleGames(_ games: [LibraryGame], matching search: String = "", order: LibraryOrder = .name, building: UUID? = nil) -> [LibraryGame] {
        order.arrange(games.filter { (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) && includes($0, building: building) })
    }

    static func load(_ defaults: UserDefaults = .standard) -> LibraryFilter {
        LibraryFilter(rawValue: defaults.string(forKey: "libraryFilter") ?? "") ?? .owned
    }
    func save(_ defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: "libraryFilter") }

    /// The selection and the controller's focus after a switch to this filter. A selected game the filter hides gives way to the
    /// first one it shows, and a focus on a hidden card is dropped, so neither the hero nor the A button reaches a game that is not
    /// on screen.
    func reconcile(games: [LibraryGame], selectedID: UUID?, focused: String?, order: LibraryOrder = .name,
                   building: UUID? = nil) -> (selectedID: UUID?, focused: String?) {
        let shown = visibleGames(games, order: order, building: building)
        let selection = shown.contains { $0.id == selectedID } ? selectedID : shown.first?.id
        guard let focused, focused.hasPrefix("card.") else { return (selection, focused) }
        return (selection, shown.contains { "card." + $0.id.uuidString == focused } ? focused : nil)
    }
}

/// The order of the library's row (LNPANDY/NX2Apple#937). Recent puts the games last played first, the rest after them by name.
/// Name is Finder-style ordering on the display title. Custom is the order the player arranged in console mode, which is the
/// library's own order (`GameLibrary.games`): it takes over from Recent or Name, and a game added later goes to the end.
/// Remembered between launches; the desktop and console mode share it.
enum LibraryOrder: String, CaseIterable, Identifiable {
    case recent, name, custom
    var id: String { rawValue }
    var labelKey: String { "order." + rawValue }
    static let defaultsKey = "libraryOrder"
    /// What the desktop offers. Custom comes only from arranging the row in console mode (RB), and Recent or Name ends it.
    static let choices: [LibraryOrder] = [.recent, .name]

    func arrange(_ games: [LibraryGame]) -> [LibraryGame] {
        switch self {
        case .custom: return games
        case .name: return games.sorted(by: Self.byName)
        case .recent:
            return games.sorted { left, right in
                switch (left.lastPlayed, right.lastPlayed) {
                case let (l?, r?): return l == r ? Self.byName(left, right) : l > r
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return Self.byName(left, right)
                }
            }
        }
    }

    /// Different games can have the same title: the title ID decides then.
    static func byName(_ left: LibraryGame, _ right: LibraryGame) -> Bool {
        let order = left.name.localizedStandardCompare(right.name)
        return order == .orderedSame ? left.titleID < right.titleID : order == .orderedAscending
    }

    static func load(_ defaults: UserDefaults = .standard) -> LibraryOrder {
        LibraryOrder(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .recent
    }
    func save(_ defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.defaultsKey) }
}
