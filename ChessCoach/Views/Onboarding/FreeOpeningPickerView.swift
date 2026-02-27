import SwiftUI

/// Post-onboarding screen where free-tier users pick ONE opening to unlock fully.
/// The picked opening is stored in AppSettings and checked by SubscriptionService.
/// This view is modular — the access policy is centralized in SubscriptionService,
/// so paywall behavior can be changed independently of this picker.
struct FreeOpeningPickerView: View {
    var onComplete: () -> Void = {}

    @Environment(AppSettings.self) private var settings
    @Environment(SubscriptionService.self) private var subscriptionService

    @State private var selectedID: String?
    @State private var confirming = false

    /// All openings available for free-tier picking.
    /// Currently reads from the database; filter logic can be changed here
    /// without touching any other view.
    private var pickableOpenings: [Opening] {
        OpeningDatabase.shared.openings.filter { opening in
            // Show all openings as pickable — the user gets ONE for free.
            // Adjust this filter to change what's available to pick.
            true
        }
    }

    /// Grouped by color for display.
    private var whiteOpenings: [Opening] {
        pickableOpenings.filter { $0.color == .white }
            .sorted { $0.difficulty < $1.difficulty }
    }

    private var blackOpenings: [Opening] {
        pickableOpenings.filter { $0.color == .black }
            .sorted { $0.difficulty < $1.difficulty }
    }

    var body: some View {
        ZStack {
            AppColor.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColor.gold)
                        .symbolEffect(.pulse, options: .repeating.speed(0.5))

                    Text("Choose Your Opening")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColor.primaryText)

                    Text("Pick one opening to unlock completely — all lessons, all practice modes, everything. You can always unlock more later.")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xxxl)
                }
                .padding(.top, AppSpacing.xxxl)
                .padding(.bottom, AppSpacing.lg)

                // Opening list
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        if !whiteOpenings.isEmpty {
                            openingSection(title: "Playing White", openings: whiteOpenings)
                        }
                        if !blackOpenings.isEmpty {
                            openingSection(title: "Playing Black", openings: blackOpenings)
                        }
                    }
                    .padding(.horizontal, AppSpacing.screenPadding)
                    .padding(.bottom, 120) // Space for bottom button
                }
                .scrollIndicators(.hidden)
            }

            // Bottom button
            VStack {
                Spacer()

                VStack(spacing: AppSpacing.sm) {
                    if let selectedID, let opening = OpeningDatabase.shared.opening(byID: selectedID) {
                        Button {
                            confirmSelection(openingID: selectedID)
                        } label: {
                            HStack {
                                Text("Start with \(opening.name)")
                                    .font(.body.weight(.semibold))
                                Image(systemName: "arrow.right")
                                    .font(.body.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColor.success, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Tap an opening to select it")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }

                    Button {
                        skipSelection()
                    } label: {
                        Text("Skip for now")
                            .font(.caption)
                            .foregroundStyle(AppColor.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppSpacing.xxxl)
                .padding(.bottom, 40)
                .background(
                    LinearGradient(
                        colors: [AppColor.background.opacity(0), AppColor.background],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .frame(height: 80)
                    .allowsHitTesting(false),
                    alignment: .top
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Section

    private func openingSection(title: String, openings: [Opening]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.secondaryText)
                .padding(.leading, AppSpacing.xs)

            ForEach(openings) { opening in
                openingCard(opening)
            }
        }
    }

    // MARK: - Card

    private func openingCard(_ opening: Opening) -> some View {
        let isSelected = selectedID == opening.id
        let isFreeAlready = SubscriptionService.freeOpeningIDs.contains(opening.id)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedID = selectedID == opening.id ? nil : opening.id
                }
            } label: {
                HStack(spacing: AppSpacing.md) {
                    // Color indicator
                    Circle()
                        .fill(opening.color == .white ? .white : Color(white: 0.3))
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                        HStack(spacing: AppSpacing.xs) {
                            Text(opening.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColor.primaryText)

                            if isFreeAlready {
                                Text("FREE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(AppColor.success)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(AppColor.success.opacity(0.15), in: Capsule())
                            }
                        }

                        Text(opening.description)
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)
                            .lineLimit(isSelected ? 10 : 2)

                        // Difficulty dots
                        HStack(spacing: 3) {
                            Text("Difficulty")
                                .font(.system(size: 9))
                                .foregroundStyle(AppColor.tertiaryText)
                            ForEach(1...5, id: \.self) { level in
                                Circle()
                                    .fill(level <= opening.difficulty ? AppColor.gold : AppColor.tertiaryText.opacity(0.3))
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }

                    Spacer()

                    // Selection indicator
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AppColor.success : AppColor.tertiaryText)
                }
                .padding(AppSpacing.cardPadding)
            }
            .buttonStyle(.plain)

            // Preview board — shows when selected so user can see the opening played through
            if isSelected {
                OpeningPreviewBoard(opening: opening)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.bottom, AppSpacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(isSelected ? AppColor.success.opacity(0.08) : AppColor.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(isSelected ? AppColor.success.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: - Actions

    private func confirmSelection(openingID: String) {
        // Save the user's pick — SubscriptionService checks this
        settings.pickedFreeOpeningID = openingID
        settings.hasPickedFreeOpening = true
        onComplete()
    }

    private func skipSelection() {
        // User skipped — they still get the default free openings
        settings.hasPickedFreeOpening = true
        onComplete()
    }
}
