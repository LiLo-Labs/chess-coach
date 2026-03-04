import SwiftUI

/// A view modifier that reveals content with a spring animation (scale + opacity).
/// Used for score reveals, promotion banners, and milestone announcements.
/// Automatically disables when the user has enabled Reduce Motion.
struct RevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var isVisible: Bool
    var delay: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1.0 : (isVisible ? 1.0 : 0.5))
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7).delay(delay), value: isVisible)
    }
}

extension View {
    /// Reveals the view with a spring scale-and-fade animation.
    /// - Parameters:
    ///   - isVisible: Whether the view should be shown.
    ///   - delay: Delay before the animation starts. Default is `0.3`.
    func reveal(
        isVisible: Bool,
        delay: Double = 0.3
    ) -> some View {
        modifier(RevealModifier(
            isVisible: isVisible,
            delay: delay
        ))
    }
}
