import SwiftUI
import NXLauncher

/// How a tile looks while the row is arranged (RB, #937). The focused tile rises a little; the one picked up (A) rises further, grows
/// and casts a shadow, leaving the row, with arrows on the sides it can move to; the others step back while one is held.
private struct ConsoleArrangeLook: ViewModifier {
    let arranging: Bool, focused: Bool, held: Bool, anyHeld: Bool, canLeft: Bool, canRight: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(held ? 1.08 : 1)
            .shadow(color: .black.opacity(held ? 0.6 : 0), radius: held ? 30 : 0, y: held ? 24 : 0)
            .overlay {
                if held {
                    HStack {
                        arrow("chevron.left").opacity(canLeft ? 1 : 0)
                        Spacer(minLength: 0)
                        arrow("chevron.right").opacity(canRight ? 1 : 0)
                    }
                    .padding(.horizontal, -6)
                    .transition(.opacity)
                }
            }
            .offset(y: held ? -52 : (arranging && focused ? -22 : 0))
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
    func arrangeLook(arranging: Bool, focused: Bool, held: Bool, anyHeld: Bool, canLeft: Bool, canRight: Bool) -> some View {
        modifier(ConsoleArrangeLook(arranging: arranging, focused: focused, held: held, anyHeld: anyHeld, canLeft: canLeft, canRight: canRight))
    }
}
