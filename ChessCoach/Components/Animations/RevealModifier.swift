import SwiftUI

/// A view modifier that reveals content with a spring animation (scale + opacity).
/// Used for score reveals, promotion banners, and milestone announcements.
/// Automatically disables when the user has enabled Reduce Motion.
struct RevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var isVisible: Bool
    var delay: Double
    var response: Double
    var dampingFraction: Double
    var initialScale: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(effectiveScale)
            .opacity(effectiveOpacity)
            .animation(reduceMotion ? nil : springAnimation, value: isVisible)
    }

    private var effectiveScale: Double {
        if reduceMotion { return 1.0 }
        return isVisible ? 1.0 : initialScale
    }

    private var effectiveOpacity: Double {
        if reduceMotion { return isVisible ? 1.0 : 0.0 }
        return isVisible ? 1.0 : 0.0
    }

    private var springAnimation: Animation {
        .spring(response: response, dampingFraction: dampingFraction)
        .delay(delay)
    }
}

extension View {
    /// Reveals the view with a spring scale-and-fade animation.
    /// - Parameters:
    ///   - isVisible: Whether the view should be shown.
    ///   - delay: Delay before the animation starts. Default is `0.3`.
    ///   - response: Spring response time. Default is `0.5`.
    ///   - dampingFraction: Spring damping. Default is `0.7`.
    ///   - initialScale: Starting scale before reveal. Default is `0.5`.
    func reveal(
        isVisible: Bool,
        delay: Double = 0.3,
        response: Double = 0.5,
        dampingFraction: Double = 0.7,
        initialScale: Double = 0.5
    ) -> some View {
        modifier(RevealModifier(
            isVisible: isVisible,
            delay: delay,
            response: response,
            dampingFraction: dampingFraction,
            initialScale: initialScale
        ))
    }
}
