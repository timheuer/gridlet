import Testing
import Foundation
@testable import Gridlet

@Suite("Model Tests")
struct ModelTests {

    @Test("GridSize dimensions")
    func gridSizeDimensions() {
        #expect(GridSize.five.dimension == 5)
        #expect(GridSize.six.dimension == 6)
    }

    @Test("WordDirection toggle")
    func wordDirectionToggle() {
        #expect(WordDirection.across.toggled == .down)
        #expect(WordDirection.down.toggled == .across)
    }

    @Test("WordEntry cells calculation - across")
    func wordEntryCellsAcross() {
        let word = WordEntry(direction: .across, text: "HELLO", clue: "Greeting", startRow: 1, startCol: 0)
        let cells = word.cells
        #expect(cells.count == 5)
        #expect(cells[0].row == 1 && cells[0].col == 0)
        #expect(cells[4].row == 1 && cells[4].col == 4)
    }

    @Test("WordEntry cells calculation - down")
    func wordEntryCellsDown() {
        let word = WordEntry(direction: .down, text: "CAT", clue: "Pet", startRow: 0, startCol: 2)
        let cells = word.cells
        #expect(cells.count == 3)
        #expect(cells[0].row == 0 && cells[0].col == 2)
        #expect(cells[2].row == 2 && cells[2].col == 2)
    }

    @Test("GameState initialization")
    func gameStateInit() {
        let state = GameState(puzzleId: UUID(), isDaily: true, gridSize: .five)
        #expect(state.playerGrid.count == 5)
        #expect(state.playerGrid[0].count == 5)
        #expect(state.isCompleted == false)
        #expect(state.checksUsed == 0)
        #expect(state.activeDirection == .across)
    }

    @Test("GameState Codable round-trip")
    func gameStateCodable() throws {
        var state = GameState(puzzleId: UUID(), isDaily: false, gridSize: .six)
        state.playerGrid[0][0] = "A"
        state.playerGrid[2][3] = "B"
        state.selectedCell = CellPosition(row: 1, col: 2)
        state.checkedWrongCells.insert(CellPosition(row: 0, col: 0))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GameState.self, from: data)

        #expect(decoded.puzzleId == state.puzzleId)
        #expect(decoded.playerGrid[0][0] == "A")
        #expect(decoded.playerGrid[2][3] == "B")
        #expect(decoded.playerGrid[1][1] == nil)
        #expect(decoded.selectedCell == CellPosition(row: 1, col: 2))
        #expect(decoded.checkedWrongCells.contains(CellPosition(row: 0, col: 0)))
    }

    @Test("PlayerStats streak logic")
    func playerStatsStreak() {
        var stats = PlayerStats()

        let record = CompletionRecord(
            puzzleId: UUID(),
            elapsedSeconds: 120,
            gridSize: .five,
            checksUsed: 1,
            isDaily: true
        )
        stats.recordDailyCompletion(record: record)

        #expect(stats.currentStreak == 1)
        #expect(stats.longestStreak == 1)
        #expect(stats.totalPuzzlesSolved == 1)
        #expect(stats.totalDailySolved == 1)
        #expect(stats.lastDailyCompletedDate == PlayerStats.todayString())
    }

    @Test("PlayerStats unlimited does not affect streak")
    func unlimitedNoStreak() {
        var stats = PlayerStats()
        let record = CompletionRecord(
            puzzleId: UUID(),
            elapsedSeconds: 60,
            gridSize: .six,
            checksUsed: 0,
            isDaily: false
        )
        stats.recordUnlimitedCompletion(record: record)

        #expect(stats.currentStreak == 0)
        #expect(stats.totalPuzzlesSolved == 1)
        #expect(stats.totalDailySolved == 0)
    }

    @Test("PuzzleDefinition helpers")
    func puzzleDefinitionHelpers() {
        let cells: [[CellDefinition]] = (0..<5).map { row in
            (0..<5).map { col in
                if row == 0 && col < 3 {
                    return CellDefinition(row: row, col: col, letter: ["C", "A", "T"][col])
                }
                return CellDefinition(row: row, col: col, letter: nil)
            }
        }

        let word = WordEntry(direction: .across, text: "CAT", clue: "Pet", startRow: 0, startCol: 0)
        let puzzle = PuzzleDefinition(seed: 42, gridSize: .five, cells: cells, words: [word])

        #expect(puzzle.solutionLetter(row: 0, col: 0) == "C")
        #expect(puzzle.isBlackCell(row: 1, col: 0) == true)
        #expect(puzzle.words(at: 0, col: 1).count == 1)
        #expect(puzzle.word(at: 0, col: 0, direction: .across)?.text == "CAT")
        #expect(puzzle.word(at: 0, col: 0, direction: .down) == nil)
                #expect(puzzle.aiGenerationStatus == .fallbackReasonUnknown)
        }

        @Test("PuzzleDefinition preserves AI diagnostics")
        func puzzleDefinitionAIDiagnostics() throws {
                let cells = [[CellDefinition(row: 0, col: 0, letter: "A")]]
                let word = WordEntry(direction: .across, text: "A", clue: "Letter", startRow: 0, startCol: 0)
                let puzzle = PuzzleDefinition(
                        seed: 7,
                        gridSize: .five,
                        cells: cells,
                        words: [word],
                        aiGenerationStatus: .validationFailed,
                        aiGenerationDetail: "Accepted 12 validated AI entries; required at least 40 to use AI output."
                )

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(puzzle)

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(PuzzleDefinition.self, from: data)

                #expect(decoded.isAIGenerated == false)
                #expect(decoded.aiGenerationStatus == .validationFailed)
                #expect(decoded.aiGenerationDetail == "Accepted 12 validated AI entries; required at least 40 to use AI output.")
        }

        @Test("PuzzleDefinition decodes legacy AI metadata")
        func puzzleDefinitionLegacyAIDecode() throws {
                let legacyJSON = """
                {
                    "id": "11111111-1111-1111-1111-111111111111",
                    "seed": 42,
                    "gridSize": "five",
                    "cells": [[{"row": 0, "col": 0, "letter": "C"}]],
                    "words": [{
                        "id": "22222222-2222-2222-2222-222222222222",
                        "direction": "across",
                        "text": "CAT",
                        "clue": "Pet",
                        "startRow": 0,
                        "startCol": 0
                    }],
                    "generatedAt": "2026-03-13T00:00:00Z",
                    "isAIGenerated": false
                }
                """.data(using: .utf8)!

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(PuzzleDefinition.self, from: legacyJSON)

                #expect(decoded.isAIGenerated == false)
                #expect(decoded.aiGenerationStatus == .fallbackReasonUnknown)
                #expect(decoded.aiGenerationDetail == nil)
    }

    @Test("CellDefinition Codable round-trip")
    func cellDefinitionCodable() throws {
        let cell = CellDefinition(row: 2, col: 3, letter: "X")
        let blackCell = CellDefinition(row: 0, col: 0, letter: nil)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let cellData = try encoder.encode(cell)
        let decodedCell = try decoder.decode(CellDefinition.self, from: cellData)
        #expect(decodedCell.letter == "X")
        #expect(decodedCell.row == 2)

        let blackData = try encoder.encode(blackCell)
        let decodedBlack = try decoder.decode(CellDefinition.self, from: blackData)
        #expect(decodedBlack.letter == nil)
    }
}
