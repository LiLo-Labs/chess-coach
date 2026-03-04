import SwiftUI

extension View {
    /// Applies the standard card background with the given corner radius.
    func cardBackground(cornerRadius: CGFloat = AppRadius.md) -> some View {
        background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
