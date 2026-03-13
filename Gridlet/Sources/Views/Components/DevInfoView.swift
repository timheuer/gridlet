import SwiftUI

/// Developer info sheet showing puzzle metadata, word list, and grid stats.
struct DevInfoView: View {
    let viewModel: PuzzleViewModel
    @Environment(\.dismiss) private var dismiss

    private var puzzle: PuzzleDefinition { viewModel.puzzle }

    private var filledCells: Int {
        let dim = puzzle.gridSize.dimension
        var count = 0
        for r in 0..<dim {
            for c in 0..<dim {
                if puzzle.solutionLetter(row: r, col: c) != nil { count += 1 }
            }
        }
        return count
    }

    private var totalCells: Int {
        let dim = puzzle.gridSize.dimension
        return dim * dim
    }

    private var fillPercent: Int {
        guard totalCells > 0 else { return 0 }
        return Int(Double(filledCells) / Double(totalCells) * 100)
    }

    private var acrossWords: [WordEntry] {
        puzzle.words.filter { $0.direction == .across }.sorted { ($0.startRow, $0.startCol) < ($1.startRow, $1.startCol) }
    }

    private var downWords: [WordEntry] {
        puzzle.words.filter { $0.direction == .down }.sorted { ($0.startRow, $0.startCol) < ($1.startRow, $1.startCol) }
    }

    private var aiAvailable: Bool {
        AIWordService.shared.isAvailable
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Puzzle Info") {
                    LabeledContent("Seed", value: String(puzzle.seed))
                    LabeledContent("Grid Size", value: "\(puzzle.gridSize.dimension)×\(puzzle.gridSize.dimension)")
                    LabeledContent("Generated", value: puzzle.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Puzzle ID", value: puzzle.id.uuidString.prefix(8) + "…")
                    LabeledContent("AI Generated", value: puzzle.isAIGenerated ? "Yes" : "No")
                }

                Section("Grid Stats") {
                    LabeledContent("Total Cells", value: "\(totalCells)")
                    LabeledContent("Filled Cells", value: "\(filledCells)")
                    LabeledContent("Black Cells", value: "\(totalCells - filledCells)")
                    LabeledContent("Fill Density", value: "\(fillPercent)%")
                    LabeledContent("Word Count", value: "\(puzzle.words.count)")
                    LabeledContent("Across Words", value: "\(acrossWords.count)")
                    LabeledContent("Down Words", value: "\(downWords.count)")
                }

                Section("Game State") {
                    LabeledContent("Is Daily", value: viewModel.gameState.isDaily ? "Yes" : "No")
                    LabeledContent("Completed", value: viewModel.isCompleted ? "Yes" : "No")
                    LabeledContent("Checks Used", value: "\(viewModel.gameState.checksUsed)")
                    LabeledContent("Elapsed", value: formatTime(viewModel.gameState.elapsedSeconds))
                    LabeledContent("Cells Filled", value: "\(playerFilledCount)/\(filledCells)")
                }

                Section("Environment") {
                    LabeledContent("Apple Intelligence", value: aiAvailable ? "Available" : "Unavailable")
                    #if DEBUG
                    LabeledContent("Build", value: "Debug")
                    #else
                    LabeledContent("Build", value: "Release")
                    #endif
                }

                Section("Words — Across") {
                    ForEach(acrossWords, id: \.text) { word in
                        wordRow(word)
                    }
                }

                Section("Words — Down") {
                    ForEach(downWords, id: \.text) { word in
                        wordRow(word)
                    }
                }
            }
            .navigationTitle("Dev Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func wordRow(_ word: WordEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(word.text)
                    .font(.system(.body, design: .monospaced).bold())
                Spacer()
                Text("(\(word.startRow),\(word.startCol))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(word.clue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var playerFilledCount: Int {
        let dim = puzzle.gridSize.dimension
        var count = 0
        for r in 0..<dim {
            for c in 0..<dim {
                if viewModel.gameState.playerGrid[r][c] != nil { count += 1 }
            }
        }
        return count
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
