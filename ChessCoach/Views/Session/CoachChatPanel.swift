import SwiftUI

/// Chat message for the coach panel.
struct CoachChatMessage: Identifiable {
    let id = UUID()
    let role: String  // "user" or "coach"
    let text: String
}

/// Observable state that persists across panel open/close.
/// Create this in the parent view so it survives the panel being hidden.
@Observable
@MainActor
final class CoachChatState {
    var messages: [CoachChatMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var coachingService: CoachingService?

    func appendMessage(role: String, text: String) {
        messages.append(CoachChatMessage(role: role, text: text))
    }
}

/// Sliding side panel for AI coach chat during a session.
/// Has full board context, move history, and opening info pre-loaded.
struct CoachChatPanel: View {
    let opening: Opening
    let fen: String
    let moveHistory: [String]
    let currentPly: Int
    let coachPersonality: CoachPersonality
    var isEngineMode: Bool = false
    @Binding var isPresented: Bool
    var chatState: CoachChatState

    @Environment(AppServices.self) private var appServices

    private let suggestions = [
        "Why this move?",
        "What's the plan here?",
        "What should I watch for?",
        "How am I doing?"
    ]

    private var showSuggestions: Bool {
        // Show suggestions until the user sends their first question
        let hasUserMessage = chatState.messages.contains { $0.role == "user" }
        return !hasUserMessage && chatState.inputText.isEmpty && !chatState.isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                coachAvatar(size: 28)
                Text(coachPersonality.displayName(engineMode: isEngineMode))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppColor.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close coach chat")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppColor.cardBackground)

            Divider().opacity(0.3)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        // Welcome
                        chatBubble(
                            role: "coach",
                            text: "\(coachPersonality.displayName(engineMode: isEngineMode)) here! Ask me anything about the \(opening.name). I can see the board and your moves."
                        )

                        // Move history context
                        if !moveHistory.isEmpty {
                            moveHistorySection
                                .padding(.horizontal, 12)
                        }

                        if showSuggestions {
                            suggestionChips
                                .padding(.horizontal, 12)
                        }

                        ForEach(chatState.messages) { message in
                            chatBubble(role: message.role, text: message.text)
                                .id(message.id)
                        }

                        if chatState.isLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small).tint(AppColor.secondaryText)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(AppColor.secondaryText)
                            }
                            .padding(.horizontal, 12)
                            .id("loading")
                            .accessibilityLabel("Coach is thinking")
                        }
                    }
                    .padding(.vertical, 10)
                }
                .onChange(of: chatState.messages.count) {
                    if let last = chatState.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: chatState.isLoading) {
                    if chatState.isLoading { withAnimation { proxy.scrollTo("loading", anchor: .bottom) } }
                }
            }

            Divider().opacity(0.3)

            // Input
            HStack(spacing: 8) {
                TextField("Ask about this position...", text: Bindable(chatState).inputText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColor.inputBackground, in: RoundedRectangle(cornerRadius: 16))

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            chatState.inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? AppColor.disabledText
                                : AppColor.guided
                        )
                }
                .buttonStyle(.plain)
                .disabled(chatState.inputText.trimmingCharacters(in: .whitespaces).isEmpty || chatState.isLoading)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: 320)
        .background(AppColor.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 20, x: -5, y: 0)
    }

    // MARK: - Suggestion Chips

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Try asking...")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppColor.tertiaryText)

            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    chatState.inputText = suggestion
                } label: {
                    Text(suggestion)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .cardBackground(cornerRadius: AppRadius.sm)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Fills in the text field with this question")
            }
        }
    }

    // MARK: - Move History

    private var moveHistorySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "list.number")
                    .font(.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                    .accessibilityHidden(true)
                Text("Moves played (\(moveHistory.count))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppColor.tertiaryText)
            }

            // Show moves in pairs (1. e4 e5  2. Nf3 Nc6 ...)
            let paired = formattedMoveHistory
            Text(paired)
                .font(.caption2.monospaced())
                .foregroundStyle(AppColor.secondaryText)
                .lineLimit(4)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private var formattedMoveHistory: String {
        var result = ""
        for i in stride(from: 0, to: moveHistory.count, by: 2) {
            let moveNum = (i / 2) + 1
            let white = moveHistory[i]
            let black = i + 1 < moveHistory.count ? moveHistory[i + 1] : ""
            if !result.isEmpty { result += " " }
            result += "\(moveNum). \(white)"
            if !black.isEmpty { result += " \(black)" }
        }
        return result.isEmpty ? "No moves yet" : result
    }

    // MARK: - Coach Avatar

    @ViewBuilder
    private func coachAvatar(size: CGFloat) -> some View {
        let assetName = isEngineMode ? coachPersonality.enginePortraitSmall : ""
        if isEngineMode, let uiImage = UIImage(named: assetName) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: coachPersonality.displayIcon(engineMode: isEngineMode))
                .font(.system(size: size * 0.55))
                .foregroundStyle(AppColor.practice)
                .frame(width: size, height: size)
        }
    }

    // MARK: - Chat Bubble

    private func chatBubble(role: String, text: String) -> some View {
        let isUser = role == "user"
        let coachName = coachPersonality.displayName(engineMode: isEngineMode)
        return HStack {
            if isUser { Spacer(minLength: 20) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                if !isUser {
                    HStack(spacing: 3) {
                        coachAvatar(size: 14)
                            .accessibilityHidden(true)
                        Text(coachName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppColor.practice)
                            .accessibilityHidden(true)
                    }
                }

                Text(text)
                    .font(.caption)
                    .foregroundStyle(AppColor.primaryText.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(
                isUser ? AppColor.guided.opacity(0.2) : AppColor.cardBackground,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isUser ? "You: \(text)" : "\(coachName): \(text)")

            if !isUser { Spacer(minLength: 20) }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let question = chatState.inputText.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty else { return }

        chatState.appendMessage(role: "user", text: question)
        chatState.inputText = ""
        chatState.isLoading = true

        // Build conversation history from all prior messages (coaching + Q&A)
        let history = chatState.messages.map { (role: $0.role, text: $0.text) }

        let context = ChatContext(
            fen: fen,
            openingName: opening.name,
            lineName: opening.name,
            moveHistory: moveHistory,
            currentPly: currentPly,
            conversationHistory: history
        )

        // Capture what we need for the background task
        let state = chatState
        let services = appServices
        let openingRef = opening

        Task {
            if state.coachingService == nil {
                let llmService = services.llmService
                let line = openingRef.lines?.first ?? OpeningLine(
                    id: "\(openingRef.id)/main",
                    name: openingRef.name,
                    moves: openingRef.mainLine,
                    branchPoint: 0,
                    parentLineID: nil
                )
                let newService = CoachingService(
                    llmService: llmService,
                    curriculumService: CurriculumService(opening: openingRef, activeLine: line, phase: .learningMainLine),
                    featureAccess: UnlockedAccess()
                )
                await MainActor.run { state.coachingService = newService }
            }
            guard let coachingService = state.coachingService else {
                await MainActor.run {
                    state.appendMessage(role: "coach", text: "Coach is unavailable right now. Try again later.")
                    state.isLoading = false
                }
                return
            }
            let response = await coachingService.getChatResponse(question: question, context: context)
            await MainActor.run {
                state.appendMessage(role: "coach", text: response)
                state.isLoading = false
            }
        }
    }
}
