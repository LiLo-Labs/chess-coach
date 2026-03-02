import SwiftUI

struct BoardThemePickerView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SubscriptionService.self) private var subscriptionService

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

        List {
            Section("Free Themes") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(BoardTheme.freeThemes) { theme in
                        boardThemeSwatch(theme)
                    }
                }
                .padding(.vertical, AppSpacing.xxs)
            }
            .listRowBackground(AppColor.cardBackground)

            if !BoardTheme.proThemes.isEmpty {
                Section("Premium") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(BoardTheme.proThemes) { theme in
                            boardThemeSwatch(theme)
                        }
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }
                .listRowBackground(AppColor.cardBackground)
            }
        }
        .listStyle(.insetGrouped)
        .background(AppColor.background)
        .scrollContentBackground(.hidden)
        .navigationTitle("Board Theme")
        .navigationBarTitleDisplayMode(.inline)
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
                            theme.lightColor.frame(width: 24, height: 24)
                            theme.darkColor.frame(width: 24, height: 24)
                        }
                        GridRow {
                            theme.darkColor.frame(width: 24, height: 24)
                            theme.lightColor.frame(width: 24, height: 24)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
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
                            : locked ? AppColor.tertiaryText : AppColor.secondaryText
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }
}
