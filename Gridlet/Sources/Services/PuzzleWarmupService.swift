import Foundation

/// Preloads daily and unlimited puzzles so home screen taps can reuse work already in progress.
actor PuzzleWarmupService {
  static let shared = PuzzleWarmupService()
  static let backgroundUnlimitedTimeoutSeconds: TimeInterval = 30
  private static let crosswordPrewarmCooldownSeconds: TimeInterval = 60

  private let aiWordService: AIWordService
  private let persistence: PersistenceService
  private let dailyIdentifier: @Sendable () -> String
  private let cachedDailyLoader: @Sendable (String) -> PuzzleDefinition?
  private let dailyGenerator: @Sendable () async -> PuzzleDefinition
  private let unlimitedGenerator: @Sendable (TimeInterval, Set<String>) async -> PuzzleDefinition
  private let hasUnlimitedInProgress: @Sendable () -> Bool

  private var dailyTask: Task<PuzzleDefinition, Never>?
  private var dailyTaskIdentifier: String?
  private var unlimitedTask: Task<PuzzleDefinition, Never>?
  private var unlimitedTaskTimeoutSeconds: TimeInterval?
  private var lastCrosswordPrewarmAt: Date?

  init(
    aiWordService: AIWordService = .shared,
    persistence: PersistenceService = .shared,
    dailyIdentifier: @escaping @Sendable () -> String = {
      DailyPuzzleService().todayString
    },
    cachedDailyLoader: @escaping @Sendable (String) -> PuzzleDefinition? = { dateString in
      PersistenceService.shared.loadCachedDailyPuzzle(for: dateString)
    },
    dailyGenerator: @escaping @Sendable () async -> PuzzleDefinition = {
      await DailyPuzzleService().todaysPuzzle()
    },
    unlimitedGenerator: @escaping @Sendable (TimeInterval, Set<String>) async -> PuzzleDefinition =
      {
        timeoutSeconds, excludedWords in
        await PuzzleGeneratorService().generateWithAI(
          seed: UInt64.random(in: 0...UInt64.max),
          timeoutSeconds: timeoutSeconds,
          excludedWords: excludedWords
        )
      },
    hasUnlimitedInProgress: @escaping @Sendable () -> Bool = {
      PersistenceService.shared.loadUnlimitedGameState() != nil
        && PersistenceService.shared.loadUnlimitedPuzzle() != nil
    }
  ) {
    self.aiWordService = aiWordService
    self.persistence = persistence
    self.dailyIdentifier = dailyIdentifier
    self.cachedDailyLoader = cachedDailyLoader
    self.dailyGenerator = dailyGenerator
    self.unlimitedGenerator = unlimitedGenerator
    self.hasUnlimitedInProgress = hasUnlimitedInProgress
  }

  func startWarmup() {
    prewarmCrosswordGenerationIfNeeded()
    warmDailyPuzzleIfNeeded()
    warmUnlimitedPuzzleIfNeeded()
  }

  func dailyPuzzle() async -> PuzzleDefinition {
    let identifier = normalizeDailyTask()

    if let task = dailyTask {
      return await task.value
    }

    if let cachedPuzzle = cachedDailyLoader(identifier) {
      return cachedPuzzle
    }

    let task = Task { await dailyGenerator() }
    dailyTask = task
    dailyTaskIdentifier = identifier
    return await task.value
  }

  func unlimitedPuzzle() async -> PuzzleDefinition {
    if let task = unlimitedTask {
      let puzzle = await task.value
      unlimitedTask = nil
      unlimitedTaskTimeoutSeconds = nil
      warmUnlimitedPuzzleIfNeeded(forceBackground: true)
      return puzzle
    }

    let puzzle = await unlimitedGenerator(
      AIWordService.aiTimeoutSeconds,
      currentGameWords()
    )
    warmUnlimitedPuzzleIfNeeded(forceBackground: true)
    return puzzle
  }

  func warmNextUnlimitedPuzzle() {
    warmUnlimitedPuzzleIfNeeded(forceBackground: true)
  }

  func unlimitedWarmupTimeoutSeconds() -> TimeInterval {
    max(
      unlimitedTaskTimeoutSeconds ?? AIWordService.timeoutSeconds(for: .seven),
      AIWordService.timeoutSeconds(for: .seven)
    )
  }

  private func warmDailyPuzzleIfNeeded() {
    let identifier = normalizeDailyTask()

    guard dailyTask == nil else { return }
    guard cachedDailyLoader(identifier) == nil else { return }

    dailyTaskIdentifier = identifier
    dailyTask = Task { await dailyGenerator() }
  }

  private func warmUnlimitedPuzzleIfNeeded(forceBackground: Bool = false) {
    guard unlimitedTask == nil else { return }

    let timeoutSeconds =
      forceBackground
      ? Self.backgroundUnlimitedTimeoutSeconds
      : (hasUnlimitedInProgress()
        ? Self.backgroundUnlimitedTimeoutSeconds
        : AIWordService.aiTimeoutSeconds)
    unlimitedTaskTimeoutSeconds = timeoutSeconds
    let excludedWords = currentGameWords()
    unlimitedTask = Task { await unlimitedGenerator(timeoutSeconds, excludedWords) }
  }

  @discardableResult
  private func normalizeDailyTask() -> String {
    let identifier = dailyIdentifier()
    if dailyTaskIdentifier != identifier {
      dailyTaskIdentifier = nil
      dailyTask = nil
    }
    return identifier
  }

  private func prewarmCrosswordGenerationIfNeeded() {
    let now = Date()
    if let lastCrosswordPrewarmAt,
      now.timeIntervalSince(lastCrosswordPrewarmAt) < Self.crosswordPrewarmCooldownSeconds
    {
      return
    }

    lastCrosswordPrewarmAt = now
    aiWordService.prewarmCrosswordGeneration()
  }

  private func currentGameWords() -> Set<String> {
    var words = Set<String>()

    if let dailyState = persistence.loadDailyGameState(),
      let dailyPuzzle = persistence.loadCachedDailyPuzzle(for: PlayerStats.todayString()),
      dailyState.puzzleId == dailyPuzzle.id
    {
      words.formUnion(dailyPuzzle.words.map { $0.text.uppercased() })
    }

    if let unlimitedState = persistence.loadUnlimitedGameState(),
      let unlimitedPuzzle = persistence.loadUnlimitedPuzzle(),
      unlimitedState.puzzleId == unlimitedPuzzle.id
    {
      words.formUnion(unlimitedPuzzle.words.map { $0.text.uppercased() })
    }

    return words
  }
}
