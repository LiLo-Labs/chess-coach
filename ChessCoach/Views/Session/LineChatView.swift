import SwiftUI

/// Pro AI chat panel presented over LineStudyView.
/// Allows users to ask questions about the current position.
struct LineChatView: View {
    let opening: Opening
    let line: OpeningLine
    let fen: String
    let currentPly: Int
    let moveHistory: [String]

    @State private var messages: [(role: String, text: String)] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var coachingService: CoachingService?
    @Environment(\.dismiss) private var dismiss

    private let suggestions = [
        "Why not Nf6?",
        "What's the idea here?",
        "What if opponent plays d4?",
        "What's the long-term plan?"
    ]

    private var showSuggestions: Bool {
        messages.isEmpty && inputText.isEmpty && !isLoading
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                            // Welcome message
                            chatBubble(
                                role: "coach",
                                text: "Ask me anything about this position in the \(opening.name). I'm here to help you understand why each move matters."
                            )

                            // Suggestion chips shown before the user has typed anything
                            if showSuggestions {
                                suggestionChips
                                    .padding(.horizontal, AppSpacing.screenPadding)
                            }

                            ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                                chatBubble(role: message.role, text: message.text)
                                    .id(index)
                            }

                            if isLoading {
                                HStack(spacing: AppSpacing.sm) {
                                    ProgressView().controlSize(.small).tint(AppColor.secondaryText)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(AppColor.secondaryText)
                                }
                                .padding(.horizontal, AppSpacing.screenPadding)
                                .id("loading")
                            }
                        }
                        .padding(.vertical, AppSpacing.md)
                    }
                    .onChange(of: messages.count) {
                        withAnimation {
                            proxy.scrollTo(messages.count - 1, anchor: .bottom)
                        }
                    }
                    .onChange(of: isLoading) {
                        if isLoading {
                            withAnimation {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Input bar
                HStack(spacing: AppSpacing.sm) {
                    TextField("Ask about this position...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, AppSpacing.sm + AppSpacing.xxs)
                        .background(AppColor.inputBackground, in: RoundedRectangle(cornerRadius: AppRadius.xl))

                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(
                                inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? AppColor.disabledText
                                    : AppColor.guided
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.vertical, AppSpacing.sm + AppSpacing.xxs)
            }
            .background(AppColor.background)
            .navigationTitle("Ask Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Suggestion Chips

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Try asking...")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColor.tertiaryText)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: AppSpacing.sm
            ) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        inputText = suggestion
                    } label: {
                        Text(suggestion)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColor.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.sm))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Chat Bubble

    private func chatBubble(role: String, text: String) -> some View {
        let isUser = role == "user"
        return HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: AppSpacing.xxs) {
                if !isUser {
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption2)
                            .foregroundStyle(AppColor.practice)
                        Text("Coach")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppColor.practice)
                    }
                }

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.primaryText.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.md)
            .background(
                isUser ? AppColor.guided.opacity(0.2) : AppColor.cardBackground,
                in: RoundedRectangle(cornerRadius: AppRadius.md)
            )

            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal, AppSpacing.screenPadding)
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
            lineName: line.name,
            moveHistory: moveHistory,
            currentPly: currentPly
        )

        Task {
            // Lazily create the coaching service once and reuse across messages
            if coachingService == nil {
                let llmService = LLMService()
                await llmService.detectProvider()
                coachingService = CoachingService(
                    llmService: llmService,
                    curriculumService: CurriculumService(opening: opening, activeLine: line, phase: .learningMainLine)
                )
            }
            guard let coachingService else { return }
            let response = await coachingService.getChatResponse(question: question, context: context)
            await MainActor.run {
                messages.append((role: "coach", text: response))
                isLoading = false
            }
        }
    }
}
