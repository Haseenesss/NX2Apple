import SwiftUI
import NXLauncher

/// How a tile looks while the row is arranged (RB, #937). The focused tile rises a little; the one picked up (A) rises further, grows
/// and casts a shadow, leaving the row, with arrows on the sides it can move to; the others step back while one is held.
private struct ConsoleArrangeLook: ViewModifier {
    let arranging: Bool, focused: Bool, held: Bool, anyHeld: Bool, canLeft: Bool, canRight: Bool, scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .scaleEffect(held ? scale : 1)
            .shadow(color: .black.opacity(held ? 0.6 : 0), radius: held ? 30 : 0, y: held ? 24 : 0)
            .overlay {
                if held {
                    HStack {
                        arrow("chevron.left").opacity(canLeft ? 1 : 0)
                        Spacer(minLength: 0)
                        arrow("chevron.right").opacity(canRight ? 1 : 0)
                    }
                    .padding(.horizontal, -ConsoleArrange.arrowOverhang)
                    .transition(.opacity)
                }
            }
            .offset(y: held ? -52 : (arranging && focused ? -22 : 0))
            // left and right with nothing held move the focus: the tile left behind settles and the next one rises, as smoothly as a move
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78), value: focused)
            .opacity(anyHeld && !held ? 0.5 : 1)
            .zIndex(held ? 1 : 0)
    }
    private func arrow(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
            .frame(width: 40, height: 40)
            .background(LauncherPalette.cream, in: Circle())
            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            .accessibilityHidden(true)
    }
}

extension View {
    func arrangeLook(arranging: Bool, focused: Bool, held: Bool, anyHeld: Bool, canLeft: Bool, canRight: Bool, scale: CGFloat) -> some View {
        modifier(ConsoleArrangeLook(arranging: arranging, focused: focused, held: held, anyHeld: anyHeld, canLeft: canLeft, canRight: canRight, scale: scale))
    }
}

enum ConsoleArrange {
    /// How far the arrows stand out past a held tile's sides.
    static let arrowOverhang: CGFloat = 6
    static let maxScale: CGFloat = 1.08
    /// How much a held tile grows: up to `maxScale`, less when the room beside a tile at the row's end (`room`, from the tile's side
    /// to the screen's edge) would not hold the growth and the arrows, so it is never cut at the screen's edge.
    static func heldScale(width: CGFloat, room: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        let grow = max(0, room - arrowOverhang - 4)   // 4 pt left clear
        return min(maxScale, 1 + 2 * grow / width)
    }
}
