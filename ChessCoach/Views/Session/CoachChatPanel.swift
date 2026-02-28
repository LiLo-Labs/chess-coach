import SwiftUI

/// Sliding side panel for AI coach chat during a session.
/// Has full board context, move history, and opening info pre-loaded.
struct CoachChatPanel: View {
    let opening: Opening
    let fen: String
    let moveHistory: [String]
    let currentPly: Int
    @Binding var isPresented: Bool

    @Environment(AppServices.self) private var appServices

    @State private var messages: [(role: String, text: String)] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var coachingService: CoachingService?

    private let suggestions = [
        "Why this move?",
        "What's the plan here?",
        "What should I watch for?",
        "How am I doing?"
    ]

    private var showSuggestions: Bool {
        messages.isEmpty && inputText.isEmpty && !isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.practice)
                Text("Ask Coach")
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
                            text: "Ask me anything about the \(opening.name). I can see the board and your moves."
                        )

                        if showSuggestions {
                            suggestionChips
                                .padding(.horizontal, 12)
                        }

                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            chatBubble(role: message.role, text: message.text)
                                .id(index)
                        }

                        if isLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small).tint(AppColor.secondaryText)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(AppColor.secondaryText)
                            }
                            .padding(.horizontal, 12)
                            .id("loading")
                        }
                    }
                    .padding(.vertical, 10)
                }
                .onChange(of: messages.count) {
                    withAnimation { proxy.scrollTo(messages.count - 1, anchor: .bottom) }
                }
                .onChange(of: isLoading) {
                    if isLoading { withAnimation { proxy.scrollTo("loading", anchor: .bottom) } }
                }
            }

            Divider().opacity(0.3)

            // Input
            HStack(spacing: 8) {
                TextField("Ask about this position...", text: $inputText)
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
                            inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? AppColor.disabledText
                                : AppColor.guided
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
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
                    inputText = suggestion
                } label: {
                    Text(suggestion)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Chat Bubble

    private func chatBubble(role: String, text: String) -> some View {
        let isUser = role == "user"
        return HStack {
            if isUser { Spacer(minLength: 20) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                if !isUser {
                    HStack(spacing: 3) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 8))
                            .foregroundStyle(AppColor.practice)
                        Text("Coach")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppColor.practice)
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

            if !isUser { Spacer(minLength: 20) }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let question = inputText.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty else { return }

        messages.append((role: "user", text: question))
        inputText = ""
        isLoading = true

        let context = ChatContext(
            fen: fen,
            openingName: opening.name,
            lineName: opening.name,
            moveHistory: moveHistory,
            currentPly: currentPly
        )

        Task {
            do {
                if coachingService == nil {
                    // Reuse the shared LLM service (already warmed up at app start)
                    let llmService = appServices.llmService
                    let line = opening.lines?.first ?? OpeningLine(
                        id: "\(opening.id)/main",
                        name: opening.name,
                        moves: opening.mainLine,
                        branchPoint: 0,
                        parentLineID: nil
                    )
                    let newService = CoachingService(
                        llmService: llmService,
                        curriculumService: CurriculumService(opening: opening, activeLine: line, phase: .learningMainLine),
                        featureAccess: UnlockedAccess()
                    )
                    await MainActor.run { coachingService = newService }
                }
                guard let coachingService else {
                    await MainActor.run {
                        messages.append((role: "coach", text: "Coach is unavailable right now. Try again later."))
                        isLoading = false
                    }
                    return
                }
                let response = await coachingService.getChatResponse(question: question, context: context)
                await MainActor.run {
                    messages.append((role: "coach", text: response))
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    messages.append((role: "coach", text: "Sorry, I couldn't reach the coach right now. Please try again."))
                    isLoading = false
                }
            }
        }
    }
}
