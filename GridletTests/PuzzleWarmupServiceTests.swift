import Foundation
import Testing
@testable import Gridlet

@Suite("Puzzle Warmup Service Tests")
struct PuzzleWarmupServiceTests {

    @Test("Daily warmup reuses the in-flight generation task")
    func dailyWarmupReusesInFlightTask() async throws {
        let state = WarmupTestState()
        let expectedPuzzle = makeWarmupPuzzle(
            seed: 11,
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        )
        state.setNextDailyPuzzle(expectedPuzzle)

        let service = PuzzleWarmupService(
            dailyIdentifier: { "2026-03-25" },
            cachedDailyLoader: { _ in state.loadCachedDailyPuzzle() },
            dailyGenerator: {
                state.recordDailyGeneration()
                try? await Task.sleep(for: .milliseconds(50))
                return state.loadNextDailyPuzzle()
            },
            unlimitedGenerator: {
                state.recordUnlimitedGeneration()
                return state.dequeueUnlimitedPuzzle()
            },
            hasUnlimitedInProgress: { state.loadHasUnlimitedInProgress() }
        )

        await service.startWarmup()
        let firstPuzzle = await service.dailyPuzzle()
        let secondPuzzle = await service.dailyPuzzle()

        #expect(firstPuzzle.id == expectedPuzzle.id)
        #expect(secondPuzzle.id == expectedPuzzle.id)
        #expect(state.dailyGenerationCount() == 1)
    }

    @Test("Unlimited warmup returns the preloaded puzzle before generating another")
    func unlimitedWarmupReturnsPreloadedPuzzle() async {
        let state = WarmupTestState()
        let firstPuzzle = makeWarmupPuzzle(
            seed: 21,
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        )
        let secondPuzzle = makeWarmupPuzzle(
            seed: 22,
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        )
        state.setUnlimitedPuzzles([firstPuzzle, secondPuzzle])

        let service = PuzzleWarmupService(
            dailyIdentifier: { "2026-03-25" },
            cachedDailyLoader: { _ in state.loadCachedDailyPuzzle() },
            dailyGenerator: {
                state.recordDailyGeneration()
                return state.loadNextDailyPuzzle()
            },
            unlimitedGenerator: {
                state.recordUnlimitedGeneration()
                try? await Task.sleep(for: .milliseconds(20))
                return state.dequeueUnlimitedPuzzle()
            },
            hasUnlimitedInProgress: { state.loadHasUnlimitedInProgress() }
        )

        await service.startWarmup()
        let warmedPuzzle = await service.unlimitedPuzzle()
        let freshPuzzle = await service.unlimitedPuzzle()

        #expect(warmedPuzzle.id == firstPuzzle.id)
        #expect(freshPuzzle.id == secondPuzzle.id)
        #expect(state.unlimitedGenerationCount() == 2)
    }

    @Test("Unlimited warmup skips background generation when a puzzle is already in progress")
    func unlimitedWarmupSkipsWhenInProgressExists() async throws {
        let state = WarmupTestState()
        state.setHasUnlimitedInProgress(true)
        state.setUnlimitedPuzzles([makeWarmupPuzzle(seed: 31)])

        let service = PuzzleWarmupService(
            dailyIdentifier: { "2026-03-25" },
            cachedDailyLoader: { _ in state.loadCachedDailyPuzzle() },
            dailyGenerator: {
                state.recordDailyGeneration()
                return state.loadNextDailyPuzzle()
            },
            unlimitedGenerator: {
                state.recordUnlimitedGeneration()
                return state.dequeueUnlimitedPuzzle()
            },
            hasUnlimitedInProgress: { state.loadHasUnlimitedInProgress() }
        )

        await service.startWarmup()
        try? await Task.sleep(for: .milliseconds(20))

        #expect(state.unlimitedGenerationCount() == 0)
    }
}

private final class WarmupTestState: @unchecked Sendable {
    private let lock = NSLock()

    var nextDailyPuzzle = makeWarmupPuzzle(seed: 1)
    var cachedDailyPuzzle: PuzzleDefinition?
    var unlimitedPuzzles: [PuzzleDefinition] = []
    var hasUnlimitedInProgress = false

    private var dailyCalls = 0
    private var unlimitedCalls = 0

    func recordDailyGeneration() {
        lock.lock()
        defer { lock.unlock() }
        dailyCalls += 1
    }

    func setNextDailyPuzzle(_ puzzle: PuzzleDefinition) {
        lock.lock()
        defer { lock.unlock() }
        nextDailyPuzzle = puzzle
    }

    func recordUnlimitedGeneration() {
        lock.lock()
        defer { lock.unlock() }
        unlimitedCalls += 1
    }

    func setUnlimitedPuzzles(_ puzzles: [PuzzleDefinition]) {
        lock.lock()
        defer { lock.unlock() }
        unlimitedPuzzles = puzzles
    }

    func setHasUnlimitedInProgress(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        hasUnlimitedInProgress = value
    }

    func dailyGenerationCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return dailyCalls
    }

    func unlimitedGenerationCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return unlimitedCalls
    }

    func loadCachedDailyPuzzle() -> PuzzleDefinition? {
        lock.lock()
        defer { lock.unlock() }
        return cachedDailyPuzzle
    }

    func loadNextDailyPuzzle() -> PuzzleDefinition {
        lock.lock()
        defer { lock.unlock() }
        return nextDailyPuzzle
    }

    func loadHasUnlimitedInProgress() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasUnlimitedInProgress
    }

    func dequeueUnlimitedPuzzle() -> PuzzleDefinition {
        lock.lock()
        defer { lock.unlock() }
        if unlimitedPuzzles.isEmpty {
            return makeWarmupPuzzle(seed: 999)
        }
        return unlimitedPuzzles.removeFirst()
    }
}

private func makeWarmupPuzzle(seed: UInt64, id: UUID = UUID()) -> PuzzleDefinition {
    let cells = [
        [
            CellDefinition(row: 0, col: 0, letter: "C"),
            CellDefinition(row: 0, col: 1, letter: "A"),
            CellDefinition(row: 0, col: 2, letter: "T"),
            CellDefinition(row: 0, col: 3, letter: nil),
            CellDefinition(row: 0, col: 4, letter: nil),
        ],
        Array(repeating: CellDefinition(row: 1, col: 0, letter: nil), count: 5),
        Array(repeating: CellDefinition(row: 2, col: 0, letter: nil), count: 5),
        Array(repeating: CellDefinition(row: 3, col: 0, letter: nil), count: 5),
        Array(repeating: CellDefinition(row: 4, col: 0, letter: nil), count: 5),
    ]

    return PuzzleDefinition(
        id: id,
        seed: seed,
        gridSize: .five,
        cells: cells.enumerated().map { row, rowCells in
            rowCells.enumerated().map { col, cell in
                CellDefinition(row: row, col: col, letter: cell.letter)
            }
        },
        words: [
            WordEntry(direction: .across, text: "CAT", clue: "Pet", startRow: 0, startCol: 0)
        ]
    )
}
