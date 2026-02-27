import SwiftUI

/// Animated confetti particles shown on line completion (improvement 18).
struct ConfettiView: View {
    @State private var particles: [Particle] = []
    @State private var isAnimating = false

    private let colors: [Color] = [.yellow, .green, .blue, .orange, .pink, .purple, .cyan]
    private let particleCount = 50

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        let targetX: CGFloat
        let targetY: CGFloat
        let size: CGFloat
        let color: Color
        let rotation: Double
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                for particle in particles {
                    let currentX = isAnimating ? particle.targetX : particle.x
                    let currentY = isAnimating ? particle.targetY : particle.y
                    let opacity = isAnimating ? 0.0 : 1.0

                    var transform = CGAffineTransform.identity
                    transform = transform.translatedBy(x: currentX, y: currentY)
                    transform = transform.rotated(by: isAnimating ? particle.rotation * 4 : 0)

                    context.opacity = opacity
                    context.fill(
                        Path(CGRect(
                            x: -particle.size / 2,
                            y: -particle.size / 2,
                            width: particle.size,
                            height: particle.size
                        )).applying(transform),
                        with: .color(particle.color)
                    )
                }
            }
            .onAppear {
                let centerX = geo.size.width / 2
                let centerY = geo.size.height / 3

                particles = (0..<particleCount).map { _ in
                    let angle = Double.random(in: 0...(2 * .pi))
                    let distance = CGFloat.random(in: 100...300)
                    return Particle(
                        x: centerX,
                        y: centerY,
                        targetX: centerX + cos(angle) * distance,
                        targetY: centerY + sin(angle) * distance + CGFloat.random(in: 50...200),
                        size: CGFloat.random(in: 4...10),
                        color: colors.randomElement() ?? .yellow,
                        rotation: Double.random(in: -3...3)
                    )
                }

                withAnimation(.spring(response: 1.2, dampingFraction: 0.6)) {
                    isAnimating = true
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
