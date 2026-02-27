import Foundation

actor CoachingService {
    private let llmService: any TextGenerating
    private let curriculumService: CurriculumService
    private let featureAccess: any FeatureAccessProviding

    init(llmService: any TextGenerating, curriculumService: CurriculumService, featureAccess: any FeatureAccessProviding) {
        self.llmService = llmService
        self.curriculumService = curriculumService
        self.featureAccess = featureAccess
    }

    /// Determine whether coaching should be shown for this move.
    func shouldCoach(moveCategory: MoveCategory, phase: LearningPhase) -> Bool {
        switch phase {
        case .learningMainLine:
            // Always coach during learning phase
            return true
        case .naturalDeviations:
            // Coach on all non-trivial moments
            return true
        case .widerVariations:
            // Coach on mistakes and deviations
            return moveCategory != .goodMove
        case .freePlay:
            // Only coach on mistakes
            return moveCategory == .mistake
        }
    }

    /// Get coaching text for a move.
    /// When LLM coaching is not unlocked, returns hardcoded fallback coaching only (no LLM call).
    func getCoaching(
        fen: String,
        lastMove: String,
        scoreBefore: Int,
        scoreAfter: Int,
        ply: Int,
        userELO: Int,
        moveHistory: String = "",
        isUserMove: Bool = true,
        studentColor: String? = nil
    ) async -> String? {
        let moveCategory = curriculumService.categorizeUserMove(
            atPly: ply,
            move: lastMove,
            stockfishScore: scoreAfter - scoreBefore
        )

        let phase = curriculumService.phase

        guard shouldCoach(moveCategory: moveCategory, phase: phase) else {
            return nil
        }

        // Free tier: return hardcoded coaching only
        let hasLLM = await featureAccess.isUnlocked(.llmCoaching)
        if !hasLLM {
            let context = buildContext(
                fen: fen, lastMove: lastMove, scoreBefore: scoreBefore, scoreAfter: scoreAfter,
                ply: ply, userELO: userELO, moveHistory: moveHistory,
                isUserMove: isUserMove, studentColor: studentColor,
                category: isUserMove ? moveCategory : (curriculumService.isDeviation(atPly: ply, move: lastMove) ? .deviation : .opponentMove)
            )
            return fallbackCoaching(for: context)
        }

        // Use the isUserMove flag passed from SessionViewModel
        let isOpponentMove = !isUserMove

        let category: MoveCategory
        if isOpponentMove && curriculumService.isDeviation(atPly: ply, move: lastMove) {
            category = .deviation
        } else if isOpponentMove {
            category = .opponentMove
        } else {
            category = moveCategory
        }

        let context = buildContext(
            fen: fen, lastMove: lastMove, scoreBefore: scoreBefore, scoreAfter: scoreAfter,
            ply: ply, userELO: userELO, moveHistory: moveHistory,
            isUserMove: isUserMove, studentColor: studentColor, category: category
        )

        do {
            let prompt = LLMService.buildPrompt(for: context)
            let raw = try await llmService.generate(prompt: prompt, maxTokens: AppConfig.tokens.coaching)
            let parsed = CoachingValidator.parse(response: raw)
            if let validated = CoachingValidator.validate(parsed: parsed, fen: fen) {
                return validated
            } else {
                #if DEBUG
                print("[ChessCoach] Hallucination detected in coaching, using fallback")
                #endif
                return fallbackCoaching(for: context)
            }
        } catch {
            #if DEBUG
            print("[ChessCoach] LLM coaching failed: \(error)")
            #endif
            return nil
        }
    }

    /// Get batched coaching for both user and opponent moves in a single LLM call.
    /// When LLM coaching is not unlocked, returns hardcoded fallback coaching only.
    func getBatchedCoaching(
        userFen: String,
        userMove: String,
        userPly: Int,
        opponentFen: String,
        opponentMove: String,
        opponentPly: Int,
        scoreBefore: Int,
        scoreAfter: Int,
        userELO: Int,
        moveHistory: String,
        studentColor: String?
    ) async -> (userCoaching: String?, opponentCoaching: String?) {
        let userMoveCategory = curriculumService.categorizeUserMove(
            atPly: userPly, move: userMove, stockfishScore: scoreAfter - scoreBefore
        )
        let phase = curriculumService.phase

        let userCategory: MoveCategory = userMoveCategory

        let opponentCategory: MoveCategory
        if curriculumService.isDeviation(atPly: opponentPly, move: opponentMove) {
            opponentCategory = .deviation
        } else {
            opponentCategory = .opponentMove
        }

        // Free tier: return hardcoded coaching only
        let hasLLM = await featureAccess.isUnlocked(.llmCoaching)
        if !hasLLM {
            let uc = buildContext(
                fen: userFen, lastMove: userMove, scoreBefore: scoreBefore, scoreAfter: scoreAfter,
                ply: userPly, userELO: userELO, moveHistory: moveHistory,
                isUserMove: true, studentColor: studentColor, category: userCategory
            )
            let oc = buildContext(
                fen: opponentFen, lastMove: opponentMove, scoreBefore: 0, scoreAfter: 0,
                ply: opponentPly, userELO: userELO, moveHistory: moveHistory,
                isUserMove: false, studentColor: studentColor, category: opponentCategory
            )
            let shouldCoachUser = shouldCoach(moveCategory: userCategory, phase: phase)
            let shouldCoachOpponent = shouldCoach(moveCategory: opponentCategory, phase: phase)
            return (
                shouldCoachUser ? fallbackCoaching(for: uc) : nil,
                shouldCoachOpponent ? fallbackCoaching(for: oc) : nil
            )
        }

        let userContext = buildContext(
            fen: userFen, lastMove: userMove, scoreBefore: scoreBefore, scoreAfter: scoreAfter,
            ply: userPly, userELO: userELO, moveHistory: moveHistory,
            isUserMove: true, studentColor: studentColor, category: userCategory
        )

        let opponentContext = buildContext(
            fen: opponentFen, lastMove: opponentMove, scoreBefore: 0, scoreAfter: 0,
            ply: opponentPly, userELO: userELO, moveHistory: moveHistory,
            isUserMove: false, studentColor: studentColor, category: opponentCategory
        )

        let shouldCoachUser = shouldCoach(moveCategory: userCategory, phase: phase)
        let shouldCoachOpponent = shouldCoach(moveCategory: opponentCategory, phase: phase)

        guard shouldCoachUser || shouldCoachOpponent else {
            return (nil, nil)
        }

        let batched = BatchedCoachingContext(
            userContext: userContext,
            opponentContext: opponentContext
        )

        do {
            let batchedPrompt = LLMService.buildBatchedPrompt(for: batched)
            let rawResult = try await llmService.generate(prompt: batchedPrompt, maxTokens: AppConfig.tokens.batchedCoaching)
            let result = LLMService.parseBatchedResponse(rawResult)

            // Validate user coaching
            let userParsed = CoachingValidator.parse(response: result.userCoaching)
            let validatedUser: String?
            if let v = CoachingValidator.validate(parsed: userParsed, fen: userFen) {
                validatedUser = shouldCoachUser ? v : nil
            } else {
                #if DEBUG
                print("[ChessCoach] Hallucination detected in user coaching, using fallback")
                #endif
                validatedUser = shouldCoachUser ? fallbackCoaching(for: userContext) : nil
            }

            // Validate opponent coaching
            let opponentParsed = CoachingValidator.parse(response: result.opponentCoaching)
            let validatedOpponent: String?
            if let v = CoachingValidator.validate(parsed: opponentParsed, fen: opponentFen) {
                validatedOpponent = shouldCoachOpponent ? v : nil
            } else {
                #if DEBUG
                print("[ChessCoach] Hallucination detected in opponent coaching, using fallback")
                #endif
                validatedOpponent = shouldCoachOpponent ? fallbackCoaching(for: opponentContext) : nil
            }

            return (validatedUser, validatedOpponent)
        } catch {
            #if DEBUG
            print("[ChessCoach] Batched LLM coaching failed: \(error)")
            #endif
            // Fall back to single coaching calls
            var userResult: String?
            var opponentResult: String?
            if shouldCoachUser {
                do {
                    let prompt = LLMService.buildPrompt(for: userContext)
                    let raw = try await llmService.generate(prompt: prompt, maxTokens: AppConfig.tokens.coaching)
                    let parsed = CoachingValidator.parse(response: raw)
                    userResult = CoachingValidator.validate(parsed: parsed, fen: userFen) ?? fallbackCoaching(for: userContext)
                } catch {
                    #if DEBUG
                    print("[ChessCoach] Single user coaching also failed: \(error)")
                    #endif
                }
            }
            if shouldCoachOpponent {
                do {
                    let prompt = LLMService.buildPrompt(for: opponentContext)
                    let raw = try await llmService.generate(prompt: prompt, maxTokens: AppConfig.tokens.coaching)
                    let parsed = CoachingValidator.parse(response: raw)
                    opponentResult = CoachingValidator.validate(parsed: parsed, fen: opponentFen) ?? fallbackCoaching(for: opponentContext)
                } catch {
                    #if DEBUG
                    print("[ChessCoach] Single opponent coaching also failed: \(error)")
                    #endif
                }
            }
            return (userResult, opponentResult)
        }
    }

    // MARK: - Chat

    /// Get a chat response for a user's question about the current position (Pro feature).
    func getChatResponse(question: String, context: ChatContext) async -> String {
        let opening = curriculumService.opening
        let userELO = UserDefaults.standard.object(forKey: AppSettings.Key.userELO) as? Int ?? 600
        let boardState = LLMService.boardStateSummary(fen: context.fen)
        let occupied = LLMService.occupiedSquares(fen: context.fen)

        let moveHistoryStr = context.moveHistory.enumerated().map { i, m in
            i % 2 == 0 ? "\(i / 2 + 1). \(m)" : m
        }.joined(separator: " ")

        let prompt = PromptCatalog.chatPrompt(
            question: question,
            openingName: context.openingName,
            lineName: context.lineName,
            fen: context.fen,
            boardSummary: boardState,
            occupiedSquares: occupied,
            moveHistory: moveHistoryStr,
            currentPly: context.currentPly,
            userELO: userELO
        )

        do {
            let response = try await llmService.generate(prompt: prompt, maxTokens: AppConfig.tokens.explanation)
            let parsed = CoachingValidator.parse(response: response)
            if let validated = CoachingValidator.validate(parsed: parsed, fen: context.fen) {
                return validated
            }
            return parsed.text
        } catch {
            return "Sorry, I couldn't process that question right now. Try asking again."
        }
    }

    // MARK: - Private

    private func buildContext(
        fen: String, lastMove: String, scoreBefore: Int, scoreAfter: Int,
        ply: Int, userELO: Int, moveHistory: String,
        isUserMove: Bool, studentColor: String?, category: MoveCategory
    ) -> CoachingContext {
        let opening = curriculumService.opening
        let expectedMove = opening.expectedMove(atPly: ply)

        let mainLineSoFar = opening.mainLine.prefix(ply + 1)
            .map(\.san)
            .enumerated()
            .map { i, san in i % 2 == 0 ? "\(i/2 + 1). \(san)" : san }
            .joined(separator: " ")

        return CoachingContext(
            fen: fen,
            lastMove: lastMove,
            scoreBefore: scoreBefore,
            scoreAfter: scoreAfter,
            openingName: opening.name,
            openingDescription: opening.description,
            expectedMoveExplanation: expectedMove?.explanation,
            expectedMoveSAN: expectedMove?.san,
            userELO: userELO,
            phase: curriculumService.phase,
            moveCategory: category,
            moveHistory: moveHistory,
            isUserMove: isUserMove,
            studentColor: studentColor,
            plyNumber: ply,
            mainLineSoFar: mainLineSoFar
        )
    }

    private func fallbackCoaching(for context: CoachingContext) -> String? {
        let cfg = AppConfig.coaching
        if context.isUserMove {
            switch context.moveCategory {
            case .goodMove:
                return String(format: cfg.goodMoveTemplate, context.openingName)
            case .okayMove:
                let expected = context.expectedMoveSAN ?? "the book move"
                return String(format: cfg.okayMoveTemplate, expected)
            case .mistake:
                let expected = context.expectedMoveSAN ?? "the book move"
                return String(format: cfg.mistakeMoveTemplate, expected)
            default:
                return nil
            }
        } else {
            if context.moveCategory == .deviation {
                return String(format: cfg.deviationTemplate, context.openingName)
            } else {
                return cfg.standardOpponentTemplate
            }
        }
    }
}
