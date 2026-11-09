import Foundation

/// Semantic inputs from a future controller adapter; the view does not discover hardware.
enum ConsoleInput {
    case left, right, up, down, activate, back, options, menu
    /// The library page's: a screen back or on (L, R), its first or last game (ZL, ZR). Nothing elsewhere.
    case pageBack, pageForward, first, last
    /// The library page's display chips (its order, Only built games) take the focus, or give it back to the grid: R3, or F.
    case displayMode

    /// The launcher's controller path (Gamepad.swift) in console terms: the D-pad and left stick move, A activates, B backs out,
    /// Y opens the focused game's options, the menu button (+, Menu, Options) and the Select-type button (−, View, Share,
    /// Create) the console's menu. The same button again closes what it opened. L, R, ZL and ZR page the library. X is not used.
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
        case .l: self = .pageBack
        case .r: self = .pageForward
        case .zl: self = .first
        case .zr: self = .last
        case .rs: self = .displayMode
        case .x: return nil
        }
    }
}
