import SwiftUI

struct ProgressDetailView: View {
    @State private var showELOAssessment = false
    @Environment(AppSettings.self) private var settings
    private let progressService = PlayerProgressService.shared
    private var styleProfile: StyleProfile {
        let mastery = PersistenceService.shared.loadAllMastery()
        return StyleProfile.compute(mastery: mastery, database: OpeningDatabase.shared)
    }

    var body: some View {
        NavigationStack {
            List {
                // Estimated rating
                Section {
                    HStack(spacing: AppSpacing.lg) {
                        VStack(spacing: AppSpacing.xxs) {
                            Text("\(progressService.estimatedRating)")
                                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(AppColor.primaryText)
                            Text("Estimated Rating")
                                .font(.caption)
                                .foregroundStyle(AppColor.tertiaryText)
                        }

                        Spacer()

                        VStack(spacing: AppSpacing.xxs) {
                            Image(systemName: progressService.trend.icon)
                                .font(.title)
                                .foregroundStyle(trendColor)
                            Text(progressService.trend.label)
                                .font(.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }

                        Spacer()

                        VStack(spacing: AppSpacing.xxs) {
                            ProgressRing(
                                progress: progressService.confidence,
                                color: AppColor.info,
                                lineWidth: 3.5,
                                size: 44
                            )
                            .overlay {
                                Text("\(Int(progressService.confidence * 100))%")
                                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                                    .foregroundStyle(AppColor.secondaryText)
                            }
                            Text("Confidence")
                                .font(.caption2)
                                .foregroundStyle(AppColor.tertiaryText)
                        }
                    }
                    .padding(.vertical, AppSpacing.sm)
                }
                .listRowBackground(AppColor.cardBackground)

                // Recalibrate
                Section {
                    Button {
                        showELOAssessment = true
                    } label: {
                        Label("Recalibrate Skill Level", systemImage: "brain.head.profile")
                    }
                }
                .listRowBackground(AppColor.cardBackground)

                // Split ELO tracks
                Section("Rating Tracks") {
                    eloTrack(
                        label: "Human-Like",
                        icon: "person.fill",
                        elo: progressService.humanELO,
                        color: .cyan
                    )

                    eloTrack(
                        label: "Engine",
                        icon: "cpu",
                        elo: progressService.engineELO,
                        color: .orange
                    )
                }
                .listRowBackground(AppColor.cardBackground)

                // Recent win rate
                let totalRecent = progressService.humanELO.recentResults + progressService.engineELO.recentResults
                if !totalRecent.isEmpty {
                    Section("Performance") {
                        let winRate = totalRecent.reduce(0, +) / Double(totalRecent.count)
                        HStack {
                            Label {
                                Text("Recent Win Rate")
                                    .foregroundStyle(AppColor.primaryText)
                            } icon: {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundStyle(AppColor.info)
                            }
                            Spacer()
                            Text("\(Int(winRate * 100))%")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(winRate >= 0.5 ? AppColor.success : AppColor.warning)
                        }

                        HStack {
                            Label {
                                Text("Games Played")
                                    .foregroundStyle(AppColor.primaryText)
                            } icon: {
                                Image(systemName: "gamecontroller")
                                    .foregroundStyle(AppColor.secondaryText)
                            }
                            Spacer()
                            Text("\(progressService.humanELO.gamesPlayed + progressService.engineELO.gamesPlayed)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(AppColor.secondaryText)
                        }
                    }
                    .listRowBackground(AppColor.cardBackground)
                }

                // Style profile
                if styleProfile.isReady {
                    Section("Your Style") {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text(styleProfile.styleLabel)
                                .font(.headline)
                                .foregroundStyle(AppColor.primaryText)

                            ForEach(styleProfile.tagWeights.prefix(5)) { tw in
                                HStack(spacing: AppSpacing.sm) {
                                    Text(tw.tag.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(AppColor.secondaryText)
                                        .frame(width: 90, alignment: .leading)

                                    GeometryReader { geo in
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(AppColor.info)
                                            .frame(width: geo.size.width * tw.weight)
                                    }
                                    .frame(height: 8)
                                }
                            }
                        }
                        .padding(.vertical, AppSpacing.xs)
                    }
                    .listRowBackground(AppColor.cardBackground)
                }
            }
            .listStyle(.insetGrouped)
            .background(AppColor.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Your Progress")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showELOAssessment) {
                ELOAssessmentView { elo in
                    settings.userELO = elo
                }
            }
        }
    }

    private func eloTrack(label: String, icon: String, elo: ELOEstimate, color: Color) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
                HStack(spacing: AppSpacing.sm) {
                    Text("\(elo.rating)")
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(AppColor.primaryText)
                    if elo.peak > elo.rating {
                        Text("Peak \(elo.peak)")
                            .font(.caption2)
                            .foregroundStyle(AppColor.gold.opacity(0.7))
                    }
                }
            }

            Spacer()

            Text("\(elo.gamesPlayed) games")
                .font(.caption)
                .foregroundStyle(AppColor.tertiaryText)
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    private var trendColor: Color {
        switch progressService.trend {
        case .improving: return AppColor.success
        case .declining: return AppColor.error
        case .stable: return AppColor.secondaryText
        }
    }
}
