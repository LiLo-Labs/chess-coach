import Foundation

actor CoachingService {
    private let llmService: any TextGenerating
    private let curriculumService: CurriculumService
    private let featureAccess: any FeatureAccessProviding
    private let offBookService = OffBookCoachingService()

    init(llmService: any TextGenerating, curriculumService: CurriculumService, featureAccess: any FeatureAccessProviding) {
        self.llmService = llmService
        self.curriculumService = curriculumService
        self.featureAccess = featureAccess
    }

    /// Determine whether coaching should be shown for this move.
    func shouldCoach(moveCategory: MoveCategory) -> Bool {
        curriculumService.shouldCoach(moveCategory: moveCategory)
    }

    /// Get coaching text for a move.
    /// When LLM coaching is not unlocked, returns template coaching only (no LLM call).
    func getCoaching(
        fen: String,
        lastMove: String,
        scoreBefore: Int,
        scoreAfter: Int,
        ply: Int,
        userELO: Int,
        moveHistory: String = "",
        isUserMove: Bool = true,
        studentColor: String? = nil,
        matchedResponseName: String? = nil,
        matchedResponseAdjustment: String? = nil,
        bookStatus: BookStatus? = nil
    ) async -> String? {
        let moveCategory = curriculumService.categorizeUserMove(
            atPly: ply,
            move: lastMove,
            stockfishScore: scoreAfter - scoreBefore
        )



        guard shouldCoach(moveCategory: moveCategory) else {
            return nil
        }

        // Free tier: return hardcoded coaching only
        let hasLLM = await featureAccess.isUnlocked(.llmCoaching)
        if !hasLLM {
            let context = buildContext(
                fen: fen, lastMove: lastMove, scoreBefore: scoreBefore, scoreAfter: scoreAfter,
                ply: ply, userELO: userELO, moveHistory: moveHistory,
                isUserMove: isUserMove, studentColor: studentColor,
                category: isUserMove ? moveCategory : (curriculumService.isDeviation(atPly: ply, move: lastMove) ? .deviation : .opponentMove),
                matchedResponseName: matchedResponseName,
                matchedResponseAdjustment: matchedResponseAdjustment,
                bookStatus: bookStatus
            )
            return freeCoaching(for: context)
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
            isUserMove: isUserMove, studentColor: studentColor, category: category,
            matchedResponseName: matchedResponseName,
            matchedResponseAdjustment: matchedResponseAdjustment,
            bookStatus: bookStatus
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
                return freeCoaching(for: context)
            }
        } catch {
            #if DEBUG
            print("[ChessCoach] LLM coaching failed: \(error)")
            #endif
            return nil
        }
    }

    /// Get batched coaching for both user and opponent moves in a single LLM call.
    /// When LLM coaching is not unlocked, returns template coaching only.
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
        studentColor: String?,
        bookStatus: BookStatus? = nil
    ) async -> (userCoaching: String?, opponentCoaching: String?) {
        let userMoveCategory = curriculumService.categorizeUserMove(
            atPly: userPly, move: userMove, stockfishScore: scoreAfter - scoreBefore
        )


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
                isUserMove: true, studentColor: studentColor, category: userCategory,
                bookStatus: bookStatus
            )
            let oc = buildContext(
                fen: opponentFen, lastMove: opponentMove, scoreBefore: 0, scoreAfter: 0,
                ply: opponentPly, userELO: userELO, moveHistory: moveHistory,
                isUserMove: false, studentColor: studentColor, category: opponentCategory,
                bookStatus: bookStatus
            )
            let shouldCoachUser = shouldCoach(moveCategory: userCategory)
            let shouldCoachOpponent = shouldCoach(moveCategory: opponentCategory)
            return (
                shouldCoachUser ? freeCoaching(for: uc) : nil,
                shouldCoachOpponent ? freeCoaching(for: oc) : nil
            )
        }

        let userContext = buildContext(
            fen: userFen, lastMove: userMove, scoreBefore: scoreBefore, scoreAfter: scoreAfter,
            ply: userPly, userELO: userELO, moveHistory: moveHistory,
            isUserMove: true, studentColor: studentColor, category: userCategory,
            bookStatus: bookStatus
        )

        let opponentContext = buildContext(
            fen: opponentFen, lastMove: opponentMove, scoreBefore: 0, scoreAfter: 0,
            ply: opponentPly, userELO: userELO, moveHistory: moveHistory,
            isUserMove: false, studentColor: studentColor, category: opponentCategory,
            bookStatus: bookStatus
        )

        let shouldCoachUser = shouldCoach(moveCategory: userCategory)
        let shouldCoachOpponent = shouldCoach(moveCategory: opponentCategory)

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
                validatedUser = shouldCoachUser ? freeCoaching(for: userContext) : nil
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
                validatedOpponent = shouldCoachOpponent ? freeCoaching(for: opponentContext) : nil
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
                    userResult = CoachingValidator.validate(parsed: parsed, fen: userFen) ?? freeCoaching(for: userContext)
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
                    opponentResult = CoachingValidator.validate(parsed: parsed, fen: opponentFen) ?? freeCoaching(for: opponentContext)
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
            userELO: userELO,
            conversationHistory: context.conversationHistory
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
        isUserMove: Bool, studentColor: String?, category: MoveCategory,
        matchedResponseName: String? = nil, matchedResponseAdjustment: String? = nil,
        bookStatus: BookStatus? = nil
    ) -> CoachingContext {
        let opening = curriculumService.opening
        let expectedMove = opening.expectedMove(atPly: ply)
        let personality = CoachPersonality.forOpening(opening)

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
            familiarityPercent: Int(curriculumService.familiarity * 100),
            moveCategory: category,
            moveHistory: moveHistory,
            isUserMove: isUserMove,
            studentColor: studentColor,
            plyNumber: ply,
            mainLineSoFar: mainLineSoFar,
            matchedResponseName: matchedResponseName,
            matchedResponseAdjustment: matchedResponseAdjustment,
            coachPersonalityPrompt: personality.personalityPrompt,
            opening: opening,
            bookStatus: bookStatus
        )
    }

    private func freeCoaching(for context: CoachingContext) -> String? {
        // Off-book: delegate to plan-based guidance
        if let bookStatus = context.bookStatus, let opening = context.opening {
            switch bookStatus {
            case .offBook(let p), .userDeviated(_, let p), .opponentDeviated(_, _, let p):
                let guidance = offBookService.generateGuidance(
                    fen: context.fen,
                    opening: opening,
                    deviationPly: p,
                    moveHistory: []
                )
                return guidance.templateCoaching
            case .onBook:
                break
            }
        }

        // On-book: use opening move explanations
        if context.isUserMove {
            if let explanation = context.expectedMoveExplanation, !explanation.isEmpty {
                switch context.moveCategory {
                case .goodMove:
                    return explanation
                case .okayMove:
                    let expected = context.expectedMoveSAN ?? "the book move"
                    return "The book move is \(expected). \(explanation)"
                case .mistake:
                    let expected = context.expectedMoveSAN ?? "the book move"
                    return "The recommended move is \(expected). \(explanation)"
                default:
                    return nil
                }
            }
            switch context.moveCategory {
            case .goodMove: return "Good — that's the book move."
            case .okayMove:
                let expected = context.expectedMoveSAN ?? "the book move"
                return "The book move is \(expected)."
            case .mistake:
                let expected = context.expectedMoveSAN ?? "the book move"
                return "The recommended move is \(expected)."
            default: return nil
            }
        } else {
            if context.moveCategory == .deviation {
                if let name = context.matchedResponseName, let adj = context.matchedResponseAdjustment {
                    return "Your opponent played the \(name). \(adj)"
                }
                return "Your opponent deviated from the main line."
            }
            return nil
        }
    }
}
