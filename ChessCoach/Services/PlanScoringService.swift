import Foundation

/// Orchestrates all scoring signals (Stockfish, LLM, Polyglot) to produce
/// a composite Plan Execution Score for each move.
actor PlanScoringService {
    private let llmService: any TextGenerating
    private let stockfish: any PositionEvaluating
    private let featureAccess: any FeatureAccessProviding

    init(llmService: any TextGenerating, stockfish: any PositionEvaluating, featureAccess: any FeatureAccessProviding) {
        self.llmService = llmService
        self.stockfish = stockfish
        self.featureAccess = featureAccess
    }

    /// Scale Stockfish depth by student ELO — beginners get a more forgiving
    /// evaluation while stronger players are held to a higher standard.
    private static func depthForELO(_ elo: Int) -> Int {
        AppConfig.engine.depthForELO(elo)
    }

    /// Compute the full Plan Execution Score for a move.
    ///
    /// For paid tier: calls LLM for plan alignment + reasoning.
    /// For free tier: returns soundness-only score with template reasoning.
    func scoreMoveForPlan(
        fen: String,
        fenBeforeMove: String,
        move: String,
        moveSAN: String,
        opening: Opening,
        plan: OpeningPlan?,
        ply: Int,
        playerIsWhite: Bool,
        userELO: Int,
        moveHistory: String,
        polyglotMoveWeight: UInt16,
        polyglotAllWeights: [UInt16],
        maiaTopMoves: [(move: String, probability: Double)],
        stockfishTopMoves: [(move: String, score: Int)],
        isBookMove: Bool = false
    ) async -> PlanExecutionScore {
        // 0. Book move fast path — the learner played exactly what the opening recommends.
        //    No need for expensive LLM/engine evaluation; reward them immediately.
        if isBookMove {
            let reasoning = "Great job! \(moveSAN) is the book move in the \(opening.name). You're building solid opening habits."
            return PlanExecutionScore(
                total: 95,
                soundness: 95,
                alignment: 95,
                popularity: 5,
                reasoning: reasoning,
                category: .masterful,
                rubric: AlignmentRubric(development: true, pawnStructure: true, strategicGoal: true, kingSafety: "positive")
            )
        }

        // 1. Stockfish soundness — depth scales with student ELO
        let depth = Self.depthForELO(userELO)
        let evalBefore = await stockfish.evaluate(fen: fenBeforeMove, depth: depth)
        let evalAfter = await stockfish.evaluate(fen: fen, depth: depth)

        // If Stockfish isn't running or eval failed, we can't trust soundness.
        // Default to a neutral score rather than assuming perfect (100).
        let soundness: Int
        let cpLoss: Int
        if let before = evalBefore, let after = evalAfter {
            cpLoss = SoundnessCalculator.centipawnLoss(
                scoreBefore: before.score,
                scoreAfter: after.score,
                playerIsWhite: playerIsWhite
            )
            soundness = SoundnessCalculator.ceiling(centipawnLoss: cpLoss, userELO: userELO)
        } else {
            // Stockfish unavailable — use neutral score, don't fake perfection
            cpLoss = -1
            soundness = 50
            #if DEBUG
            print("[ChessCoach] PES: Stockfish eval unavailable, using neutral soundness (50)")
            #endif
        }

        // 2. Popularity adjustment
        let popularity = PopularityService.adjustment(
            moveWeight: polyglotMoveWeight,
            allWeights: polyglotAllWeights
        )

        // 3. Plan alignment (LLM) — paid tier only
        let hasFullPES = await featureAccess.isUnlocked(.fullPES)
        if hasFullPES, let plan = plan {
            let alignmentResult = await getLLMAlignment(
                fen: fen,
                fenBeforeMove: fenBeforeMove,
                move: move,
                moveSAN: moveSAN,
                opening: opening,
                plan: plan,
                ply: ply,
                playerIsWhite: playerIsWhite,
                userELO: userELO,
                moveHistory: moveHistory,
                soundness: soundness,
                cpLoss: cpLoss,
                polyglotMoveWeight: polyglotMoveWeight,
                polyglotAllWeights: polyglotAllWeights,
                maiaTopMoves: maiaTopMoves,
                stockfishTopMoves: stockfishTopMoves
            )
            return PlanExecutionScore.compute(
                soundness: soundness,
                alignment: alignmentResult.alignment,
                popularity: popularity,
                reasoning: alignmentResult.reasoning,
                rubric: alignmentResult.rubric
            )
        }

        // Free tier: soundness-only score with template reasoning
        let reasoning = templateReasoning(
            soundness: soundness,
            moveSAN: moveSAN,
            openingName: opening.name
        )
        return PlanExecutionScore.compute(
            soundness: soundness,
            alignment: soundness, // Use soundness as alignment proxy for free tier
            popularity: popularity,
            reasoning: reasoning
        )
    }

    /// Compute a simplified soundness-only PES (no LLM call).
    func scoreSoundnessOnly(
        fen: String,
        fenBeforeMove: String,
        move: String,
        moveSAN: String,
        openingName: String,
        playerIsWhite: Bool,
        userELO: Int = 600,
        polyglotMoveWeight: UInt16,
        polyglotAllWeights: [UInt16]
    ) async -> PlanExecutionScore {
        let depth = Self.depthForELO(userELO)
        let evalBefore = await stockfish.evaluate(fen: fenBeforeMove, depth: depth)
        let evalAfter = await stockfish.evaluate(fen: fen, depth: depth)
        let soundness: Int
        let cpLoss: Int
        if let before = evalBefore, let after = evalAfter {
            cpLoss = SoundnessCalculator.centipawnLoss(
                scoreBefore: before.score,
                scoreAfter: after.score,
                playerIsWhite: playerIsWhite
            )
            soundness = SoundnessCalculator.ceiling(centipawnLoss: cpLoss, userELO: userELO)
        } else {
            cpLoss = -1
            soundness = 50
            #if DEBUG
            print("[ChessCoach] PES soundness-only: Stockfish eval unavailable")
            #endif
        }
        let popularity = PopularityService.adjustment(
            moveWeight: polyglotMoveWeight,
            allWeights: polyglotAllWeights
        )
        let reasoning = templateReasoning(
            soundness: soundness,
            moveSAN: moveSAN,
            openingName: openingName
        )
        return PlanExecutionScore.compute(
            soundness: soundness,
            alignment: soundness,
            popularity: popularity,
            reasoning: reasoning
        )
    }

    // MARK: - LLM Alignment

    private struct LLMAlignmentResult {
        let alignment: Int
        let reasoning: String
        let rubric: AlignmentRubric?
    }

    private func getLLMAlignment(
        fen: String,
        fenBeforeMove: String,
        move: String,
        moveSAN: String,
        opening: Opening,
        plan: OpeningPlan,
        ply: Int,
        playerIsWhite: Bool,
        userELO: Int,
        moveHistory: String,
        soundness: Int,
        cpLoss: Int,
        polyglotMoveWeight: UInt16,
        polyglotAllWeights: [UInt16],
        maiaTopMoves: [(move: String, probability: Double)],
        stockfishTopMoves: [(move: String, score: Int)]
    ) async -> LLMAlignmentResult {
        let prompt = buildAlignmentPrompt(
            fen: fen,
            fenBeforeMove: fenBeforeMove,
            move: move,
            moveSAN: moveSAN,
            opening: opening,
            plan: plan,
            ply: ply,
            playerIsWhite: playerIsWhite,
            userELO: userELO,
            moveHistory: moveHistory,
            soundness: soundness,
            cpLoss: cpLoss,
            polyglotMoveWeight: polyglotMoveWeight,
            polyglotAllWeights: polyglotAllWeights,
            maiaTopMoves: maiaTopMoves,
            stockfishTopMoves: stockfishTopMoves
        )

        do {
            let response = try await llmService.generate(prompt: prompt, maxTokens: AppConfig.tokens.explanation)
            return parseAlignmentResponse(response)
        } catch {
            #if DEBUG
            print("[ChessCoach] PES LLM alignment failed: \(error)")
            #endif
            return LLMAlignmentResult(
                alignment: min(soundness, 50),
                reasoning: "Could not evaluate plan alignment.",
                rubric: nil
            )
        }
    }

    private func buildAlignmentPrompt(
        fen: String,
        fenBeforeMove: String,
        move: String,
        moveSAN: String,
        opening: Opening,
        plan: OpeningPlan,
        ply: Int,
        playerIsWhite: Bool,
        userELO: Int,
        moveHistory: String,
        soundness: Int,
        cpLoss: Int,
        polyglotMoveWeight: UInt16,
        polyglotAllWeights: [UInt16],
        maiaTopMoves: [(move: String, probability: Double)],
        stockfishTopMoves: [(move: String, score: Int)]
    ) -> String {
        let boardState = LLMService.boardStateSummary(fen: fen)
        let boardStateBefore = LLMService.boardStateSummary(fen: fenBeforeMove)

        let goalsText = plan.strategicGoals.map { "  \($0.priority). \($0.description)" }.joined(separator: "\n")
        let pieceTargetsText = plan.pieceTargets.map { "  - \($0.piece): ideal squares \($0.idealSquares.joined(separator: ", ")) — \($0.reasoning)" }.joined(separator: "\n")

        // Format Maia probabilities
        let actualMoveMaiaProb = maiaTopMoves.first(where: { $0.move == move })?.probability
        let actualMoveProbStr: String
        if let prob = actualMoveMaiaProb {
            actualMoveProbStr = String(format: "%.1f%%", prob * 100)
        } else {
            actualMoveProbStr = "<1% (not in Maia top predictions)"
        }

        let maiaTopStr = maiaTopMoves.prefix(5).map { m in
            let marker = m.move == move ? " <-- PLAYED" : ""
            return "    \(m.move): \(String(format: "%.1f%%", m.probability * 100))\(marker)"
        }.joined(separator: "\n")

        let sfTopStr = stockfishTopMoves.prefix(3).map { m in
            let marker = m.move == move ? " <-- PLAYED" : ""
            let pawns = String(format: "%+.1f", Double(m.score) / 100.0)
            return "    \(m.move): \(pawns) pawns\(marker)"
        }.joined(separator: "\n")

        let totalWeight = polyglotAllWeights.reduce(0, { $0 + Int($1) })
        let moveFreq: String
        if totalWeight > 0 && polyglotMoveWeight > 0 {
            let pct = Double(polyglotMoveWeight) / Double(totalWeight) * 100
            moveFreq = String(format: "%.0f%% of games", pct)
        } else if polyglotMoveWeight == 0 {
            moveFreq = "Not found in opening book"
        } else {
            moveFreq = "No book data available"
        }

        return PromptCatalog.alignmentPrompt(params: .init(
            fen: fen,
            fenBeforeMove: fenBeforeMove,
            move: move,
            moveSAN: moveSAN,
            openingName: opening.name,
            openingDescription: opening.description,
            planSummary: plan.summary,
            strategicGoals: goalsText,
            pawnStructureTarget: plan.pawnStructureTarget,
            keySquares: plan.keySquares.joined(separator: ", "),
            pieceTargets: pieceTargetsText,
            ply: ply,
            playerIsWhite: playerIsWhite,
            userELO: userELO,
            moveHistory: moveHistory,
            soundness: soundness,
            cpLoss: cpLoss,
            boardSummary: boardState,
            boardSummaryBefore: boardStateBefore,
            stockfishTopStr: sfTopStr,
            maiaActualMoveProbStr: actualMoveProbStr,
            maiaTopStr: maiaTopStr,
            moveFreq: moveFreq
        ))
    }

    private func parseAlignmentResponse(_ response: String) -> LLMAlignmentResult {
        // Try to extract JSON from the response
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON object boundaries
        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let jsonEnd = trimmed.lastIndex(of: "}") else {
            return regexFallbackParse(response)
        }

        var jsonStr = String(trimmed[jsonStart...jsonEnd])

        // Fix extra trailing braces — Qwen3-4B often adds one extra `}` on nested objects
        while jsonStr.hasSuffix("}}}")  {
            jsonStr = String(jsonStr.dropLast())
        }

        // Fix common LLM issues: unquoted string values like kingSafety: neutral
        // Quote bare words that appear as values (after : and not already quoted/boolean/number)
        jsonStr = jsonStr.replacingOccurrences(
            of: #":\s*(positive|negative|neutral)\b"#,
            with: #": "$1""#,
            options: .regularExpression
        )
        // Fix unquoted true/false that might have trailing junk
        jsonStr = jsonStr.replacingOccurrences(
            of: #":\s*True\b"#,
            with: ": true",
            options: .regularExpression
        )
        jsonStr = jsonStr.replacingOccurrences(
            of: #":\s*False\b"#,
            with: ": false",
            options: .regularExpression
        )

        guard let data = jsonStr.data(using: .utf8) else {
            return regexFallbackParse(response)
        }

        do {
            let parsed = try JSONDecoder().decode(AlignmentLLMResponse.self, from: data)
            let rubric = AlignmentRubric(
                development: parsed.rubric?.development ?? parsed.development ?? false,
                pawnStructure: parsed.rubric?.pawnStructure ?? parsed.pawnStructure ?? false,
                strategicGoal: parsed.rubric?.strategicGoal ?? parsed.strategicGoal ?? false,
                kingSafety: parsed.rubric?.kingSafety ?? parsed.kingSafety ?? "neutral"
            )
            return LLMAlignmentResult(
                alignment: max(0, min(100, parsed.alignment)),
                reasoning: parsed.reasoning,
                rubric: rubric
            )
        } catch {
            #if DEBUG
            print("[ChessCoach] Failed to parse alignment JSON: \(error)")
            #endif
            // Fall back to regex extraction
            return regexFallbackParse(response)
        }
    }

    /// Extract alignment and reasoning using regex when JSON parsing fails.
    private func regexFallbackParse(_ response: String) -> LLMAlignmentResult {
        var alignment = 50
        var reasoning = response

        // Try to extract alignment number
        if let match = response.range(of: #""alignment"\s*:\s*(\d+)"#, options: .regularExpression) {
            let snippet = String(response[match])
            if let numMatch = snippet.range(of: #"\d+"#, options: .regularExpression) {
                alignment = max(0, min(100, Int(snippet[numMatch]) ?? 50))
            }
        }

        // Try to extract reasoning string
        if let match = response.range(of: #""reasoning"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let snippet = String(response[match])
            // Extract content between the quotes after "reasoning":
            if let quoteStart = snippet.range(of: #":\s*""#, options: .regularExpression) {
                let afterColon = snippet[quoteStart.upperBound...]
                if let endQuote = afterColon.dropFirst().firstIndex(of: "\"") {
                    reasoning = String(afterColon[afterColon.startIndex..<endQuote])
                    // Remove leading quote
                    if reasoning.hasPrefix("\"") { reasoning = String(reasoning.dropFirst()) }
                }
            }
        }

        #if DEBUG
        print("[ChessCoach] PES: Used regex fallback — alignment=\(alignment)")
        #endif
        return LLMAlignmentResult(alignment: alignment, reasoning: reasoning, rubric: nil)
    }

    // MARK: - Template Reasoning (Free Tier)

    private func templateReasoning(soundness: Int, moveSAN: String, openingName: String) -> String {
        switch soundness {
        case 90...100:
            return "Good move! \(moveSAN) is sound in the \(openingName)."
        case 75...89:
            return "\(moveSAN) is a reasonable choice."
        case 60...74:
            return "\(moveSAN) is playable but there may be stronger options."
        case 40...59:
            return "\(moveSAN) is a bit inaccurate. Consider the plan's main ideas."
        default:
            return "\(moveSAN) loses material or position. Look for safer alternatives."
        }
    }
}

// MARK: - LLM Response Parsing

private struct AlignmentLLMResponse: Codable {
    let alignment: Int
    let reasoning: String
    // Nested format (legacy)
    let rubric: AlignmentRubricResponse?
    // Flat format (preferred — avoids Qwen3 extra-brace bug)
    let development: Bool?
    let pawnStructure: Bool?
    let strategicGoal: Bool?
    let kingSafety: String?
}

private struct AlignmentRubricResponse: Codable {
    let development: Bool?
    let pawnStructure: Bool?
    let strategicGoal: Bool?
    let kingSafety: String?
}
