import SwiftUI

/// Animated "typing" dots indicator — three circles that pulse in sequence.
struct ThinkingDotsView: View {
    @State private var activeIndex = 0

    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppColor.guided.opacity(index == activeIndex ? 0.9 : 0.3))
                    .frame(width: 6, height: 6)
                    .scaleEffect(index == activeIndex ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: activeIndex)
            }
        }
        .onReceive(timer) { _ in
            activeIndex = (activeIndex + 1) % 3
        }
    }
}
