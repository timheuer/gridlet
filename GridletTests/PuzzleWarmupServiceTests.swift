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
      unlimitedGenerator: { timeoutSeconds, excludedWords in
        state.recordUnlimitedGeneration(
          timeoutSeconds: timeoutSeconds,
          excludedWords: excludedWords
        )
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
      unlimitedGenerator: { timeoutSeconds, excludedWords in
        state.recordUnlimitedGeneration(
          timeoutSeconds: timeoutSeconds,
          excludedWords: excludedWords
        )
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
    #expect(
      state.unlimitedGenerationTimeouts() == [
        AIWordService.aiTimeoutSeconds,
        PuzzleWarmupService.backgroundUnlimitedTimeoutSeconds,
      ])
  }

  @Test("Unlimited warmup generates with the background timeout when one is already in progress")
  func unlimitedWarmupGeneratesWithBackgroundTimeoutWhenInProgressExists() async throws {
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
      unlimitedGenerator: { timeoutSeconds, excludedWords in
        state.recordUnlimitedGeneration(
          timeoutSeconds: timeoutSeconds,
          excludedWords: excludedWords
        )
        return state.dequeueUnlimitedPuzzle()
      },
      hasUnlimitedInProgress: { state.loadHasUnlimitedInProgress() }
    )

    await service.startWarmup()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(state.unlimitedGenerationCount() == 1)
    #expect(
      state.unlimitedGenerationTimeouts() == [PuzzleWarmupService.backgroundUnlimitedTimeoutSeconds]
    )
  }

  @Test(
    "Unlimited puzzle generation warms the following puzzle in the background after serving the current puzzle"
  )
  func unlimitedPuzzleWarmsNextPuzzleAfterServingCurrentPuzzle() async {
    let state = WarmupTestState()
    let currentPuzzle = makeWarmupPuzzle(
      seed: 41,
      id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
    )
    let nextPuzzle = makeWarmupPuzzle(
      seed: 42,
      id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
    )
    state.setUnlimitedPuzzles([currentPuzzle, nextPuzzle])

    let service = PuzzleWarmupService(
      dailyIdentifier: { "2026-03-25" },
      cachedDailyLoader: { _ in state.loadCachedDailyPuzzle() },
      dailyGenerator: {
        state.recordDailyGeneration()
        return state.loadNextDailyPuzzle()
      },
      unlimitedGenerator: { timeoutSeconds, excludedWords in
        state.recordUnlimitedGeneration(
          timeoutSeconds: timeoutSeconds,
          excludedWords: excludedWords
        )
        try? await Task.sleep(for: .milliseconds(20))
        return state.dequeueUnlimitedPuzzle()
      },
      hasUnlimitedInProgress: { state.loadHasUnlimitedInProgress() }
    )

    let servedPuzzle = await service.unlimitedPuzzle()
    try? await Task.sleep(for: .milliseconds(40))

    #expect(servedPuzzle.id == currentPuzzle.id)
    #expect(state.unlimitedGenerationCount() == 2)
    #expect(
      state.unlimitedGenerationTimeouts() == [
        AIWordService.aiTimeoutSeconds,
        PuzzleWarmupService.backgroundUnlimitedTimeoutSeconds,
      ])
  }

  @Test("Unlimited warmup excludes words from active puzzles")
  func unlimitedWarmupExcludesActivePuzzleWords() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let persistence = PersistenceService(documentsURL: tempDirectory)
    let today = PlayerStats.todayString()

    let dailyPuzzle = makeWarmupPuzzle(
      seed: 61, id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!, word: "BINGO",
      clue: "Game with numbered cards")
    let unlimitedPuzzle = makeWarmupPuzzle(
      seed: 62, id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!, word: "HOME",
      clue: "A place to live")

    try persistence.cacheDailyPuzzle(dailyPuzzle, for: today)
    try persistence.saveDailyGameState(
      GameState(puzzleId: dailyPuzzle.id, isDaily: true, gridSize: .five))
    try persistence.saveUnlimitedPuzzle(unlimitedPuzzle)
    try persistence.saveUnlimitedGameState(
      GameState(puzzleId: unlimitedPuzzle.id, isDaily: false, gridSize: .five))

    let state = WarmupTestState()
    state.setHasUnlimitedInProgress(true)
    state.setUnlimitedPuzzles([makeWarmupPuzzle(seed: 63)])

    let service = PuzzleWarmupService(
      persistence: persistence,
      dailyIdentifier: { today },
      cachedDailyLoader: { _ in state.loadCachedDailyPuzzle() },
      dailyGenerator: {
        state.recordDailyGeneration()
        return state.loadNextDailyPuzzle()
      },
      unlimitedGenerator: { timeoutSeconds, excludedWords in
        state.recordUnlimitedGeneration(
          timeoutSeconds: timeoutSeconds,
          excludedWords: excludedWords
        )
        return state.dequeueUnlimitedPuzzle()
      },
      hasUnlimitedInProgress: { state.loadHasUnlimitedInProgress() }
    )

    await service.startWarmup()
    try? await Task.sleep(for: .milliseconds(20))

    let excludedWords = state.unlimitedExcludedWords()
    #expect(excludedWords.contains("BINGO"))
    #expect(excludedWords.contains("HOME"))
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
  private var unlimitedTimeouts: [TimeInterval] = []
  private var unlimitedExcludedWordSets: [Set<String>] = []

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

  func recordUnlimitedGeneration(timeoutSeconds: TimeInterval, excludedWords: Set<String>) {
    lock.lock()
    defer { lock.unlock() }
    unlimitedCalls += 1
    unlimitedTimeouts.append(timeoutSeconds)
    unlimitedExcludedWordSets.append(excludedWords)
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

  func unlimitedGenerationTimeouts() -> [TimeInterval] {
    lock.lock()
    defer { lock.unlock() }
    return unlimitedTimeouts
  }

  func unlimitedExcludedWords() -> Set<String> {
    lock.lock()
    defer { lock.unlock() }
    return Set(unlimitedExcludedWordSets.flatMap { $0 })
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

private func makeWarmupPuzzle(
  seed: UInt64,
  id: UUID = UUID(),
  word: String = "CAT",
  clue: String = "Pet"
) -> PuzzleDefinition {
  let uppercasedWord = word.uppercased()
  let letters = Array(uppercasedWord)
  precondition(letters.count <= 5, "Warmup test puzzles support words up to 5 letters")

  let firstRow = (0..<5).map { col in
    let letter: Character? = col < letters.count ? letters[col] : nil
    return CellDefinition(row: 0, col: col, letter: letter)
  }

  let cells = [
    [
      firstRow[0],
      firstRow[1],
      firstRow[2],
      firstRow[3],
      firstRow[4],
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
      WordEntry(direction: .across, text: uppercasedWord, clue: clue, startRow: 0, startCol: 0)
    ]
  )
}
