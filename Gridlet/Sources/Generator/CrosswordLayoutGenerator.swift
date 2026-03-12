// Crossword layout generator for small grids (5×5, 6×6).
// Adapted from iOS-Crosswords-Generator by Maxim Bilan (MIT License).
// Rewritten for dense small-grid generation with seeded RNG.

import Foundation
import GameplayKit

/// A crossword grid generator optimized for small (5×5, 6×6) grids
/// with seeded random number generation for deterministic puzzles.
final class CrosswordLayoutGenerator {
    /// Small mobile grids feel sparse below ~60% fill, but higher targets make it much harder
    /// for the search to find a valid layout that can still place enough intersecting words.
    static let targetDensityThreshold = 0.6
    private static let maxLayoutAttempts = 60

    struct PlacedWord {
        let word: String
        let column: Int  // 1-indexed
        let row: Int     // 1-indexed
        let direction: WordDirection
    }

    private let columns: Int
    private let rows: Int
    private var rng: GKMersenneTwisterRandomSource

    private var grid: [[String]]
    /// Tracks which direction(s) occupy each cell to prevent same-direction overlaps.
    private var directionGrid: [[Set<WordDirection>]]
    private var currentWords: [String] = []
    private(set) var result: [PlacedWord] = []

    private let emptySymbol = "-"

    init(columns: Int, rows: Int, maxLoops: Int = 2000, seed: UInt64) {
        self.columns = columns
        self.rows = rows
        self.rng = GKMersenneTwisterRandomSource(seed: seed)
        self.grid = Array(repeating: Array(repeating: "-", count: columns), count: rows)
        self.directionGrid = Array(repeating: Array(repeating: Set<WordDirection>(), count: columns), count: rows)
    }

    /// Generate a crossword layout from the given words.
    /// Runs multiple full attempts with different word orderings and keeps the densest result.
    func generate(words: [String], minimumWordCount: Int = 0) {
        let candidates = words
            .map { $0.uppercased() }
            .filter { $0.count <= max(columns, rows) && $0.count >= 2 }

        var bestPlaced: [PlacedWord] = []
        var bestGrid: [[String]] = []
        var bestFilledCells = -1
        let overlapScores = buildOverlapScores(for: candidates)
        let attempts = Self.maxLayoutAttempts

        for attemptIndex in 0..<attempts {
            // Reset grid
            grid = Array(repeating: Array(repeating: emptySymbol, count: columns), count: rows)
            directionGrid = Array(repeating: Array(repeating: Set<WordDirection>(), count: columns), count: rows)
            currentWords.removeAll()
            var placed: [PlacedWord] = []

            let shuffled = orderedWords(for: candidates, overlapScores: overlapScores, attempt: attemptIndex)

            // Place words
            for word in shuffled {
                if !currentWords.contains(word) {
                    if let pw = tryPlace(word) {
                        placed.append(pw)
                        currentWords.append(word)
                    }
                }
            }

            // Second pass: retry words that failed (grid state has changed)
            for word in shuffled {
                if !currentWords.contains(word) {
                    if let pw = tryPlace(word) {
                        placed.append(pw)
                        currentWords.append(word)
                    }
                }
            }

            let filledCells = grid.flatMap { $0 }.filter { $0 != emptySymbol }.count
            if placed.count > bestPlaced.count || (placed.count == bestPlaced.count && filledCells > bestFilledCells) {
                bestPlaced = placed
                bestGrid = grid
                bestFilledCells = filledCells
            }

            // Keep searching until the layout hits the requested word count
            // and a healthy fill ratio for these small grids.
            let totalCells = columns * rows
            let density = Double(filledCells) / Double(totalCells)
            if placed.count >= minimumWordCount && density >= Self.targetDensityThreshold {
                break
            }
        }

        result = bestPlaced
        grid = bestGrid
    }

    private func buildOverlapScores(for words: [String]) -> [String: Int] {
        var scores: [String: Int] = [:]
        let letterSets = Dictionary(uniqueKeysWithValues: words.map { ($0, Set($0)) })

        for word in words {
            let uniqueLetters = letterSets[word]!
            let score = words.reduce(into: 0) { partialResult, candidate in
                guard candidate != word else { return }
                let candidateLetters = letterSets[candidate]!
                partialResult += uniqueLetters.intersection(candidateLetters).count
            }
            scores[word] = score
        }

        return scores
    }

    private func orderedWords(for candidates: [String], overlapScores: [String: Int], attempt: Int) -> [String] {
        var ordered = candidates
        ordered.shuffle(using: &rng)

        // Rotate through length-first, overlap-first, and short-first orderings
        // so each layout attempt explores a meaningfully different packing strategy.
        switch attempt % 3 {
        case 0:
            // Start with longer words to build a central spine, then prefer words
            // with lots of shared letters so later placements can intersect cleanly.
            ordered.sort { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return overlapScores[lhs, default: 0] > overlapScores[rhs, default: 0]
            }
        case 1:
            // Favor high-overlap words even if they are shorter; this tends to
            // unlock extra placements once the grid already has a few anchors.
            ordered.sort { lhs, rhs in
                let lhsScore = overlapScores[lhs, default: 0]
                let rhsScore = overlapScores[rhs, default: 0]
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.count < rhs.count
            }
        default:
            // Start from shorter words to squeeze more entries into the same
            // footprint, using overlap score as the secondary tiebreaker.
            ordered.sort { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count < rhs.count
                }
                return overlapScores[lhs, default: 0] > overlapScores[rhs, default: 0]
            }
        }

        return ordered
    }

    // MARK: - Word Placement

    private func tryPlace(_ word: String) -> PlacedWord? {
        if currentWords.isEmpty {
            return placeFirstWord(word)
        }
        return placeByIntersection(word)
    }

    private func placeFirstWord(_ word: String) -> PlacedWord? {
        // For the first word, try placing it through the center of the grid
        let directions: [WordDirection] = rng.nextInt(upperBound: 2) == 0
            ? [.across, .down] : [.down, .across]

        for direction in directions {
            let positions = startingPositions(for: word, direction: direction)
            for (col, row) in positions {
                if fitScore(column: col, row: row, direction: direction, word: word) > 0 {
                    commitWord(column: col, row: row, direction: direction, word: word)
                    return PlacedWord(word: word, column: col, row: row, direction: direction)
                }
            }
        }
        return nil
    }

    /// Generate starting positions sorted by proximity to grid center.
    private func startingPositions(for word: String, direction: WordDirection) -> [(col: Int, row: Int)] {
        var positions: [(Int, Int)] = []
        let maxCol = direction == .across ? columns - word.count + 1 : columns
        let maxRow = direction == .down ? rows - word.count + 1 : rows

        for r in 1...maxRow {
            for c in 1...maxCol {
                positions.append((c, r))
            }
        }

        let cx = Double(columns + 1) / 2.0
        let cy = Double(rows + 1) / 2.0
        positions.sort { a, b in
            let da = abs(Double(a.0) - cx) + abs(Double(a.1) - cy)
            let db = abs(Double(b.0) - cx) + abs(Double(b.1) - cy)
            return da < db
        }
        return positions
    }

    private func placeByIntersection(_ word: String) -> PlacedWord? {
        var coords = findIntersections(for: word)
        coords.shuffle(using: &rng)
        coords.sort { $0.score > $1.score }

        for coord in coords {
            commitWord(column: coord.col, row: coord.row, direction: coord.direction, word: word)
            return PlacedWord(word: word, column: coord.col, row: coord.row, direction: coord.direction)
        }
        return nil
    }

    private func findIntersections(for word: String) -> [(col: Int, row: Int, direction: WordDirection, score: Int)] {
        var coords: [(col: Int, row: Int, direction: WordDirection, score: Int)] = []
        let chars = Array(word)

        for (letterIndex, letter) in chars.enumerated() {
            let letterStr = String(letter)
            for r in 0..<rows {
                for c in 0..<columns {
                    guard grid[r][c] == letterStr else { continue }

                    // Try placing down: the intersection is at row r, so word starts at r - letterIndex
                    let downStartRow = r - letterIndex
                    if downStartRow >= 0 && downStartRow + word.count <= rows {
                        let score = fitScore(column: c + 1, row: downStartRow + 1, direction: .down, word: word)
                        if score > 0 {
                            coords.append((c + 1, downStartRow + 1, .down, score))
                        }
                    }

                    // Try placing across: intersection at col c, word starts at c - letterIndex
                    let acrossStartCol = c - letterIndex
                    if acrossStartCol >= 0 && acrossStartCol + word.count <= columns {
                        let score = fitScore(column: acrossStartCol + 1, row: r + 1, direction: .across, word: word)
                        if score > 0 {
                            coords.append((acrossStartCol + 1, r + 1, .across, score))
                        }
                    }
                }
            }
        }
        return coords
    }

    // MARK: - Fit Checking (1-indexed coordinates)

    private func fitScore(column: Int, row: Int, direction: WordDirection, word: String) -> Int {
        var c = column
        var r = row
        guard c >= 1, r >= 1 else { return 0 }

        // Check the word doesn't extend beyond grid bounds
        if direction == .across {
            guard c + word.count - 1 <= columns else { return 0 }
        } else {
            guard r + word.count - 1 <= rows else { return 0 }
        }

        // Check cell before word start is clear (no adjacent word running into this one)
        if direction == .across {
            if !cellClear(column: c - 1, row: r) { return 0 }
        } else {
            if !cellClear(column: c, row: r - 1) { return 0 }
        }

        // Check cell after word end is clear
        if direction == .across {
            if !cellClear(column: c + word.count, row: r) { return 0 }
        } else {
            if !cellClear(column: c, row: r + word.count) { return 0 }
        }

        var score = 1
        var hasIntersection = currentWords.isEmpty  // first word doesn't need intersection

        for (i, letter) in word.enumerated() {
            let letterStr = String(letter)
            let cell = getCell(column: c, row: r)

            if cell == letterStr {
                // Reject if this cell is already used by a word in the same direction
                // (e.g., two down words sharing the same column cells)
                if directionGrid[r - 1][c - 1].contains(direction) {
                    return 0
                }
                // Valid intersection with a perpendicular word
                score += 1
                hasIntersection = true
            } else if cell == emptySymbol {
                // Empty cell — check that perpendicular neighbors are clear
                // (to avoid creating unintended adjacent parallel words)
                if direction == .across {
                    if !cellClear(column: c, row: r - 1) { return 0 }
                    if !cellClear(column: c, row: r + 1) { return 0 }
                } else {
                    if !cellClear(column: c - 1, row: r) { return 0 }
                    if !cellClear(column: c + 1, row: r) { return 0 }
                }
            } else {
                // Cell occupied by a different letter — can't place here
                return 0
            }

            if direction == .across { c += 1 } else { r += 1 }
        }

        return hasIntersection ? score : 0
    }

    private func commitWord(column: Int, row: Int, direction: WordDirection, word: String) {
        var c = column
        var r = row
        for letter in word {
            setCell(column: c, row: r, value: String(letter))
            directionGrid[r - 1][c - 1].insert(direction)
            if direction == .across { c += 1 } else { r += 1 }
        }
    }

    // MARK: - Grid Access (1-indexed)

    private func setCell(column: Int, row: Int, value: String) {
        grid[row - 1][column - 1] = value
    }

    private func getCell(column: Int, row: Int) -> String {
        grid[row - 1][column - 1]
    }

    private func cellClear(column: Int, row: Int) -> Bool {
        if column < 1 || row < 1 || column > columns || row > rows {
            return true  // out of bounds = clear
        }
        return getCell(column: column, row: row) == emptySymbol
    }

    /// Returns the grid as a 2D array of characters (nil = empty/black cell).
    func gridLetters() -> [[Character?]] {
        grid.map { row in
            row.map { cell in
                cell == emptySymbol ? nil : cell.first
            }
        }
    }
}

// Extend GKMersenneTwisterRandomSource to conform to RandomNumberGenerator
extension GKMersenneTwisterRandomSource: @retroactive RandomNumberGenerator {
    public func next() -> UInt64 {
        let high = UInt64(bitPattern: Int64(nextInt()))
        let low = UInt64(bitPattern: Int64(nextInt()))
        return (high << 32) | (low & 0xFFFFFFFF)
    }
}
