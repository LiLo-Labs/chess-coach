import Foundation
import llama

/// On-device LLM inference using llama.cpp with a bundled Qwen3-4B GGUF model.
/// Loads the model once and reuses it across the session. The actor's own
/// serial executor handles thread safety — no need for Task.detached.
actor OnDeviceLLMService {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var isLoaded = false

    static let modelFilename = "qwen3-4b-q4_k_m"

    /// Check whether the GGUF model file is bundled in the app.
    nonisolated static var isModelAvailable: Bool {
        Bundle.main.path(forResource: modelFilename, ofType: "gguf") != nil
    }

    /// Load the model from the app bundle. Call once at session start.
    func loadModel() throws {
        guard !isLoaded else { return }

        guard let path = Bundle.main.path(forResource: Self.modelFilename, ofType: "gguf") else {
            throw OnDeviceLLMError.modelNotFound
        }

        llama_backend_init()

        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #endif

        guard let m = llama_model_load_from_file(path, modelParams) else {
            throw OnDeviceLLMError.modelLoadFailed
        }

        let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 4096
        ctxParams.n_threads = Int32(nThreads)
        ctxParams.n_threads_batch = Int32(nThreads)

        guard let c = llama_init_from_model(m, ctxParams) else {
            llama_model_free(m)
            throw OnDeviceLLMError.contextInitFailed
        }

        self.model = m
        self.context = c
        self.vocab = llama_model_get_vocab(m)
        self.isLoaded = true
        print("[ChessCoach] On-device LLM loaded (\(nThreads) threads)")
    }

    /// Generate a completion for the given prompt. Supports Qwen3 thinking mode.
    func generate(prompt: String, maxTokens: Int = 200, useThinking: Bool = false) throws -> String {
        guard isLoaded, let model, let context, let vocab else {
            throw OnDeviceLLMError.modelNotLoaded
        }

        // Build ChatML prompt for Qwen3
        let thinkTag = useThinking ? "/think" : "/no_think"
        let chatMLPrompt = "<|im_start|>system\nYou are a helpful chess coaching assistant.\(thinkTag)<|im_end|>\n<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n"

        let result = try Self.runInference(
            model: model,
            context: context,
            vocab: vocab,
            prompt: chatMLPrompt,
            maxTokens: maxTokens
        )

        if useThinking {
            return Self.stripThinkingContent(result)
        }
        return result
    }

    func unloadModel() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        self.context = nil
        self.model = nil
        self.vocab = nil
        self.isLoaded = false
        llama_backend_free()
        print("[ChessCoach] On-device LLM unloaded")
    }

    // Cleanup is handled by unloadModel() — caller must call it before releasing.
    // deinit can't safely access actor-isolated state in Swift 6.

    // MARK: - Private

    private static func runInference(
        model: OpaquePointer,
        context: OpaquePointer,
        vocab: OpaquePointer,
        prompt: String,
        maxTokens: Int
    ) throws -> String {
        // Tokenize
        let utf8Count = prompt.utf8.count
        let maxTokenCount = utf8Count + 2
        var tokens = [llama_token](repeating: 0, count: maxTokenCount)
        let nTokens = Int(llama_tokenize(vocab, prompt, Int32(utf8Count), &tokens, Int32(maxTokenCount), true, true))

        guard nTokens > 0 else {
            throw OnDeviceLLMError.tokenizationFailed
        }

        // Clear KV cache
        llama_memory_clear(llama_get_memory(context), false)

        // Create batch and fill with prompt tokens
        var batch = llama_batch_init(Int32(nTokens + maxTokens), 0, 1)
        defer { llama_batch_free(batch) }

        for i in 0..<nTokens {
            batch.token[i] = tokens[i]
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 0
        }
        batch.n_tokens = Int32(nTokens)
        batch.logits[nTokens - 1] = 1  // Enable logits for last token

        // Process prompt
        guard llama_decode(context, batch) == 0 else {
            throw OnDeviceLLMError.decodeFailed
        }

        // Set up sampler
        let sparams = llama_sampler_chain_default_params()
        let sampler = llama_sampler_chain_init(sparams)!
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.6))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        defer { llama_sampler_free(sampler) }

        // Generate tokens
        var output = ""
        var nCur = Int32(nTokens)
        var tempInvalidCChars: [CChar] = []

        for _ in 0..<maxTokens {
            let newTokenId = llama_sampler_sample(sampler, context, batch.n_tokens - 1)

            if llama_vocab_is_eog(vocab, newTokenId) {
                if !tempInvalidCChars.isEmpty {
                    let bytes = tempInvalidCChars.map { UInt8(bitPattern: $0) }
                    output += String(decoding: bytes, as: UTF8.self)
                }
                break
            }

            // Convert token to text
            let piece = tokenToPiece(vocab: vocab, token: newTokenId)
            tempInvalidCChars.append(contentsOf: piece)

            // Try to decode accumulated bytes as valid UTF-8
            let bytes = tempInvalidCChars.map { UInt8(bitPattern: $0) }
            let decoded = String(decoding: bytes, as: UTF8.self)
            if !decoded.contains("\u{FFFD}") {
                tempInvalidCChars.removeAll()
                output += decoded
            }

            // Prepare next batch
            llama_batch_clear(&batch)
            batch.token[0] = newTokenId
            batch.pos[0] = nCur
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            batch.n_tokens = 1

            nCur += 1

            guard llama_decode(context, batch) == 0 else {
                break
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenToPiece(vocab: OpaquePointer, token: llama_token) -> [CChar] {
        var buf = [CChar](repeating: 0, count: 64)
        let nChars = llama_token_to_piece(vocab, token, &buf, 64, 0, false)
        if nChars < 0 {
            buf = [CChar](repeating: 0, count: Int(-nChars))
            _ = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
            return Array(buf.prefix(Int(-nChars)))
        }
        return Array(buf.prefix(Int(nChars)))
    }

    /// Strip `<think>...</think>` blocks from Qwen3 thinking mode output
    private static func stripThinkingContent(_ text: String) -> String {
        var result = text
        while let thinkStart = result.range(of: "<think>"),
              let thinkEnd = result.range(of: "</think>") {
            if thinkStart.lowerBound <= thinkEnd.upperBound {
                result.removeSubrange(thinkStart.lowerBound..<thinkEnd.upperBound)
            } else {
                break
            }
        }
        if let thinkStart = result.range(of: "<think>") {
            result = String(result[thinkStart.upperBound...])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

enum OnDeviceLLMError: Error, LocalizedError {
    case modelNotFound
    case modelLoadFailed
    case contextInitFailed
    case modelNotLoaded
    case tokenizationFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound: "GGUF model file not found in app bundle"
        case .modelLoadFailed: "Failed to load GGUF model"
        case .contextInitFailed: "Failed to initialize llama context"
        case .modelNotLoaded: "Model not loaded — call loadModel() first"
        case .tokenizationFailed: "Failed to tokenize prompt"
        case .decodeFailed: "llama_decode failed during inference"
        }
    }
}
