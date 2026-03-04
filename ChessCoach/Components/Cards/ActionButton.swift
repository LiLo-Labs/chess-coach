import SwiftUI

/// Normalized action button using RoundedRectangle instead of Capsule.
/// Fixes GitHub issue #8: "Buttons too oval".
struct ActionButton: View {
    let title: String
    let icon: String?
    let color: Color
    let foregroundColor: Color
    let cornerRadius: CGFloat
    let isFullWidth: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        color: Color = AppColor.guided,
        foregroundColor: Color = AppColor.primaryText,
        cornerRadius: CGFloat = AppRadius.md,
        isFullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.foregroundColor = foregroundColor
        self.cornerRadius = cornerRadius
        self.isFullWidth = isFullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                }
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.horizontal, isFullWidth ? 0 : AppSpacing.xxl)
            .padding(.vertical, AppSpacing.md)
            .background(color, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
    }
}

/// Button style modifier that replaces Capsule with RoundedRectangle.
/// Use for inline button styling where ActionButton wrapper is too rigid.
struct RoundedButtonStyle: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat

    init(_ color: Color, cornerRadius: CGFloat = AppRadius.md) {
        self.color = color
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        content
            .background(color, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Replaces `.background(color, in: Capsule())` for button shapes.
    func buttonBackground(_ color: Color, cornerRadius: CGFloat = AppRadius.md) -> some View {
        modifier(RoundedButtonStyle(color, cornerRadius: cornerRadius))
    }
}
