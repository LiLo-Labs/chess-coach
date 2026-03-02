import SwiftUI
import ChessboardKit

struct PieceStylePickerView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SubscriptionService.self) private var subscriptionService

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

        List {
            Section("Free Styles") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(PieceStyle.freeStyles) { style in
                        pieceStyleSwatch(style)
                    }
                }
                .padding(.vertical, AppSpacing.xxs)
            }
            .listRowBackground(AppColor.cardBackground)

            if !PieceStyle.proStyles.isEmpty {
                Section("Premium") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(PieceStyle.proStyles) { style in
                            pieceStyleSwatch(style)
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
        .navigationTitle("Piece Style")
        .navigationBarTitleDisplayMode(.inline)
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
                        .frame(width: 56, height: 56)
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
                            .frame(width: 40, height: 40)
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
                            : locked ? AppColor.tertiaryText : AppColor.secondaryText
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }
}
