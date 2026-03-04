import SwiftUI

/// Reusable correct/incorrect move feedback overlay.
/// Used in puzzles, ELO assessment, and practice sessions.
struct MoveFeedbackView: View {
    let isCorrect: Bool
    var message: String?
    var solutionText: String?
    var actionLabel: String = "Next"
    var onAction: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(isCorrect ? AppColor.success : AppColor.error)
                .scaleEffect(appeared ? 1.0 : 0.3)
                .opacity(appeared ? 1.0 : 0)

            Text(isCorrect ? "Correct!" : "Not quite")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxl)
            }

            if !isCorrect, let solutionText {
                Text(solutionText)
                    .font(.caption)
                    .foregroundStyle(AppColor.tertiaryText)
                    .multilineTextAlignment(.center)
            }

            Button(action: onAction) {
                Text(actionLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.info, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, AppSpacing.xxl)
        }
        .sensoryFeedback(isCorrect ? .success : .error, trigger: appeared)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}
