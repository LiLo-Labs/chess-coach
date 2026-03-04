import SwiftUI

/// Standalone top bar for gameplay screens: back button, title, chat toggle, overflow menu.
struct GameTopBar: View {
    // MARK: - Title Data

    let title: String
    let subtitle: String?

    // MARK: - Feature Flags

    let showChatToggle: Bool
    let isChatOpen: Bool
    let showBetaOptions: Bool

    // MARK: - Menu State

    let canUndo: Bool
    let canRedo: Bool
    let isTrainerMode: Bool

    // MARK: - Callbacks

    let onBack: () -> Void
    let onChatToggle: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onRestart: () -> Void
    let onResign: () -> Void
    let onReportBug: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        showChatToggle: Bool = false,
        isChatOpen: Bool = false,
        showBetaOptions: Bool = false,
        canUndo: Bool = false,
        canRedo: Bool = false,
        isTrainerMode: Bool = false,
        onBack: @escaping () -> Void,
        onChatToggle: @escaping () -> Void = {},
        onUndo: @escaping () -> Void = {},
        onRedo: @escaping () -> Void = {},
        onRestart: @escaping () -> Void = {},
        onResign: @escaping () -> Void = {},
        onReportBug: @escaping () -> Void = {}
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showChatToggle = showChatToggle
        self.isChatOpen = isChatOpen
        self.showBetaOptions = showBetaOptions
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.isTrainerMode = isTrainerMode
        self.onBack = onBack
        self.onChatToggle = onChatToggle
        self.onUndo = onUndo
        self.onRedo = onRedo
        self.onRestart = onRestart
        self.onResign = onResign
        self.onReportBug = onReportBug
    }

    var body: some View {
        HStack(spacing: 0) {
            backButton
            Spacer()
            titleView
            Spacer()
            if showChatToggle { chatButton }
            menuButton
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.top, AppSpacing.topBarSafeArea)
        .padding(.bottom, 4)
    }

    // MARK: - Subviews

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var titleView: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var chatButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                onChatToggle()
            }
        } label: {
            Image(systemName: isChatOpen ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                .font(.body)
                .foregroundStyle(isChatOpen ? AppColor.practice : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isChatOpen ? "Close coach chat" : "Open coach chat")
    }

    private var menuButton: some View {
        Menu {
            Button(action: onUndo) {
                Label("Undo Move", systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndo)

            Button(action: onRedo) {
                Label("Redo Move", systemImage: "arrow.uturn.forward")
            }
            .disabled(!canRedo)

            Divider()

            if isTrainerMode {
                Button(role: .destructive, action: onResign) {
                    Label("Resign", systemImage: "flag.fill")
                }
            } else {
                Button(action: onRestart) {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
            }

            if showBetaOptions {
                Button(action: onReportBug) {
                    Label("Report Bug", systemImage: "ladybug.fill")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options")
    }
}
