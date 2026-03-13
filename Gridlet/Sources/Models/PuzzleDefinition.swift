import Foundation

/// A complete puzzle definition — the grid layout, placed words, and their clues.
struct PuzzleDefinition: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let seed: UInt64
    let gridSize: GridSize
    let cells: [[CellDefinition]]
    let words: [WordEntry]
    let generatedAt: Date
    /// Whether this puzzle was generated using Apple Intelligence.
    let isAIGenerated: Bool

    init(
        id: UUID = UUID(),
        seed: UInt64,
        gridSize: GridSize,
        cells: [[CellDefinition]],
        words: [WordEntry],
        generatedAt: Date = Date(),
        isAIGenerated: Bool = false
    ) {
        self.id = id
        self.seed = seed
        self.gridSize = gridSize
        self.cells = cells
        self.words = words
        self.generatedAt = generatedAt
        self.isAIGenerated = isAIGenerated
    }

    /// Returns the solution letter at (row, col), or nil for black cells.
    func solutionLetter(row: Int, col: Int) -> Character? {
        guard row >= 0, row < gridSize.dimension,
              col >= 0, col < gridSize.dimension else { return nil }
        return cells[row][col].letter
    }

    /// Whether a cell is a black (blocked) cell.
    func isBlackCell(row: Int, col: Int) -> Bool {
        solutionLetter(row: row, col: col) == nil
    }

    /// Returns the words that pass through the given cell.
    func words(at row: Int, col: Int) -> [WordEntry] {
        words.filter { word in
            word.cells.contains { $0.row == row && $0.col == col }
        }
    }

    /// Returns the word at a given cell for a specific direction, if any.
    func word(at row: Int, col: Int, direction: WordDirection) -> WordEntry? {
        words.first { word in
            word.direction == direction &&
            word.cells.contains { $0.row == row && $0.col == col }
        }
    }
}
