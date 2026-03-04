import SwiftUI

/// A view modifier that applies a repeating pulse (opacity fade) animation.
/// Used for the "YOUR MOVE" badge and streak flame indicators.
/// Automatically disables when the user has enabled Reduce Motion.
struct PulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var minOpacity: Double
    var duration: Double

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .phaseAnimator([false, true]) { view, phase in
                    view.opacity(phase ? 1.0 : minOpacity)
                } animation: { _ in .easeInOut(duration: duration) }
        }
    }
}

extension View {
    /// Applies a repeating pulse animation that fades opacity between full and `minOpacity`.
    /// - Parameters:
    ///   - minOpacity: The lowest opacity value in the cycle. Default is `0.6`.
    ///   - duration: The duration of one half-cycle. Default is `0.8` seconds.
    func pulse(minOpacity: Double = 0.6, duration: Double = 0.8) -> some View {
        modifier(PulseModifier(minOpacity: minOpacity, duration: duration))
    }
}
