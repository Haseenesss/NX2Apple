import SwiftUI
import NXLauncher
import NXModel

/// How a game's cover says whether the game can be opened (LNPANDY/NX2Apple#937): in colour once it has a build, in grey without
/// one. While its build runs the cover carries the build's progress, and a grey cover comes to colour when the build is done, so
/// the card that showed up when the build started turns into the game. The desktop's cards and console mode's tiles share it.
struct CoverLook: Equatable {
    /// In colour: the game has a build it can open (on the desktop a Mac or an iPhone build, in console mode a Mac build).
    var built: Bool
    /// This game's build is running.
    var building = false
    /// How far the running stage is, 0 to 1, as the build's own progress shows it; nil while the stage gives no figure.
    var fraction: Double?

    /// Grey and a little darker: the cover is still read (its picture tells the game apart), it just does not look ready.
    static let greyBrightness = -0.25
}

extension BuildStore {
    /// How far the running stage is, 0 to 1: the figure the desktop's activity bar and console mode's build chip show. The script
    /// reports a percentage for the current step, not for all the work left.
    var stageFraction: Double? {
        stages.last { $0.state == .running }?.percent.map { $0 / 100 }
    }
}

extension View {
    /// The cover drawn with `look`: grey or in colour, and the build's progress over its bottom edge while it runs. `label` names the
    /// build ("Building"), nil for none; `percent` is the figure beside the bar, written as the build's other progress writes it.
    func coverLook(_ look: CoverLook, label: String? = nil, percent: String? = nil, tint: Color, scale: CGFloat = 1) -> some View {
        modifier(CoverLookModifier(look: look, label: label, percent: percent, tint: tint, scale: scale))
    }
}

private struct CoverLookModifier: ViewModifier {
    let look: CoverLook
    let label: String?
    let percent: String?
    let tint: Color
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .saturation(look.built ? 1 : 0)
            .brightness(look.built ? 0 : CoverLook.greyBrightness)
            .overlay(alignment: .bottom) {
                if look.building { progress.transition(.opacity) }
            }
            // The colour comes in slowly enough to be seen as the build's end; the progress leaves quickly
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: look.built)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: look.building)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            if label != nil || percent != nil {
                HStack(spacing: 7 * scale) {
                    if let label {
                        Text(label).font(.manrope(12 * scale, .semibold)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let percent {
                        Text(percent).font(.manrope(12 * scale, .semibold)).monospacedDigit()
                    }
                }
                .foregroundStyle(.white.opacity(0.92))
            }
            LauncherProgressBar(value: look.fraction, height: 4 * scale, tint: tint)
                .frame(height: 4 * scale)
        }
        .padding(.horizontal, 10 * scale).padding(.bottom, 9 * scale).padding(.top, 22 * scale)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)   // the card's status says "Building" already
    }
}
