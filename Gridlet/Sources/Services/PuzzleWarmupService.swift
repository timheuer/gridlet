import Foundation

/// Preloads daily and unlimited puzzles so home screen taps can reuse work already in progress.
actor PuzzleWarmupService {
    static let shared = PuzzleWarmupService()

    private let dailyIdentifier: @Sendable () -> String
    private let cachedDailyLoader: @Sendable (String) -> PuzzleDefinition?
    private let dailyGenerator: @Sendable () async -> PuzzleDefinition
    private let unlimitedGenerator: @Sendable () async -> PuzzleDefinition
    private let hasUnlimitedInProgress: @Sendable () -> Bool

    private var dailyTask: Task<PuzzleDefinition, Never>?
    private var dailyTaskIdentifier: String?
    private var unlimitedTask: Task<PuzzleDefinition, Never>?

    init(
        dailyIdentifier: @escaping @Sendable () -> String = {
            DailyPuzzleService().todayString
        },
        cachedDailyLoader: @escaping @Sendable (String) -> PuzzleDefinition? = { dateString in
            PersistenceService.shared.loadCachedDailyPuzzle(for: dateString)
        },
        dailyGenerator: @escaping @Sendable () async -> PuzzleDefinition = {
            await DailyPuzzleService().todaysPuzzle()
        },
        unlimitedGenerator: @escaping @Sendable () async -> PuzzleDefinition = {
            await PuzzleGeneratorService().generateWithAI(seed: UInt64.random(in: 0...UInt64.max))
        },
        hasUnlimitedInProgress: @escaping @Sendable () -> Bool = {
            PersistenceService.shared.loadUnlimitedGameState() != nil
                && PersistenceService.shared.loadUnlimitedPuzzle() != nil
        }
    ) {
        self.dailyIdentifier = dailyIdentifier
        self.cachedDailyLoader = cachedDailyLoader
        self.dailyGenerator = dailyGenerator
        self.unlimitedGenerator = unlimitedGenerator
        self.hasUnlimitedInProgress = hasUnlimitedInProgress
    }

    func startWarmup() {
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
            return puzzle
        }

        return await unlimitedGenerator()
    }

    private func warmDailyPuzzleIfNeeded() {
        let identifier = normalizeDailyTask()

        guard dailyTask == nil else { return }
        guard cachedDailyLoader(identifier) == nil else { return }

        dailyTaskIdentifier = identifier
        dailyTask = Task { await dailyGenerator() }
    }

    private func warmUnlimitedPuzzleIfNeeded() {
        guard !hasUnlimitedInProgress() else { return }
        guard unlimitedTask == nil else { return }

        unlimitedTask = Task { await unlimitedGenerator() }
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
}
