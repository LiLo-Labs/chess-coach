import SwiftUI

struct CoachingBubble: View {
    let text: String
    let isLoading: Bool

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.title3)
                .foregroundStyle(.yellow)

            if isLoading {
                HStack(spacing: 4) {
                    Text("Thinking")
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appeared = true
            }
        }
        .onChange(of: text) { _, _ in
            appeared = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}
