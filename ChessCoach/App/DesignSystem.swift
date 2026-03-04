import SwiftUI

/// App-wide color palette.
enum AppColor {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let cardBackground = Color(white: 0.16)
    static let elevatedBackground = Color(white: 0.14)
    static let inputBackground = Color(white: 0.18)

    static let study = Color.cyan
    static let guided = Color.blue
    static let unguided = Color.orange
    static let practice = Color.purple

    static let success = Color.green
    static let error = Color.red
    static let warning = Color.yellow
    static let info = Color.cyan

    // MARK: - Familiarity Colors
    static func familiarity(_ tier: FamiliarityTier) -> Color {
        switch tier {
        case .learning: return .cyan
        case .practicing: return .blue
        case .familiar: return .green
        }
    }

    static func familiarityIcon(_ tier: FamiliarityTier) -> String {
        switch tier {
        case .learning: return "book.fill"
        case .practicing: return "target"
        case .familiar: return "checkmark.seal.fill"
        }
    }

    /// Interpolated familiarity color from progress 0.0–1.0.
    static func familiarityColor(progress: Double) -> Color {
        familiarity(FamiliarityTier.from(progress: progress))
    }

    static func pesColor(_ category: ScoreCategory) -> Color {
        switch category {
        case .masterful: return .yellow
        case .strong: return .green
        case .solid: return .blue
        case .developing: return .orange
        case .needsWork: return .red
        }
    }

    static let arrowSuggestion = Color.green.opacity(0.55)
    static let arrowMistake = Color.red.opacity(0.55)
    static let arrowHistory = Color.white.opacity(0.25)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.65)
    static let tertiaryText = Color.white.opacity(0.4)
    static let disabledText = Color.white.opacity(0.25)

    static let gold = Color.yellow
    static let silver = Color(white: 0.75)
    static let bronze = Color(red: 0.80, green: 0.50, blue: 0.20)
}

enum AppSpacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32

    static let cardPadding: CGFloat = 16
    static let screenPadding: CGFloat = 16
    static let topBarSafeArea: CGFloat = 54
}


enum AppRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 14
    static let xl: CGFloat = 20
}


struct PillBadge: View {
    let text: String
    let color: Color
    var fontSize: CGFloat = 10

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .accessibilityLabel(text)
    }
}


struct ModeIndicator: View {
    let mode: String
    let color: Color

    var body: some View {
        PillBadge(text: mode.uppercased(), color: color)
            .accessibilityLabel(mode)
    }
}


struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(AppColor.tertiaryText)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.primaryText)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .buttonBackground(AppColor.guided)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .padding(AppSpacing.xxxl)
    }
}


struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 3
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Progress: \(Int(progress * 100))%")
    }
}


struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = AppColor.primaryText

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColor.primaryText)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(AppColor.secondaryText)
        }
    }
}


enum AchievementTier: String {
    case gold, silver, bronze

    var color: Color {
        switch self {
        case .gold: return AppColor.gold
        case .silver: return AppColor.silver
        case .bronze: return AppColor.bronze
        }
    }

    var icon: String {
        switch self {
        case .gold: return "medal.fill"
        case .silver: return "medal.fill"
        case .bronze: return "medal.fill"
        }
    }
}

struct AchievementBadge: View {
    let tier: AchievementTier
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tier.icon)
                .font(.system(size: 12))
                .foregroundStyle(tier.color)
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(tier.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tier.color.opacity(0.12), in: Capsule())
    }
}


enum TimeAgo {
    static func string(from date: Date?) -> String {
        guard let date else { return "Never" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        let days = Int(seconds / 86400)
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }
        if days < 30 { return "\(days / 7)w ago" }
        return "\(days / 30)mo ago"
    }
}


/// Press-scale button style.
struct ScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.95 : 1.0))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.15, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
