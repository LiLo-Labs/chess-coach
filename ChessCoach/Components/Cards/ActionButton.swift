import SwiftUI

extension View {
    /// Applies a RoundedRectangle background — replaces `.background(color, in: Capsule())`
    /// for button shapes. Fixes GitHub issue #8: "Buttons too oval".
    func buttonBackground(_ color: Color, cornerRadius: CGFloat = AppRadius.md) -> some View {
        background(color, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
