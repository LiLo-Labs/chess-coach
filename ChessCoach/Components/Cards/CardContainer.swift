import SwiftUI

/// Reusable card wrapper that applies the standard card background with rounded corners.
/// Replaces scattered `.background(AppColor.cardBackground, in: RoundedRectangle(...))` patterns.
struct CardContainer<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat?
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = AppRadius.md,
        padding: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        Group {
            if let padding {
                content()
                    .padding(padding)
            } else {
                content()
            }
        }
        .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// View modifier variant for applying card background to any view.
struct CardBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Applies the standard card background with the given corner radius.
    func cardBackground(cornerRadius: CGFloat = AppRadius.md) -> some View {
        modifier(CardBackgroundModifier(cornerRadius: cornerRadius))
    }
}
