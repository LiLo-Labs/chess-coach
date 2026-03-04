import SwiftUI

struct OpeningSettingsView: View {
    let opening: Opening
    @State private var positions: [PositionMastery] = []
    @State private var showResetAllConfirm = false
    @State private var lineToReset: OpeningLine?
    @Environment(\.dismiss) private var dismiss

    init(opening: Opening) {
        self.opening = opening
    }

    private var allLines: [OpeningLine] {
        opening.lines ?? [
            OpeningLine(
                id: "\(opening.id)/main",
                name: OpeningNode.generateLineName(moves: opening.mainLine),
                moves: opening.mainLine,
                branchPoint: 0,
                parentLineID: nil
            )
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(role: .destructive) {
                        showResetAllConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All Paths")
                        }
                    }
                } header: {
                    Text("Reset Progress")
                } footer: {
                    Text("This will clear all learning progress for this opening.")
                }

                Section("Individual Paths") {
                    ForEach(allLines) { line in
                        let linePositions = positions.filter { $0.lineID == line.id }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.name)
                                    .font(.subheadline.weight(.medium))
                                if !linePositions.isEmpty {
                                    let mastered = linePositions.filter(\.isMastered).count
                                    Text("\(linePositions.count) positions, \(mastered) mastered")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Not started")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            if !linePositions.isEmpty {
                                Button("Restart") {
                                    lineToReset = line
                                }
                                .font(.caption.weight(.medium))
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle(opening.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { reloadPositions() }
            .alert("Reset All Progress?", isPresented: $showResetAllConfirm) {
                Button("Reset", role: .destructive) {
                    var all = PersistenceService.shared.loadAllPositionMastery()
                    all.removeAll { $0.openingID == opening.id }
                    PersistenceService.shared.savePositionMastery(all)
                    reloadPositions()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will erase all learning progress for \(opening.name). This cannot be undone.")
            }
            .alert("Reset Line?", isPresented: Binding(
                get: { lineToReset != nil },
                set: { if !$0 { lineToReset = nil } }
            )) {
                Button("Reset", role: .destructive) {
                    if let line = lineToReset {
                        var all = PersistenceService.shared.loadAllPositionMastery()
                        all.removeAll { $0.openingID == opening.id && $0.lineID == line.id }
                        PersistenceService.shared.savePositionMastery(all)
                        reloadPositions()
                        lineToReset = nil
                    }
                }
                Button("Cancel", role: .cancel) { lineToReset = nil }
            } message: {
                if let line = lineToReset {
                    Text("Reset progress for \"\(line.name)\"? This cannot be undone.")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func reloadPositions() {
        positions = PersistenceService.shared.loadAllPositionMastery().filter { $0.openingID == opening.id }
    }
}
