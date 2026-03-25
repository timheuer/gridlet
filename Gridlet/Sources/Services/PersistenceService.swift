import Foundation

/// Persists game state, puzzle cache, and player stats to the app's documents directory as JSON files.
final class PersistenceService: @unchecked Sendable {
  static let shared = PersistenceService()

  private let documentsURL: URL

  private var dailyGameStateURL: URL {
    documentsURL.appendingPathComponent("daily_game_state.json")
  }
  private var unlimitedGameStateURL: URL {
    documentsURL.appendingPathComponent("unlimited_game_state.json")
  }
  private var playerStatsURL: URL { documentsURL.appendingPathComponent("player_stats.json") }
  private var dailyCacheDirectory: URL { documentsURL.appendingPathComponent("daily_cache") }
  private var solvedWordsURL: URL { documentsURL.appendingPathComponent("solved_words.json") }

  private let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = .prettyPrinted
    return e
  }()

  private let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }()

  init(
    documentsURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  ) {
    self.documentsURL = documentsURL
    try? FileManager.default.createDirectory(
      at: dailyCacheDirectory, withIntermediateDirectories: true)
  }

  // MARK: - Game State

  func saveDailyGameState(_ state: GameState) throws {
    let data = try encoder.encode(state)
    try data.write(to: dailyGameStateURL)
  }

  func loadDailyGameState() -> GameState? {
    guard let data = try? Data(contentsOf: dailyGameStateURL) else { return nil }
    return try? decoder.decode(GameState.self, from: data)
  }

  func clearDailyGameState() {
    try? FileManager.default.removeItem(at: dailyGameStateURL)
  }

  func saveUnlimitedGameState(_ state: GameState) throws {
    let data = try encoder.encode(state)
    try data.write(to: unlimitedGameStateURL)
  }

  func loadUnlimitedGameState() -> GameState? {
    guard let data = try? Data(contentsOf: unlimitedGameStateURL) else { return nil }
    return try? decoder.decode(GameState.self, from: data)
  }

  func clearUnlimitedGameState() {
    try? FileManager.default.removeItem(at: unlimitedGameStateURL)
  }

  // MARK: - Unlimited Puzzle Cache (for resume)

  private var unlimitedPuzzleURL: URL {
    documentsURL.appendingPathComponent("unlimited_puzzle.json")
  }

  func saveUnlimitedPuzzle(_ puzzle: PuzzleDefinition) throws {
    let data = try encoder.encode(puzzle)
    try data.write(to: unlimitedPuzzleURL)
  }

  func loadUnlimitedPuzzle() -> PuzzleDefinition? {
    guard let data = try? Data(contentsOf: unlimitedPuzzleURL) else { return nil }
    return try? decoder.decode(PuzzleDefinition.self, from: data)
  }

  func clearUnlimitedPuzzle() {
    try? FileManager.default.removeItem(at: unlimitedPuzzleURL)
  }

  // MARK: - Player Stats

  func savePlayerStats(_ stats: PlayerStats) throws {
    let data = try encoder.encode(stats)
    try data.write(to: playerStatsURL)
  }

  func loadPlayerStats() -> PlayerStats {
    guard let data = try? Data(contentsOf: playerStatsURL),
      let stats = try? decoder.decode(PlayerStats.self, from: data)
    else {
      return PlayerStats()
    }
    return stats
  }

  // MARK: - Solved Word History

  func loadSolvedWords() -> [String] {
    guard let data = try? Data(contentsOf: solvedWordsURL),
      let words = try? decoder.decode([String].self, from: data)
    else {
      return []
    }

    var seen = Set<String>()
    return words.compactMap { word in
      let normalized = word.uppercased()
      guard seen.insert(normalized).inserted else { return nil }
      return normalized
    }
  }

  func saveSolvedWords(_ words: [String]) throws {
    var seen = Set<String>()
    let normalized = words.compactMap { word -> String? in
      let uppercased = word.uppercased()
      guard seen.insert(uppercased).inserted else { return nil }
      return uppercased
    }

    let data = try encoder.encode(normalized)
    try data.write(to: solvedWordsURL)
  }

  func appendSolvedWords(_ words: [String]) throws {
    try saveSolvedWords(loadSolvedWords() + words)
  }

  func clearSolvedWords() {
    try? FileManager.default.removeItem(at: solvedWordsURL)
  }

  // MARK: - Daily Puzzle Cache

  func cacheDailyPuzzle(_ puzzle: PuzzleDefinition, for dateString: String) throws {
    let url = dailyCacheDirectory.appendingPathComponent("\(dateString).json")
    let data = try encoder.encode(puzzle)
    try data.write(to: url)
  }

  func loadCachedDailyPuzzle(for dateString: String) -> PuzzleDefinition? {
    let url = dailyCacheDirectory.appendingPathComponent("\(dateString).json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? decoder.decode(PuzzleDefinition.self, from: data)
  }

  /// Remove cached puzzles older than the given number of days.
  func pruneOldDailyCache(keepDays: Int = 7) {
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: dailyCacheDirectory, includingPropertiesForKeys: nil)
    else { return }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date())!

    for file in files {
      let name = file.deletingPathExtension().lastPathComponent
      if let date = formatter.date(from: name), date < cutoff {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }
}
