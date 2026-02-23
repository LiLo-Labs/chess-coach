import SwiftUI

struct SettingsView: View {
    @AppStorage("claude_api_key") private var claudeAPIKey = ""
    @AppStorage("user_elo") private var userELO = 600
    @AppStorage("opponent_elo") private var opponentELO = 1200
    @AppStorage("llm_provider_preference") private var providerPreference = "auto"

    @State private var showingAPIKey = false
    @State private var detectedProvider: String?

    var body: some View {
        Form {
            Section("LLM Provider") {
                Picker("Provider", selection: $providerPreference) {
                    Text("Auto-detect").tag("auto")
                    Text("On-Device (Qwen3-4B)").tag("onDevice")
                    Text("Ollama (Local/DGX)").tag("ollama")
                    Text("Claude API").tag("claude")
                }

                if let detected = detectedProvider {
                    HStack {
                        Text("Active")
                        Spacer()
                        Text(detected)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Claude API Key") {
                HStack {
                    if showingAPIKey {
                        TextField("sk-ant-...", text: $claudeAPIKey)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("sk-ant-...", text: $claudeAPIKey)
                    }
                    Button {
                        showingAPIKey.toggle()
                    } label: {
                        Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }

                if claudeAPIKey.isEmpty {
                    Text("Required when Ollama is unavailable. Get a key at console.anthropic.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Key saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section("Player Settings") {
                Stepper("Your ELO: \(userELO)", value: $userELO, in: 400...2000, step: 100)
                Stepper("Opponent ELO: \(opponentELO)", value: $opponentELO, in: 800...2000, step: 100)
                Text("Maia 2 adjusts play style to match the opponent ELO")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ollama Settings") {
                HStack {
                    Text("Server")
                    Spacer()
                    Text("192.168.4.62:11434")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Model")
                    Spacer()
                    Text("qwen2.5:7b")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            let config = LLMConfig()
            let provider = await config.detectProvider()
            switch provider {
            case .onDevice: detectedProvider = "On-Device (Qwen3-4B)"
            case .ollama: detectedProvider = "Ollama"
            case .claude: detectedProvider = "Claude"
            }
        }
    }
}
