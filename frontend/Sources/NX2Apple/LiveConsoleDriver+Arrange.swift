import Foundation

/// Arranging the row in console mode (RB, #937). The state moves the held game on screen; the library keeps the move as its Custom
/// order, which takes over from Recent or Name on the desktop too. The first move starts Custom from the order on screen, so nothing jumps.
extension LiveConsoleDriver {
    func toggleArranging() { state.toggleArranging() }
    func toggleHold() { state.toggleHold() }
    func pickUp(_ gameID: String) { state.pickUp(gameID) }
    func putDown() { state.putDown() }

    /// Recent or Name from the General page ends an arranged order, as the desktop's choice does; Custom keeps the row as it is.
    func setLibraryOrder(_ order: LibraryOrder) {
        if order == .custom, LibraryOrder.load() != .custom { library.adoptOrder(LibraryOrder.load().arrange(library.games).map(\.id)) }
        order.save()
        state.prefs.order = order
        refresh()
    }

    func moveHeld(_ step: Int) {
        guard let id = state.heldGameID.flatMap(UUID.init(uuidString:)), let before = state.moveHeld(step) else { return }
        let order = LibraryOrder.load()
        if order != .custom {
            library.adoptOrder(order.arrange(library.games).map(\.id))
            LibraryOrder.custom.save()
        }
        library.move(id, by: step, among: before.compactMap(UUID.init(uuidString:)))
    }
}
