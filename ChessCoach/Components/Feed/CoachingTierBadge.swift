import SwiftUI

/// Small badge indicating the coaching analysis tier: "Basic" or "AI Coach".
struct CoachingTierBadge: View {
    let isLLM: Bool

    var label: String { isLLM ? "AI Coach" : "Basic" }

    private var color: Color { isLLM ? AppColor.info : AppColor.tertiaryText }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("\(label) analysis")
    }
}
