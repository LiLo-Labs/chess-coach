import SwiftUI

struct HomeView: View {
    private let database = OpeningDatabase()
    @State private var selectedOpening: Opening?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // White openings
                    sectionHeader("Play as White")
                    ForEach(database.openings(forColor: .white)) { opening in
                        OpeningCard(opening: opening)
                            .onTapGesture {
                                selectedOpening = opening
                            }
                    }

                    // Black openings
                    sectionHeader("Play as Black")
                    ForEach(database.openings(forColor: .black)) { opening in
                        OpeningCard(opening: opening)
                            .onTapGesture {
                                selectedOpening = opening
                            }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ChessCoach")
            .fullScreenCover(item: $selectedOpening) { opening in
                SessionView(opening: opening)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.top, 8)
    }
}
