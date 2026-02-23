import SwiftUI

struct OpeningCard: View {
    let opening: Opening

    var body: some View {
        HStack(spacing: 16) {
            // Color indicator
            Circle()
                .fill(opening.color == .white ? .white : .black)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .strokeBorder(.gray.opacity(0.3), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(opening.name)
                    .font(.headline)

                Text(opening.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Difficulty stars
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= opening.difficulty ? "star.fill" : "star")
                        .font(.caption2)
                        .foregroundStyle(star <= opening.difficulty ? .yellow : .gray.opacity(0.3))
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}
