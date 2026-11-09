import Foundation

/// Semantic inputs from a future controller adapter; the view does not discover hardware.
enum ConsoleInput {
    case left, right, up, down, activate, back, options, menu
    /// R (RB, R1) on the home screen: arrange the row (#937).
    case arrange
    /// The library page's: its first or last game (ZL, ZR). Nothing elsewhere.
    case first, last
    /// The library page's display chips (its order, Only built games) take the focus, or give it back to the grid: R3, or F.
    case displayMode

    /// The launcher's controller path (Gamepad.swift) in console terms: the D-pad and left stick move, A activates, B backs out,
    /// Y opens the focused game's options, the menu button (+, Menu, Options) and the Select-type button (−, View, Share,
    /// Create) the console's menu, R (RB, R1) arranges the row, ZL and ZR go to the library page's first or last game, R3 its
    /// display chips. The same button again closes what it opened. X and L are not used.
    init?(_ action: LauncherGamepad.Action) {
        switch action {
        case .left: self = .left
        case .right: self = .right
        case .up: self = .up
        case .down: self = .down
        case .a: self = .activate
        case .b: self = .back
        case .y: self = .options
        case .plus, .select: self = .menu
        case .zl: self = .first
        case .zr: self = .last
        case .rs: self = .displayMode
        case .r: self = .arrange
        case .x, .l: return nil
        }
    }
}
