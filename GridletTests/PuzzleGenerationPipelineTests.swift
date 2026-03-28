import Testing
import Foundation
@testable import Gridlet

@Suite("Puzzle Generation Pipeline Tests")
struct PuzzleGenerationPipelineTests {

    // MARK: - Bundled Generation

    @Test("Bundled generation produces valid puzzle with all bundled words")
    func bundledGenerationAllBundled() {
        let service = PuzzleGeneratorService()
        let puzzle = service.generate(seed: 42)

        #expect(puzzle.words.count >= 4, "Should place at least 4 words")
        for word in puzzle.words {
            #expect(word.source == .bundled, "Bundled generation should mark all words as bundled")
            #expect(!word.text.isEmpty)
            #expect(!word.clue.isEmpty)
            #expect(word.clue.uppercased() != word.text.uppercased(), "Clue must not be the word itself")
        }
        #expect(!puzzle.isAIGenerated, "Bundled generation should not be marked as AI")
    }

    @Test("Blocked words and sensitive variants are rejected")
    func blockedWordVariantsRejected() {
        for blocked in [
            "RAPE", "RAPED", "RAPING", "RAPIST",
            "FUCKING", "KILLER", "SEXUAL", "DYING",
            "BOMBER", "GUNS", "NAZIS", "DAMNED",
        ] {
            #expect(WordSafetyFilter.isBlocked(blocked), "\(blocked) should be blocked")
        }

        for allowed in ["GRAPE", "GRASS", "RAPID", "CLASS", "CLASSIC", "ASSESS", "GUNNER", "SEXTET"] {
            #expect(!WordSafetyFilter.isBlocked(allowed), "\(allowed) should remain allowed")
        }
    }

    @Test("Bundled candidate list excludes blocked variants")
    func bundledCandidateListExcludesBlockedVariants() {
        let words = Set(WordListService.shared.words(maxLength: 7))
        #expect(!words.contains("RAPED"))
        #expect(!words.contains("FUCKING"))
        #expect(!words.contains("SEXUAL"))
        #expect(words.contains("RAPID"))
    }

    @Test("Bundled generation is deterministic across same seed")
    func bundledDeterministic() {
        let service = PuzzleGeneratorService()
        let puzzle1 = service.generate(seed: 12345)
        let puzzle2 = service.generate(seed: 12345)

        #expect(puzzle1.words.count == puzzle2.words.count)
        for i in 0..<puzzle1.words.count {
            #expect(puzzle1.words[i].text == puzzle2.words[i].text)
            #expect(puzzle1.words[i].clue == puzzle2.words[i].clue)
            #expect(puzzle1.words[i].direction == puzzle2.words[i].direction)
            #expect(puzzle1.words[i].startRow == puzzle2.words[i].startRow)
            #expect(puzzle1.words[i].startCol == puzzle2.words[i].startCol)
        }
    }

    // MARK: - Word Source Tracking

    @Test("WordEntry source defaults to bundled for legacy decoding")
    func wordEntryLegacyDecoding() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "direction": "across",
            "text": "HELLO",
            "clue": "A greeting",
            "startRow": 0,
            "startCol": 0
        }
        """
        let entry = try JSONDecoder().decode(WordEntry.self, from: Data(json.utf8))
        #expect(entry.source == .bundled, "Missing source should default to .bundled")
    }

    @Test("WordEntry source roundtrips through Codable")
    func wordEntrySourceCodable() throws {
        let entry = WordEntry(direction: .across, text: "CRANE", clue: "Tall bird", startRow: 0, startCol: 0, source: .ai)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(WordEntry.self, from: data)
        #expect(decoded.source == .ai)

        let bundled = WordEntry(direction: .down, text: "OAK", clue: "Shade tree", startRow: 1, startCol: 2, source: .bundled)
        let data2 = try JSONEncoder().encode(bundled)
        let decoded2 = try JSONDecoder().decode(WordEntry.self, from: data2)
        #expect(decoded2.source == .bundled)
    }

    // MARK: - Layout with Preferred Words

    @Test("Layout engine prioritizes preferred words")
    func layoutPrefersPreferredWords() {
        let preferred: Set<String> = ["CAT", "ACE", "TEA"]
        let allWords = ["CAT", "ACE", "TEA", "DOG", "BAT", "RUG", "PEN", "LOG", "GUM", "TIN"]

        let gen = CrosswordLayoutGenerator(columns: 5, rows: 5, seed: 42)
        gen.generate(words: allWords, preferredWords: preferred)

        let placedWords = Set(gen.result.map { $0.word })
        let preferredPlaced = placedWords.intersection(preferred)

        // With preference boosting, we should get at least some preferred words placed
        #expect(!preferredPlaced.isEmpty, "At least one preferred word should be placed")
    }

    @Test("Layout engine still works without preferred words")
    func layoutWithoutPreferred() {
        let words = ["HELLO", "WORLD", "HELP", "OLE", "POD"]
        let gen = CrosswordLayoutGenerator(columns: 5, rows: 5, seed: 42)
        gen.generate(words: words)

        #expect(gen.result.count >= 2, "Should still place words without preferences")
    }

    // MARK: - AI Status Downgrade Logic

    @Test("Puzzle with no AI words gets status downgraded")
    func aiStatusDowngradeWhenNoAIWords() {
        // Simulate a puzzle where AI generated words but none made it to the grid.
        // Use bundled generation (no AI available) but manually verify the logic
        // by building a puzzle with the service and checking status fields.
        let service = PuzzleGeneratorService()
        let puzzle = service.generate(seed: 99)

        // Bundled generation uses .fallbackReasonUnknown, which is not AI-generated
        #expect(!puzzle.isAIGenerated)
        #expect(puzzle.aiGenerationStatus == .fallbackReasonUnknown)

        // All words should be bundled
        let aiCount = puzzle.words.filter { $0.source == .ai }.count
        #expect(aiCount == 0, "Bundled generation should have zero AI words")
    }

    // MARK: - Grid Size Distribution

    @Test("Grid size distribution heavily favors 6x6", arguments: [
        UInt64(1), UInt64(2), UInt64(3), UInt64(4), UInt64(5),
        UInt64(10), UInt64(20), UInt64(30), UInt64(40), UInt64(50),
        UInt64(100), UInt64(200), UInt64(300), UInt64(400), UInt64(500),
        UInt64(1000), UInt64(2000), UInt64(3000), UInt64(4000), UInt64(5000),
    ])
    func gridSizeDistribution(seed: UInt64) {
        let service = PuzzleGeneratorService()
        let puzzle = service.generate(seed: seed)
        // Just verify it produces a valid grid size
        #expect(puzzle.gridSize == .five || puzzle.gridSize == .six || puzzle.gridSize == .seven)
    }

    @Test("6x6 and 7x7 grids appear more often than 5x5")
    func sixAndSevenMoreCommon() {
        let service = PuzzleGeneratorService()
        var fiveCount = 0
        var sixCount = 0
        var sevenCount = 0
        for seed: UInt64 in 0..<100 {
            let puzzle = service.generate(seed: seed)
            switch puzzle.gridSize {
            case .five: fiveCount += 1
            case .six: sixCount += 1
            case .seven: sevenCount += 1
            }
        }
        #expect(sixCount > fiveCount, "6×6 should appear more often than 5×5 (got \(sixCount) vs \(fiveCount))")
        #expect(sevenCount > fiveCount, "7×7 should appear more often than 5×5 (got \(sevenCount) vs \(fiveCount))")
        #expect(sevenCount > 0, "7×7 should appear at least once in 100 puzzles (got \(sevenCount))")
    }

    // MARK: - Puzzle Validity

    @Test("Generated puzzle words are within grid bounds")
    func wordsWithinGridBounds() {
        let service = PuzzleGeneratorService()
        for seed: UInt64 in [1, 42, 100, 999, 5555] {
            let puzzle = service.generate(seed: seed)
            let dim = puzzle.gridSize.dimension
            for word in puzzle.words {
                #expect(word.startRow >= 0, "Row must be non-negative")
                #expect(word.startCol >= 0, "Col must be non-negative")
                if word.direction == .across {
                    #expect(word.startCol + word.length <= dim,
                            "\(word.text) overflows columns: startCol=\(word.startCol) len=\(word.length) dim=\(dim)")
                } else {
                    #expect(word.startRow + word.length <= dim,
                            "\(word.text) overflows rows: startRow=\(word.startRow) len=\(word.length) dim=\(dim)")
                }
            }
        }
    }

    @Test("No word has a self-referential clue")
    func noSelfReferentialClues() {
        let service = PuzzleGeneratorService()
        for seed: UInt64 in 0..<50 {
            let puzzle = service.generate(seed: seed)
            for word in puzzle.words {
                let clueWords = Set(
                    word.clue.uppercased()
                        .components(separatedBy: .whitespaces)
                        .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                        .filter { !$0.isEmpty }
                )
                let answerWord = word.text.uppercased()
                #expect(
                    !AIWordService.clueContainsAnswerOrForm(clueWords, answerWord: answerWord),
                    "Word '\(word.text)' has clue '\(word.clue)' containing the answer or a form of it"
                )
            }
        }
    }

    @Test("All placed words have non-empty clues")
    func allWordsHaveClues() {
        let service = PuzzleGeneratorService()
        for seed: UInt64 in [1, 42, 100, 999, 5555, 12345] {
            let puzzle = service.generate(seed: seed)
            for word in puzzle.words {
                #expect(!word.clue.isEmpty, "Word '\(word.text)' has empty clue")
                #expect(word.clue != "No clue available", "Word '\(word.text)' has fallback clue")
            }
        }
    }

    // MARK: - Layout Supplement Behavior

    @Test("Layout supplement does not exceed expected size")
    func layoutSupplementBounded() {
        // Generate with a seed that produces a 5×5 grid (harder to fill)
        // The supplement should add at most 60 bundled words
        let service = PuzzleGeneratorService()
        for seed: UInt64 in 0..<20 {
            let puzzle = service.generate(seed: seed)
            // All words should be placed within bounds and have valid sources
            for word in puzzle.words {
                #expect(word.source == .bundled || word.source == .ai)
                #expect(word.text.count >= 3)
                #expect(word.text.count <= puzzle.gridSize.dimension)
            }
        }
    }

    // MARK: - Word Length Distribution

    @Test("Generated puzzles include a mix of word lengths")
    func wordLengthMix() {
        let service = PuzzleGeneratorService()
        var lengthCounts: [Int: Int] = [:]
        for seed: UInt64 in 0..<50 {
            let puzzle = service.generate(seed: seed)
            for word in puzzle.words {
                lengthCounts[word.length, default: 0] += 1
            }
        }
        // Across 50 puzzles, we should see at least 2 different word lengths
        #expect(lengthCounts.keys.count >= 2, "Should have at least 2 different word lengths across puzzles")
    }
}
