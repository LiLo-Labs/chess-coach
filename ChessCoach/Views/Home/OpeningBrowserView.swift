import SwiftUI

struct OpeningBrowserView: View {
    private let database = OpeningDatabase.shared
    @State private var selectedColor: Opening.PlayerColor = .white
    @State private var searchText = ""
    @State private var allMastery: [String: OpeningMastery] = [:]
    @State private var lockedOpeningToShow: Opening?
    @State private var styleProfile = StyleProfile(tagWeights: [], totalSessions: 0)
    @Environment(SubscriptionService.self) private var subscriptionService

    private func filteredOpenings(forColor color: Opening.PlayerColor) -> [Opening] {
        let all = database.openings(forColor: color)
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func groupedOpenings(forColor color: Opening.PlayerColor) -> [(title: String, openings: [Opening])] {
        let openings = filteredOpenings(forColor: color)
        let groups: [(String, ClosedRange<Int>)] = [
            ("Beginner", 1...1),
            ("Intermediate", 2...2),
            ("Advanced", 3...5)
        ]
        return groups.compactMap { title, range in
            let matching = openings.filter { range.contains($0.difficulty) }
            return matching.isEmpty ? nil : (title, matching)
        }
    }

    var body: some View {
        List {
            // Color picker
            Section {
                Picker("Color", selection: $selectedColor.animation(.easeInOut(duration: 0.15))) {
                    Text("White").tag(Opening.PlayerColor.white)
                    Text("Black").tag(Opening.PlayerColor.black)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(AppColor.cardBackground)

            // Recommended openings based on style
            if styleProfile.isReady {
                let played = Set(allMastery.filter { $0.value.sessionsPlayed > 0 }.map(\.key))
                let recommended = styleProfile.recommendedOpenings(from: database, played: played)
                    .filter { $0.color == selectedColor }
                if !recommended.isEmpty {
                    Section("Recommended for You") {
                        ForEach(recommended.prefix(3)) { opening in
                            let accessible = subscriptionService.isOpeningAccessible(opening.id)
                            if accessible {
                                NavigationLink {
                                    OpeningDetailView(opening: opening)
                                } label: {
                                    openingRow(opening: opening, locked: false)
                                }
                                .listRowBackground(AppColor.cardBackground)
                            } else {
                                Button {
                                    lockedOpeningToShow = opening
                                } label: {
                                    openingRow(opening: opening, locked: true)
                                }
                                .listRowBackground(AppColor.cardBackground)
                            }
                        }
                    }
                }
            }

            // Openings by difficulty
            let groups = groupedOpenings(forColor: selectedColor)
            ForEach(groups, id: \.title) { title, openings in
                Section(title) {
                    ForEach(openings) { opening in
                        let accessible = subscriptionService.isOpeningAccessible(opening.id)
                        if accessible {
                            NavigationLink {
                                OpeningDetailView(opening: opening)
                            } label: {
                                openingRow(opening: opening, locked: false)
                            }
                            .listRowBackground(AppColor.cardBackground)
                        } else {
                            Button {
                                lockedOpeningToShow = opening
                            } label: {
                                openingRow(opening: opening, locked: true)
                            }
                            .listRowBackground(AppColor.cardBackground)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(AppColor.background)
        .scrollContentBackground(.hidden)
        .navigationTitle("Openings")
        .searchable(text: $searchText, prompt: "Search game plans")
        .onAppear {
            allMastery = PersistenceService.shared.loadAllMastery()
            styleProfile = StyleProfile.compute(mastery: allMastery, database: database)
        }
        .sheet(item: $lockedOpeningToShow) { opening in
            ProUpgradeView(lockedOpeningID: opening.id, lockedOpeningName: opening.name)
        }
    }

    // MARK: - Opening Row

    private func openingRow(opening: Opening, locked: Bool) -> some View {
        let mastery = allMastery[opening.id]
        let sessions = mastery?.sessionsPlayed ?? 0

        return HStack(spacing: AppSpacing.md) {
            Circle()
                .fill(opening.color == .white ? Color.white : Color(white: 0.3))
                .frame(width: 12, height: 12)
                .overlay {
                    if opening.color == .white {
                        Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(opening.name)
                    .font(.body)
                    .foregroundStyle(locked ? AppColor.tertiaryText : AppColor.primaryText)

                if locked {
                    Text(opening.description)
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                        .lineLimit(1)
                } else if sessions > 0, let mastery {
                    Text(mastery.currentLayer.displayName)
                        .font(.caption)
                        .foregroundStyle(AppColor.layer(mastery.currentLayer))
                } else {
                    Text(opening.description)
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                        .lineLimit(1)
                }

                if let tags = opening.tags, !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag.capitalized)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(tagColor(tag))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(tagColor(tag).opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            if locked {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(AppColor.gold)
            }
        }
        .opacity(locked ? 0.7 : 1.0)
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "aggressive": return .red
        case "tactical": return .orange
        case "positional": return .blue
        case "solid": return .green
        case "gambit": return .purple
        case "hypermodern": return .cyan
        case "classical": return .brown
        default: return AppColor.secondaryText
        }
    }
}
