import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "crown.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("ChessCoach")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
