import SwiftUI
import ChessboardKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(ModelDownloadService.self) private var modelDownloadService

    @State private var showingAPIKey = false
    @State private var showOnboarding = false
    @State private var showProUpgrade = false
    @State private var showELOAssessment = false

    var body: some View {
        @Bindable var s = settings

        Form {
            // MARK: - Your Level

            Section {
                Stepper("Skill Level: \(s.userELO)", value: $s.userELO, in: 400...2000, step: 100)

                Button {
                    showELOAssessment = true
                } label: {
                    Label("Assess My Level", systemImage: "brain.head.profile")
                }
            } header: {
                Label("Your Level", systemImage: "chart.bar.fill")
            } footer: {
                Text("This affects opponent difficulty, coaching language, and scoring thresholds")
            }
            .listRowBackground(AppColor.cardBackground)

            // MARK: - Board & Appearance

            Section {
                NavigationLink {
                    BoardThemePickerView()
                } label: {
                    HStack {
                        Text("Board Theme")
                        Spacer()
                        boardThemeMiniSwatch(settings.boardTheme)
                    }
                }

                NavigationLink {
                    PieceStylePickerView()
                } label: {
                    HStack {
                        Text("Piece Style")
                        Spacer()
                        pieceStyleMiniPreview(settings.pieceStyle)
                    }
                }

                Picker("Move Notation", selection: $s.notationStyle) {
                    Text("Standard (Nf3)").tag("san")
                    Text("English (Knight f3)").tag("english")
                    Text("UCI (g1f3)").tag("uci")
                }

                Toggle("Show Legal Moves", isOn: $s.showLegalMovesImmediately)

                Toggle("Color-Blind Friendly", isOn: $s.colorblindMode)
                if s.colorblindMode {
                    Text("Stage indicators use shapes in addition to colors")
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            } header: {
                Label("Board & Appearance", systemImage: "paintbrush")
            }
            .listRowBackground(AppColor.cardBackground)

            // MARK: - Gameplay

            Section {
                Stepper("Opponent Level: \(s.opponentELO)", value: $s.opponentELO, in: 800...2000, step: 100)

                HStack {
                    Text("Auto-play Speed")
                    Spacer()
                    Text("\(s.autoPlaySpeed, specifier: "%.1f")s")
                        .foregroundStyle(AppColor.secondaryText)
                }
                Slider(value: $s.autoPlaySpeed, in: 1.0...6.0, step: 0.5)

                Stepper("Daily Goal: \(s.dailyGoalTarget) games/day", value: $s.dailyGoalTarget, in: 1...10)
                Toggle("Celebration Effects", isOn: $s.confettiEnabled)
                Toggle("Dual Opening Detection", isOn: $s.holisticOpeningHints)
            } header: {
                Label("Gameplay", systemImage: "gamecontroller")
            } footer: {
                Text("Opponent Level sets default strength in trainer mode. Auto-play Speed controls opening demo animations. Dual Opening Detection shows what each side is playing independently.")
            }
            .listRowBackground(AppColor.cardBackground)

            // MARK: - Sound & Feedback

            Section {
                Toggle("Sound Effects", isOn: $s.soundEnabled)
                Toggle("Haptic Feedback", isOn: $s.hapticsEnabled)
            } header: {
                Label("Sound & Feedback", systemImage: "speaker.wave.2")
            }
            .listRowBackground(AppColor.cardBackground)

            // MARK: - AI Coach

            if subscriptionService.isPro {
                Section {
                    Picker("Provider", selection: $s.llmProvider) {
                        Text("On-Device").tag("onDevice")
                        Text("Cloud (Claude)").tag("claude")
                        Text("Local Server").tag("ollama")
                    }

                    // Provider description
                    providerDescription(for: s.llmProvider)

                    if s.llmProvider == "onDevice" {
                        modelDownloadRow
                    }

                    if s.llmProvider == "claude" {
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
                                    .foregroundStyle(AppColor.secondaryText)
                            }
                        }

                        if s.claudeAPIKey.isEmpty {
                            Text("Required for Cloud mode. Get a key at console.anthropic.com")
                                .font(.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        } else {
                            Label("Key saved", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    if s.llmProvider == "ollama" {
                        HStack {
                            Text("Server")
                            Spacer()
                            TextField("host:port", text: $s.ollamaHost)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(AppColor.secondaryText)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        HStack {
                            Text("Model")
                            Spacer()
                            TextField("model name", text: $s.ollamaModel)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(AppColor.secondaryText)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                } header: {
                    Label("AI Coach", systemImage: "brain.head.profile")
                }
                .listRowBackground(AppColor.cardBackground)
            } else {
                Section {
                    ProGateBanner(feature: "AI coaching settings")
                } header: {
                    Label("AI Coach", systemImage: "brain.head.profile")
                }
                .listRowBackground(AppColor.cardBackground)
            }

            // MARK: - Subscription

            Section {
                if subscriptionService.isPro {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                        Text("Pro Unlocked")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                } else {
                    Button {
                        showProUpgrade = true
                    } label: {
                        Label("Upgrade to Pro", systemImage: "crown")
                    }
                }

                if subscriptionService.isPro {
                    NavigationLink {
                        GameImportView()
                    } label: {
                        Label("Import Games", systemImage: "square.and.arrow.down")
                    }
                }
            } header: {
                Label("Subscription", systemImage: "crown.fill")
            } footer: {
                if subscriptionService.isPro {
                    Text("Import PGN files from other apps")
                }
            }
            .listRowBackground(AppColor.cardBackground)

            // MARK: - About

            Section {
                Button {
                    showOnboarding = true
                } label: {
                    Label("Replay Introduction", systemImage: "arrow.counterclockwise")
                }

                FeedbackButton(screen: "Settings")

                NavigationLink {
                    AcknowledgmentsView()
                } label: {
                    Label("Acknowledgments", systemImage: "hands.clap")
                }

                Link("Privacy Policy", destination: URL(string: "https://chesscoach.app/privacy")!)
                Link("Support", destination: URL(string: "mailto:chesscoach@marklifson.com")!)

                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(AppColor.secondaryText)
                }
            } header: {
                Label("About", systemImage: "info.circle")
            }
            .listRowBackground(AppColor.cardBackground)

            #if DEBUG
            Section {
                NavigationLink {
                    DebugStateView()
                } label: {
                    Label("Debug States", systemImage: "ladybug")
                }
            } header: {
                Label("Developer", systemImage: "hammer")
            }
            .listRowBackground(AppColor.cardBackground)
            #endif
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showProUpgrade) {
            ProUpgradeView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .sheet(isPresented: $showELOAssessment) {
            ELOAssessmentView { elo in
                settings.userELO = elo
            }
        }
    }

    // MARK: - Provider Descriptions

    @ViewBuilder
    private func providerDescription(for provider: String) -> some View {
        switch provider {
        case "onDevice":
            Text("Runs privately on your phone. No internet needed.")
                .font(.caption)
                .foregroundStyle(AppColor.secondaryText)
        case "claude":
            Text("Uses Anthropic's API. Requires API key.")
                .font(.caption)
                .foregroundStyle(AppColor.secondaryText)
        case "ollama":
            Text("Connect to your own Ollama instance.")
                .font(.caption)
                .foregroundStyle(AppColor.secondaryText)
        default:
            EmptyView()
        }
    }

    // MARK: - Inline Previews

    private func boardThemeMiniSwatch(_ theme: BoardTheme) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                theme.lightColor.frame(width: 14, height: 14)
                theme.darkColor.frame(width: 14, height: 14)
            }
            GridRow {
                theme.darkColor.frame(width: 14, height: 14)
                theme.lightColor.frame(width: 14, height: 14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func pieceStyleMiniPreview(_ style: PieceStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(settings.boardTheme.darkColor)
                .frame(width: 28, height: 28)

            if let uiImage = ChessboardModel.pieceImage(named: "wK", folder: style.assetFolder) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            }
        }
    }

    // MARK: - Model Download

    private var modelDownloadRow: some View {
        Group {
            switch modelDownloadService.state {
            case .downloaded:
                HStack {
                    Label("AI Model Ready", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                    Spacer()
                    if let size = modelDownloadService.downloadedModelSize {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }

                if ModelDownloadService.downloadedModelPath != nil,
                   ModelDownloadService.bundledModelPath != nil {
                    Button(role: .destructive) {
                        modelDownloadService.deleteDownloadedModel()
                    } label: {
                        Label("Delete Downloaded Model (using bundled)", systemImage: "trash")
                            .font(.subheadline)
                    }
                }

            case .notDownloaded:
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        modelDownloadService.startDownload()
                    } label: {
                        Label("Download AI Model", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline)
                    }
                    Text("~\(ByteCountFormatter.string(fromByteCount: AppConfig.modelDownload.expectedSizeBytes, countStyle: .file)) — Wi-Fi recommended")
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Downloading AI Model...")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    ProgressView(value: progress)
                        .tint(.cyan)

                    Button("Cancel", role: .destructive) {
                        modelDownloadService.cancelDownload()
                    }
                    .font(.caption)
                }

            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Download Failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    Button {
                        modelDownloadService.startDownload()
                    } label: {
                        Text("Retry")
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}
