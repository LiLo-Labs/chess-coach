import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SubscriptionService.self) private var subscriptionService

    @State private var showingAPIKey = false
    @State private var showOnboarding = false
    @State private var showProUpgrade = false

    var body: some View {
        @Bindable var s = settings

        Form {
            Section("Player Settings") {
                Stepper("Your Skill Level: \(s.userELO)", value: $s.userELO, in: 400...2000, step: 100)
                Stepper("Opponent Level: \(s.opponentELO)", value: $s.opponentELO, in: 800...2000, step: 100)
                Text("The AI opponent adjusts to match the skill level")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sound & Haptics") {
                Toggle("Sound Effects", isOn: $s.soundEnabled)
                Toggle("Haptic Feedback", isOn: $s.hapticsEnabled)
            }

            Section("Daily Goal") {
                Stepper("Target: \(s.dailyGoalTarget) games/day", value: $s.dailyGoalTarget, in: 1...10)
            }

            Section("Display") {
                Picker("Move Notation", selection: $s.notationStyle) {
                    Text("Standard (Nf3)").tag("san")
                    Text("English (Knight f3)").tag("english")
                    Text("UCI (g1f3)").tag("uci")
                }
                Toggle("Color-Blind Friendly", isOn: $s.colorblindMode)
                if s.colorblindMode {
                    Text("Stage indicators use shapes in addition to colors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show Legal Moves", isOn: $s.showLegalMovesImmediately)
                Toggle("Celebration Effects", isOn: $s.confettiEnabled)
            }

            Section("Path Study") {
                HStack {
                    Text("Auto-play Speed")
                    Spacer()
                    Text("\(s.autoPlaySpeed, specifier: "%.1f")s")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $s.autoPlaySpeed, in: 1.0...6.0, step: 0.5)
            }

            if subscriptionService.isPro {
                Section("AI Coach") {
                    Picker("Provider", selection: $s.llmProvider) {
                        Text("On-Device").tag("onDevice")
                        Text("Cloud (Claude)").tag("claude")
                        Text("Local Server").tag("ollama")
                    }
                }

                DisclosureGroup("Advanced") {
                    Section {
                        HStack {
                            if showingAPIKey {
                                TextField("sk-ant-...", text: $s.claudeAPIKey)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("sk-ant-...", text: $s.claudeAPIKey)
                            }
                            Button {
                                showingAPIKey.toggle()
                            } label: {
                                Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if s.claudeAPIKey.isEmpty {
                            Text("Required for Cloud mode. Get a key at console.anthropic.com")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Key saved", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    Section {
                        HStack {
                            Text("Local Server")
                            Spacer()
                            TextField("host:port", text: $s.ollamaHost)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        HStack {
                            Text("Model")
                            Spacer()
                            TextField("model name", text: $s.ollamaModel)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                }
            } else {
                Section("AI Coaching") {
                    ProGateBanner(feature: "AI coaching settings")
                }
            }

            if subscriptionService.isPro {
                Section {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                        Text("Pro Unlocked")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                }
            }

            Section("Help") {
                Button {
                    showOnboarding = true
                } label: {
                    Label("Replay Introduction", systemImage: "arrow.counterclockwise")
                }
                FeedbackButton(screen: "Settings")
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
            }

            #if DEBUG
            Section("Developer") {
                NavigationLink {
                    DebugStateView()
                } label: {
                    Label("Debug States", systemImage: "ladybug")
                }
            }
            #endif
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showProUpgrade) {
            ProUpgradeView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
}
