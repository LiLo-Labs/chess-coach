import SwiftUI

// MARK: - Semantic Color System

/// Centralized color definitions for the entire app.
/// Every color in the app should reference this enum to ensure consistency.
enum AppColor {
    // MARK: Backgrounds
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let cardBackground = Color(white: 0.16)
    static let elevatedBackground = Color(white: 0.14)
    static let inputBackground = Color(white: 0.18)

    // MARK: Training Pipeline (semantic)
    static let study = Color.cyan
    static let guided = Color.blue
    static let unguided = Color.orange
    static let practice = Color.purple

    // MARK: Feedback
    static let success = Color.green
    static let error = Color.red
    static let warning = Color.yellow
    static let info = Color.cyan

    // MARK: Phase Colors
    static func phase(_ phase: LearningPhase) -> Color {
        switch phase {
        case .learningMainLine: return guided
        case .naturalDeviations: return .green
        case .widerVariations: return unguided
        case .freePlay: return practice
        }
    }

    // MARK: Arrow Colors
    static let arrowSuggestion = Color.green.opacity(0.55)
    static let arrowMistake = Color.red.opacity(0.55)
    static let arrowHistory = Color.white.opacity(0.25)

    // MARK: Text
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.65)
    static let tertiaryText = Color.white.opacity(0.4)
    static let disabledText = Color.white.opacity(0.25)

    // MARK: Achievement Tiers
    static let gold = Color.yellow
    static let silver = Color(white: 0.75)
    static let bronze = Color(red: 0.80, green: 0.50, blue: 0.20)
}

// MARK: - Spacing System

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

    /// Standard card internal padding
    static let cardPadding: CGFloat = 16
    /// Standard horizontal padding for screen content
    static let screenPadding: CGFloat = 16
    /// Top bar safe area padding (for fullScreenCover views)
    static let topBarSafeArea: CGFloat = 54
}

// MARK: - Corner Radius

enum AppRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 14
    static let xl: CGFloat = 20
}

// MARK: - Reusable Card Style

struct AppCardModifier: ViewModifier {
    var padding: CGFloat = AppSpacing.cardPadding
    var radius: CGFloat = AppRadius.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    func appCard(padding: CGFloat = AppSpacing.cardPadding, radius: CGFloat = AppRadius.md) -> some View {
        modifier(AppCardModifier(padding: padding, radius: radius))
    }
}

// MARK: - Badge / Pill Style

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

// MARK: - Mode Indicator

struct ModeIndicator: View {
    let mode: String
    let color: Color

    var body: some View {
        PillBadge(text: mode.uppercased(), color: color)
            .accessibilityLabel(mode)
    }
}

// MARK: - Empty State View

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
                        .background(AppColor.guided, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .padding(AppSpacing.xxxl)
    }
}

// MARK: - Progress Ring

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

// MARK: - Stat Row

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

// MARK: - Achievement Badge

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

// MARK: - Animated Counter

struct AnimatedCounter: View {
    let value: Int
    var font: Font = .system(size: 48, weight: .bold, design: .rounded)
    var color: Color = .white

    @State private var displayValue: Int = 0

    var body: some View {
        Text("\(displayValue)")
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(displayValue)))
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    displayValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    displayValue = newValue
                }
            }
    }
}

// MARK: - Gesture Hint Overlay

struct GestureHintView: View {
    let icon: String
    let text: String
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                Text(text)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation { isVisible = false }
                }
            }
        }
    }
}

// MARK: - Timestamp Formatter

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
