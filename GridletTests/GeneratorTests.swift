import Testing
import Foundation
@testable import Gridlet

@Suite("Generator Tests")
struct GeneratorTests {

    @Test("CrosswordLayoutGenerator produces placed words")
    func layoutGeneratorProducesWords() {
        let generator = CrosswordLayoutGenerator(columns: 6, rows: 6, seed: 12345)
        let words = ["APPLE", "PLANE", "EAGLE", "LATER", "PEAR", "ATE", "RAN"]
        generator.generate(words: words)

        #expect(generator.result.count >= 2, "Should place at least 2 words")

        // All placed words should be from our input
        for placed in generator.result {
            #expect(words.contains(placed.word))
        }
    }

    @Test("Same seed produces same layout")
    func deterministicGeneration() {
        let words = ["HELLO", "WORLD", "HELP", "LONG", "OLD"]

        let gen1 = CrosswordLayoutGenerator(columns: 5, rows: 5, seed: 42)
        gen1.generate(words: words)

        let gen2 = CrosswordLayoutGenerator(columns: 5, rows: 5, seed: 42)
        gen2.generate(words: words)

        #expect(gen1.result.count == gen2.result.count, "Same seed should produce same word count")

        for i in 0..<gen1.result.count {
            #expect(gen1.result[i].word == gen2.result[i].word)
            #expect(gen1.result[i].column == gen2.result[i].column)
            #expect(gen1.result[i].row == gen2.result[i].row)
            #expect(gen1.result[i].direction == gen2.result[i].direction)
        }
    }

    @Test("Different seeds produce different layouts")
    func differentSeeds() {
        let words = ["HELLO", "WORLD", "HELP", "LONG", "OLD", "POLE", "HOLE", "LOWER", "PROWL"]

        let gen1 = CrosswordLayoutGenerator(columns: 6, rows: 6, seed: 1)
        gen1.generate(words: words)

        let gen2 = CrosswordLayoutGenerator(columns: 6, rows: 6, seed: 54321)
        gen2.generate(words: words)

        // Very unlikely to be identical with different seeds
        let same = gen1.result.count == gen2.result.count &&
            gen1.result.indices.allSatisfy { i in
                gen1.result[i].word == gen2.result[i].word &&
                gen1.result[i].column == gen2.result[i].column &&
                gen1.result[i].row == gen2.result[i].row
            }
        #expect(!same, "Different seeds should likely produce different layouts")
    }

    @Test("Grid letters match placed words")
    func gridLettersConsistency() {
        let generator = CrosswordLayoutGenerator(columns: 5, rows: 5, seed: 77)
        generator.generate(words: ["CAT", "ACE", "TEA", "ATE"])
        let grid = generator.gridLetters()

        for placed in generator.result {
            var r = placed.row - 1  // Convert to 0-indexed
            var c = placed.column - 1
            for letter in placed.word {
                #expect(grid[r][c] == letter, "Grid should contain placed word letters")
                if placed.direction == .across {
                    c += 1
                } else {
                    r += 1
                }
            }
        }
    }

    @Test("PuzzleGeneratorService seed produces deterministic seed")
    func seedFromDate() {
        let seed1 = PuzzleGeneratorService.seed(for: "2026-03-11")
        let seed2 = PuzzleGeneratorService.seed(for: "2026-03-11")
        let seed3 = PuzzleGeneratorService.seed(for: "2026-03-12")

        #expect(seed1 == seed2, "Same date should produce same seed")
        #expect(seed1 != seed3, "Different dates should produce different seeds")
    }

    @Test("Words placed within grid bounds")
    func wordsWithinBounds() {
        let generator = CrosswordLayoutGenerator(columns: 5, rows: 5, seed: 555)
        generator.generate(words: ["HELLO", "WORLD", "HELP", "OLE", "POD"])

        for placed in generator.result {
            let startRow = placed.row - 1
            let startCol = placed.column - 1
            #expect(startRow >= 0)
            #expect(startCol >= 0)

            if placed.direction == .across {
                #expect(startCol + placed.word.count <= 5, "Word should not overflow columns")
            } else {
                #expect(startRow + placed.word.count <= 5, "Word should not overflow rows")
            }
        }
    }

    @Test("CrosswordLayoutGenerator can reach a denser small-grid word count")
    func minimumWordTargetOnDenseWordList() {
        let generator = CrosswordLayoutGenerator(columns: 5, rows: 5, seed: 12345)
        let words = [
            "APPLE", "PLANE", "EAGLE", "LATER", "PEAR", "ATE", "RAN", "CAT",
            "DOG", "TEA", "ACE", "OAK", "SUN", "PEN", "ICE", "NET", "LOG",
            "BAT", "HEN", "FIG", "GUM", "RUG", "TIN", "JAM", "VET"
        ]

        generator.generate(words: words, minimumWordCount: 6)

        #expect(generator.result.count >= 6, "Dense word lists should produce at least 6 placed words on a 5×5 grid")
    }
}
