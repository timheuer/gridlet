import Foundation
import GameplayKit
import CryptoKit
import os

private let logger = Logger(subsystem: "com.timheuer.gridlet", category: "PuzzleGenerator")

/// Generates PuzzleDefinition instances from a seed.
/// Uses Apple Intelligence for word/clue generation when available,
/// falls back to the bundled word list.
final class PuzzleGeneratorService: @unchecked Sendable {
    /// Golden-ratio stride used to deterministically perturb layout seeds across retries.
    private static let layoutSeedStride: UInt64 = 0x9E3779B97F4A7C15
    private static let maxLayoutSeedAttempts = 4

    private let wordListService: WordListService
    private let aiWordService: AIWordService
    private func minimumWords(for gridSize: GridSize) -> Int {
        gridSize == .six ? 8 : 6
    }

    init(wordListService: WordListService = .shared,
         aiWordService: AIWordService = .shared) {
        self.wordListService = wordListService
        self.aiWordService = aiWordService
    }

    /// Generate a puzzle from a seed using the bundled word list (synchronous, deterministic).
    func generate(seed: UInt64) -> PuzzleDefinition {
        var rng = GKMersenneTwisterRandomSource(seed: seed)
        let gridSize: GridSize = rng.nextInt(upperBound: 4) == 0 ? .five : .six
        let dim = gridSize.dimension

        let allWords = wordListService.words(maxLength: dim)
        return generateFromWords(allWords, seed: seed, gridSize: gridSize)
    }

    /// Generate a puzzle using Apple Intelligence for word/clue generation (async).
    /// Falls back to bundled list if AI is unavailable.
    func generateWithAI(seed: UInt64) async -> PuzzleDefinition {
        var rng = GKMersenneTwisterRandomSource(seed: seed)
        let gridSize: GridSize = rng.nextInt(upperBound: 4) == 0 ? .five : .six
        let dim = gridSize.dimension

        // Get AI-generated words and diagnostics
        let generationResult = await aiWordService.generateWordClues(count: 30, maxLength: dim, seed: seed)
        let wordClues = generationResult.words
        let aiGeneratedWords = generationResult.aiGeneratedWords

        // Build clue lookup from all returned words (AI + supplement)
        let words = wordClues.map { $0.word.uppercased() }
        let allClues = Dictionary(wordClues.map { ($0.word.uppercased(), $0.clue) }, uniquingKeysWith: { first, _ in first })

        // Source-aware clue lookup: only words in aiGeneratedWords are tagged .ai
        let puzzle = generateFromWords(
            words,
            seed: seed,
            gridSize: gridSize,
            aiGenerationStatus: generationResult.status,
            aiGenerationDetail: generationResult.detail,
            clueLookup: { word in
            let uppercased = word.uppercased()
            let clue = allClues[uppercased] ?? self.wordListService.clue(for: uppercased)
            let source: WordSource = aiGeneratedWords.contains(uppercased) ? .ai : .bundled
            return (clue, source)
        },
            aiWords: aiGeneratedWords
        )
        return puzzle
    }

    /// Whether Apple Intelligence is available for word generation.
    var isAIAvailable: Bool { aiWordService.isAvailable }

    // MARK: - Core Generation

    private func generateFromWords(
        _ words: [String],
        seed: UInt64,
        gridSize: GridSize,
        aiGenerationStatus: AIGenerationStatus = .fallbackReasonUnknown,
        aiGenerationDetail: String? = nil,
        clueLookup: ((String) -> (String, WordSource))? = nil,
        aiWords: Set<String> = []
    ) -> PuzzleDefinition {
        let dim = gridSize.dimension
        let lookup = clueLookup ?? { (self.wordListService.clue(for: $0), .bundled) }
        let minWords = minimumWords(for: gridSize)

        let result = runLayoutAttempts(words: words, seed: seed, dim: dim, minWords: minWords, preferredWords: aiWords)
        logger.info("Layout attempt: placed \(result.placed.count)/\(minWords) required words from \(words.count) candidates")

        // If we fell short of the minimum, supplement with a limited number of
        // bundled words and retry — keeping AI words at the front for layout priority.
        if result.placed.count < minWords {
            let existingWords = Set(words.map { $0.uppercased() })
            let extra = wordListService.words(maxLength: dim)
                .filter { !existingWords.contains($0.uppercased()) }
                .prefix(60)
            let combined = words + extra
            logger.info("Layout supplement: adding \(extra.count) bundled words for retry (\(combined.count) total)")
            let retryResult = runLayoutAttempts(words: combined, seed: seed, dim: dim, minWords: minWords, preferredWords: aiWords)
            logger.info("Layout retry: placed \(retryResult.placed.count) words (was \(result.placed.count))")

            if retryResult.placed.count > result.placed.count {
                let placedWords = retryResult.placed.map { $0.word }.joined(separator: ", ")
                logger.info("Using retry layout. Placed words: \(placedWords)")
                return buildPuzzle(
                    seed: seed,
                    gridSize: gridSize,
                    placed: retryResult.placed,
                    grid: retryResult.grid,
                    aiGenerationStatus: aiGenerationStatus,
                    aiGenerationDetail: aiGenerationDetail,
                    clueLookup: lookup
                )
            }
        }

        return buildPuzzle(
            seed: seed,
            gridSize: gridSize,
            placed: result.placed,
            grid: result.grid,
            aiGenerationStatus: aiGenerationStatus,
            aiGenerationDetail: aiGenerationDetail,
            clueLookup: lookup
        )
    }

    private struct LayoutResult {
        let placed: [CrosswordLayoutGenerator.PlacedWord]
        let grid: [[Character?]]
        let filledCells: Int
    }

    private func runLayoutAttempts(words: [String], seed: UInt64, dim: Int, minWords: Int, preferredWords: Set<String> = []) -> LayoutResult {
        var bestPlaced: [CrosswordLayoutGenerator.PlacedWord] = []
        var bestGrid: [[Character?]] = []
        var bestFilledCells = -1

        for attemptIndex in 0..<Self.maxLayoutSeedAttempts {
            let layoutSeed = seed &+ (UInt64(attemptIndex) &* Self.layoutSeedStride)
            let generator = CrosswordLayoutGenerator(columns: dim, rows: dim, seed: layoutSeed)
            generator.generate(words: words, minimumWordCount: minWords, preferredWords: preferredWords)

            let grid = generator.gridLetters()
            let filledCells = grid.flatMap { $0 }.compactMap { $0 }.count

            if bestGrid.isEmpty ||
                generator.result.count > bestPlaced.count ||
                (generator.result.count == bestPlaced.count && filledCells > bestFilledCells) {
                bestPlaced = generator.result
                bestGrid = grid
                bestFilledCells = filledCells
            }

            let bestDensity = Double(bestFilledCells) / Double(dim * dim)
            if bestPlaced.count >= minWords &&
                bestDensity >= CrosswordLayoutGenerator.targetDensityThreshold {
                break
            }
        }

        return LayoutResult(placed: bestPlaced, grid: bestGrid, filledCells: bestFilledCells)
    }

    private func buildPuzzle(
        seed: UInt64,
        gridSize: GridSize,
        placed: [CrosswordLayoutGenerator.PlacedWord],
        grid: [[Character?]],
        aiGenerationStatus: AIGenerationStatus = .fallbackReasonUnknown,
        aiGenerationDetail: String? = nil,
        clueLookup: (String) -> (String, WordSource)
    ) -> PuzzleDefinition {
        let dim = gridSize.dimension

        let cells: [[CellDefinition]] = (0..<dim).map { row in
            (0..<dim).map { col in
                CellDefinition(row: row, col: col, letter: grid[row][col])
            }
        }

        let words: [WordEntry] = placed.map { pw in
            let (clue, source) = clueLookup(pw.word)
            return WordEntry(
                direction: pw.direction,
                text: pw.word,
                clue: clue,
                startRow: pw.row - 1,
                startCol: pw.column - 1,
                source: source
            )
        }

        // If none of the placed words are actually AI-generated, downgrade the status
        let aiWordCount = words.filter { $0.source == .ai }.count
        let bundledWordCount = words.filter { $0.source == .bundled }.count
        logger.info("Final puzzle: \(aiWordCount) AI words, \(bundledWordCount) bundled words out of \(words.count) total")
        for w in words {
            logger.debug("  \(w.source == .ai ? "🤖" : "📦") \(w.direction == .across ? "→" : "↓") \(w.text) — \(w.clue)")
        }

        let effectiveStatus: AIGenerationStatus
        let effectiveDetail: String?
        if aiWordCount == 0 && aiGenerationStatus.isAIGenerated {
            logger.warning("No AI words placed in grid — downgrading status from \(aiGenerationStatus.rawValue) to validationFailed")
            effectiveStatus = .validationFailed
            effectiveDetail = (aiGenerationDetail ?? "") + " No AI words were placed in the final grid."
        } else {
            effectiveStatus = aiGenerationStatus
            effectiveDetail = aiGenerationDetail
        }

        return PuzzleDefinition(
            seed: seed,
            gridSize: gridSize,
            cells: cells,
            words: words,
            isAIGenerated: effectiveStatus.isAIGenerated,
            aiGenerationStatus: effectiveStatus,
            aiGenerationDetail: effectiveDetail
        )
    }

    // MARK: - Daily Puzzle Seed

    /// Deterministic seed from a date string. Same date always produces the same seed.
    static func seed(for dateString: String) -> UInt64 {
        let input = "com.timheuer.gridlet:\(dateString)"
        let hash = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(hash)
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(bytes[i]) << (i * 8)
        }
        return value
    }
}
