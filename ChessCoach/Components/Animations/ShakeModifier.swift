import SwiftUI

/// A view modifier that shakes the view horizontally to indicate a wrong answer.
/// The shake triggers whenever `trigger` changes.
/// Automatically disables when the user has enabled Reduce Motion.
struct ShakeModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var trigger: Int
    var amplitude: CGFloat
    var count: Int

    @State private var shakeOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: trigger) {
                guard !reduceMotion else { return }
                performShake()
            }
    }

    private func performShake() {
        let totalSteps = count * 2
        let stepDuration = 0.06

        for step in 0..<totalSteps {
            let direction: CGFloat = step.isMultiple(of: 2) ? 1 : -1
            let delay = Double(step) * stepDuration

            withAnimation(.easeInOut(duration: stepDuration).delay(delay)) {
                shakeOffset = amplitude * direction
            }
        }

        // Return to center after the last step
        let resetDelay = Double(totalSteps) * stepDuration
        withAnimation(.easeInOut(duration: stepDuration).delay(resetDelay)) {
            shakeOffset = 0
        }
    }
}

extension View {
    /// Applies a horizontal shake animation each time `trigger` changes.
    /// - Parameters:
    ///   - trigger: An integer that triggers the shake when it changes.
    ///   - amplitude: How far the view moves from center. Default is `10`.
    ///   - count: Number of full back-and-forth oscillations. Default is `3`.
    func shake(trigger: Int, amplitude: CGFloat = 10, count: Int = 3) -> some View {
        modifier(ShakeModifier(trigger: trigger, amplitude: amplitude, count: count))
    }
}
