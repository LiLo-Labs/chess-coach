import SwiftUI

/// Reusable bot portrait view with SF Symbol fallback.
struct BotAvatarView: View {
    let personality: OpponentPersonality
    let size: AvatarSize

    enum AvatarSize {
        case small  // 32pt — bot cards, inline headers
        case large  // 64pt — setup avatar, game over

        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .large: return 64
            }
        }

        var assetName: (OpponentPersonality) -> String {
            switch self {
            case .small: return { $0.portraitSmall }
            case .large: return { $0.portraitLarge }
            }
        }

        var fallbackFontSize: CGFloat {
            switch self {
            case .small: return 18
            case .large: return 36
            }
        }
    }

    var body: some View {
        Group {
            if let uiImage = UIImage(named: size.assetName(personality)) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Fallback to SF Symbol when portrait assets aren't available
                Image(systemName: personality.icon)
                    .font(.system(size: size.fallbackFontSize))
                    .foregroundStyle(accentColor)
            }
        }
        .frame(width: size.dimension, height: size.dimension)
        .clipShape(Circle())
        .accessibilityLabel("\(personality.name)")
    }

    private var accentColor: Color {
        switch personality.accentColorName {
        case "green": return .green
        case "teal": return .teal
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "orange": return .orange
        default: return .blue
        }
    }
}
