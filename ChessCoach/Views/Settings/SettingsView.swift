import SwiftUI
import ChessboardKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(ModelDownloadService.self) private var modelDownloadService

    @State private var showingAPIKey = false
    @State private var showOnboarding = false
    @State private var showProUpgrade = false

    var body: some View {
        @Bindable var s = settings

        Form {
            // MARK: - Appearance

            Section {
                boardThemePicker
            } header: {
                Label("Board Theme", systemImage: "checkerboard.rectangle")
            }

            Section("Piece Style") {
                pieceStylePicker
            }

            Section("Display") {
                Picker("Move Notation", selection: $s.notationStyle) {
                    Text("Standard (Nf3)").tag("san")
                    Text("English (Knight f3)").tag("english")
                    Text("UCI (g1f3)").tag("uci")
                }
                Toggle("Show Legal Moves", isOn: $s.showLegalMovesImmediately)
                Toggle("Celebration Effects", isOn: $s.confettiEnabled)
                Toggle("Color-Blind Friendly", isOn: $s.colorblindMode)
                if s.colorblindMode {
                    Text("Stage indicators use shapes in addition to colors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Gameplay

            Section("Player") {
                Stepper("Your Skill Level: \(s.userELO)", value: $s.userELO, in: 400...2000, step: 100)
                Stepper("Opponent Level: \(s.opponentELO)", value: $s.opponentELO, in: 800...2000, step: 100)
                Text("The AI opponent adjusts to match the skill level")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Goals & Preferences") {
                Stepper("Daily Goal: \(s.dailyGoalTarget) games/day", value: $s.dailyGoalTarget, in: 1...10)

                HStack {
                    Text("Auto-play Speed")
                    Spacer()
                    Text("\(s.autoPlaySpeed, specifier: "%.1f")s")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $s.autoPlaySpeed, in: 1.0...6.0, step: 0.5)

                Toggle("Sound Effects", isOn: $s.soundEnabled)
                Toggle("Haptic Feedback", isOn: $s.hapticsEnabled)
            }

            // MARK: - AI Coach

            if subscriptionService.isPro {
                Section {
                    Picker("Provider", selection: $s.llmProvider) {
                        Text("On-Device").tag("onDevice")
                        Text("Cloud (Claude)").tag("claude")
                        Text("Local Server").tag("ollama")
                    }

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

                    if s.llmProvider == "ollama" {
                        HStack {
                            Text("Server")
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
                } header: {
                    Label("AI Coach", systemImage: "brain.head.profile")
                }
            } else {
                Section("AI Coaching") {
                    ProGateBanner(feature: "AI coaching settings")
                }
            }

            // MARK: - Account & Info

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
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Downloading AI Model...")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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

    // MARK: - Board Theme Picker

    private var boardThemePicker: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(BoardTheme.freeThemes) { theme in
                    boardThemeSwatch(theme)
                }
            }

            if !BoardTheme.proThemes.isEmpty {
                Text("Premium")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(BoardTheme.proThemes) { theme in
                        boardThemeSwatch(theme)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func boardThemeSwatch(_ theme: BoardTheme) -> some View {
        let locked = theme.isPro && !subscriptionService.isPro
        return Button {
            if locked { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.boardTheme = theme
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            theme.lightColor.frame(width: 20, height: 20)
                            theme.darkColor.frame(width: 20, height: 20)
                        }
                        GridRow {
                            theme.darkColor.frame(width: 20, height: 20)
                            theme.lightColor.frame(width: 20, height: 20)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(
                                settings.boardTheme == theme ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .opacity(locked ? 0.5 : 1.0)

                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                }

                Text(theme.displayName)
                    .font(.caption2)
                    .foregroundStyle(
                        settings.boardTheme == theme
                            ? Color.accentColor
                            : locked ? .secondary.opacity(0.5) : .secondary
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    // MARK: - Piece Style Picker

    private var pieceStylePicker: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(PieceStyle.freeStyles) { style in
                    pieceStyleSwatch(style)
                }
            }

            if !PieceStyle.proStyles.isEmpty {
                Text("Premium")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(PieceStyle.proStyles) { style in
                        pieceStyleSwatch(style)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func pieceStyleSwatch(_ style: PieceStyle) -> some View {
        let locked = style.isPro && !subscriptionService.isPro
        return Button {
            if locked { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.pieceStyle = style
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(settings.boardTheme.darkColor)
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    settings.pieceStyle == style ? Color.accentColor : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .opacity(locked ? 0.5 : 1.0)

                    if let uiImage = ChessboardModel.pieceImage(named: "wK", folder: style.assetFolder) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .opacity(locked ? 0.5 : 1.0)
                    }

                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                }

                Text(style.displayName)
                    .font(.caption2)
                    .foregroundStyle(
                        settings.pieceStyle == style
                            ? Color.accentColor
                            : locked ? .secondary.opacity(0.5) : .secondary
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }
}
