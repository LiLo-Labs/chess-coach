import SwiftUI
import ChessKit

struct SessionView: View {
    @State private var viewModel: SessionViewModel
    @State private var userCoachingExpanded = true
    @State private var opponentCoachingExpanded = true
    @Environment(\.dismiss) private var dismiss

    init(opening: Opening) {
        self._viewModel = State(initialValue: SessionViewModel(opening: opening))
    }

    var body: some View {
        GeometryReader { geo in
            let evalWidth: CGFloat = 12
            let evalGap: CGFloat = 4
            let boardSize = geo.size.width - evalWidth - evalGap

            VStack(spacing: 0) {
                topBar
                opponentBar

                // ── Eval bar + Board ──
                HStack(spacing: 4) {
                    evalBar(height: boardSize)
                        .frame(width: evalWidth)

                    GameBoardView(
                        gameState: viewModel.gameState,
                        perspective: viewModel.opening.color == .white ? PieceColor.white : PieceColor.black,
                        allowInteraction: viewModel.isUserTurn && !viewModel.isThinking && !viewModel.sessionComplete
                    ) { from, to in
                        Task { await viewModel.userMoved(from: from, to: to) }
                    }
                    .frame(width: boardSize, height: boardSize)
                }
                .frame(height: boardSize)

                userBar

                // ── Info area ──
                ScrollView {
                    VStack(spacing: 8) {
                        if !viewModel.sessionComplete {
                            guideCard
                        }

                        if let text = viewModel.opponentCoachingText {
                            coachingCard(
                                label: "Opponent",
                                text: text,
                                tint: Color(red: 0.55, green: 0.65, blue: 0.8),
                                isExpanded: $opponentCoachingExpanded,
                                showExplain: viewModel.opponentExplainContext != nil,
                                explanation: viewModel.opponentExplanation,
                                isExplaining: viewModel.isExplainingOpponent
                            ) {
                                Task { await viewModel.requestExplanation(forUserMove: false) }
                            }
                        }

                        if let text = viewModel.userCoachingText {
                            coachingCard(
                                label: "Your move",
                                text: text,
                                tint: Color(red: 1.0, green: 0.84, blue: 0.35),
                                isExpanded: $userCoachingExpanded,
                                showExplain: viewModel.userExplainContext != nil,
                                explanation: viewModel.userExplanation,
                                isExplaining: viewModel.isExplainingUser
                            ) {
                                Task { await viewModel.requestExplanation(forUserMove: true) }
                            }
                        }

                        if viewModel.isCoachingLoading && viewModel.userCoachingText == nil && viewModel.opponentCoachingText == nil {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small).tint(.secondary)
                                Text("Coach is thinking...")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .preferredColorScheme(.dark)
        .overlay {
            if viewModel.sessionComplete {
                sessionCompleteOverlay
            }
        }
        .task {
            await viewModel.startSession()
        }
    }

    // MARK: - Eval Bar (slim, rounded)

    private func evalBar(height: CGFloat) -> some View {
        let fraction = viewModel.evalFraction
        let whiteRatio = CGFloat((1.0 + fraction) / 2.0)

        return GeometryReader { _ in
            VStack(spacing: 0) {
                Color(white: 0.2)
                    .frame(height: height * (1 - whiteRatio))
                Color(white: 0.82)
                    .frame(height: height * whiteRatio)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .center) {
                Text(viewModel.evalText)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(whiteRatio > 0.5 ? Color(white: 0.2) : Color(white: 0.8))
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.5), value: viewModel.evalScore)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text(viewModel.opening.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            if viewModel.stats.totalUserMoves > 0 {
                Text("\(Int(viewModel.stats.accuracy * 100))%")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.endSession()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 54)
        .padding(.bottom, 8)
    }

    // MARK: - Player Bars

    private var opponentBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.opening.color == .white ? Color(white: 0.3) : .white)
                .frame(width: 10, height: 10)
            Text("Opponent")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
            Text("\(viewModel.opponentELO)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if viewModel.isThinking {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini).tint(.secondary)
                    Text("thinking")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color(white: 0.14))
    }

    private var userBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.opening.color == .white ? .white : Color(white: 0.3))
                .frame(width: 10, height: 10)
            Text("You")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
            Text("\(viewModel.userELO)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if viewModel.isUserTurn && !viewModel.isThinking && !viewModel.sessionComplete {
                Text("YOUR MOVE")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.5)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.15), in: Capsule())
            }
            Text("Move \(viewModel.moveCount / 2 + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color(white: 0.14))
    }

    // MARK: - Guide Card

    private var guideCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                switch viewModel.bookStatus {
                case .onBook:
                    if let move = viewModel.expectedNextMove {
                        Image(systemName: "book.fill")
                            .font(.footnote)
                            .foregroundStyle(.cyan)
                        Text("Play")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(move.san)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.cyan)
                        Text(move.explanation)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                        Text("End of opening line")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                case let .userDeviated(expected, _):
                    Image(systemName: "arrow.uturn.backward")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Text("Off book — expected \(expected.san)")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(action: { Task { await viewModel.restartSession() } }) {
                        Text("Retry")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)

                case .opponentDeviated:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Opponent went off book")
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                        if let hint = viewModel.bestResponseHint {
                            Text("Best response: \(hint)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: { Task { await viewModel.restartSession() } }) {
                        Text("Retry")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.yellow.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }

            // Off-book explanation
            if viewModel.bookStatus != .onBook {
                if viewModel.offBookExplanation == nil && !viewModel.isExplainingOffBook {
                    let tint: Color = {
                        if case .userDeviated = viewModel.bookStatus { return .orange }
                        return .yellow
                    }()
                    Button(action: { Task { await viewModel.requestOffBookExplanation() } }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                            Text("Why is this off book?")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(tint.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }

                if viewModel.isExplainingOffBook {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).tint(.purple)
                        Text("Analyzing deviation...")
                            .font(.caption)
                            .foregroundStyle(.purple)
                        Spacer()
                    }
                    .padding(.top, 8)
                }

                if let explanation = viewModel.offBookExplanation {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "brain.head.profile")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                            Text("Move analysis")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.purple)
                        }
                        Text(explanation)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 8)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
    }

    // MARK: - Coaching Card (collapsible, rounded)

    private func coachingCard(
        label: String,
        text: String,
        tint: Color,
        isExpanded: Binding<Bool>,
        showExplain: Bool,
        explanation: String?,
        isExplaining: Bool,
        onExplain: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 6, height: 6)
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)

                    if !isExpanded.wrappedValue {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? -180 : 0))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Body
            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    if showExplain && explanation == nil && !isExplaining {
                        Button(action: onExplain) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                Text("Explain why")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(tint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if isExplaining {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini).tint(.purple)
                            Text("Thinking deeper...")
                                .font(.caption)
                                .foregroundStyle(.purple)
                        }
                    }

                    if let explanation {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 5) {
                                Image(systemName: "brain.head.profile")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                                Text("Deep explanation")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.purple)
                            }
                            Text(explanation)
                                .font(.subheadline)
                                .foregroundStyle(.primary.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
    }

    // MARK: - Complete Overlay

    private var sessionCompleteOverlay: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("Session Complete")
                    .font(.title2.weight(.bold))

                Text("\(viewModel.moveCount / 2) moves · \(viewModel.opening.name)")
                    .font(.body)
                    .foregroundStyle(.secondary)

                if viewModel.stats.totalUserMoves > 0 {
                    VStack(spacing: 4) {
                        Text("\(Int(viewModel.stats.accuracy * 100))%")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text("accuracy")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.restartSession() }
                    } label: {
                        Text("Try Again")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(.green, in: Capsule())
                }
            }
            .padding(32)
        }
    }
}
