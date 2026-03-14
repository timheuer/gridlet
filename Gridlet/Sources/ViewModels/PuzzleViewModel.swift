import Observation
import SwiftUI

/// Central view model for puzzle gameplay — owns the game state and puzzle definition.
@Observable
final class PuzzleViewModel {
  let puzzle: PuzzleDefinition
  var gameState: GameState
  var devMode = false
  var showSolution = false

  private let persistence = PersistenceService.shared

  /// The clue text for the currently active word.
  var activeClue: String {
    guard let cell = gameState.selectedCell,
      let word = puzzle.word(at: cell.row, col: cell.col, direction: gameState.activeDirection)
    else {
      return ""
    }
    let number = wordNumber(for: word)
    let arrow = word.direction == .across ? "→" : "↓"
    return "\(number)\(arrow) \(word.clue)"
  }

  var activeClueAccessibilityLabel: String {
    guard let word = activeWord else {
      return "Current clue"
    }
    return "Current clue, \(wordNumber(for: word)) \(directionName(word.direction))"
  }

  var activeClueAccessibilityValue: String {
    guard let word = activeWord else {
      return "Tap a white cell to hear its clue."
    }
    return word.clue
  }

  var activeClueAccessibilityHint: String {
    guard let cell = gameState.selectedCell else {
      return "Select a white cell in the grid to choose a clue."
    }

    if let alternate = alternateDirection(at: cell.row, col: cell.col) {
      return "Double-tap to switch to \(directionName(alternate))."
    }

    return "This cell only has a \(directionName(gameState.activeDirection)) word."
  }

  /// Whether the puzzle is completed.
  var isCompleted: Bool { gameState.isCompleted }

  /// Set to `true` briefly when every cell is filled but the solution is wrong.
  var showIncorrectMessage = false

  init(puzzle: PuzzleDefinition, gameState: GameState) {
    self.puzzle = puzzle
    self.gameState = gameState
  }

  // MARK: - Cell Selection

  func selectCell(row: Int, col: Int) {
    guard !puzzle.isBlackCell(row: row, col: col) else { return }
    guard !gameState.isCompleted else { return }

    let tapped = CellPosition(row: row, col: col)

    if gameState.selectedCell == tapped {
      // Tap same cell → toggle direction
      let toggled = gameState.activeDirection.toggled
      // Only toggle if there's a word in that direction at this cell
      if puzzle.word(at: row, col: col, direction: toggled) != nil {
        gameState.activeDirection = toggled
      }
    } else {
      gameState.selectedCell = tapped

      // If no word exists in current direction at this cell, switch
      if puzzle.word(at: row, col: col, direction: gameState.activeDirection) == nil {
        gameState.activeDirection = gameState.activeDirection.toggled
      }
    }
  }

  // MARK: - Letter Input

  func enterLetter(_ letter: Character) {
    guard let cell = gameState.selectedCell, !gameState.isCompleted else { return }
    let row = cell.row
    let col = cell.col
    guard !puzzle.isBlackCell(row: row, col: col) else { return }

    // Track whether we're filling the last empty cell (first-time completion of word)
    let wasEmpty = gameState.playerGrid[row][col] == nil
    let emptyCellsBefore = activeWordCells.count(where: { gameState.playerGrid[$0.row][$0.col] == nil })

    gameState.playerGrid[row][col] = letter

    // Clear any red overlay on this cell since the letter changed
    gameState.checkedWrongCells.remove(cell)

    // Auto-advance: jump to next word only if this keystroke just completed the word
    let wordJustCompleted = wasEmpty && emptyCellsBefore == 1
    advanceToNextCell(wordJustCompleted: wordJustCompleted)

    checkCompletion()
    save()
  }

  func backspace() {
    guard let cell = gameState.selectedCell, !gameState.isCompleted else { return }
    let row = cell.row
    let col = cell.col

    if gameState.playerGrid[row][col] != nil {
      // Clear current cell
      gameState.playerGrid[row][col] = nil
      gameState.checkedWrongCells.remove(cell)
    } else {
      // Move back one cell in the active word
      moveToPreviousCell()
      if let newCell = gameState.selectedCell {
        gameState.playerGrid[newCell.row][newCell.col] = nil
        gameState.checkedWrongCells.remove(newCell)
      }
    }
    save()
  }

  // MARK: - Check Function

  /// Check the currently active word and mark wrong letters with red overlay.
  func checkActiveWord() {
    guard let cell = gameState.selectedCell,
      let word = puzzle.word(at: cell.row, col: cell.col, direction: gameState.activeDirection)
    else { return }

    gameState.checksUsed += 1

    for pos in word.cells {
      let playerLetter = gameState.playerGrid[pos.row][pos.col]
      let solutionLetter = puzzle.solutionLetter(row: pos.row, col: pos.col)

      let cellPos = CellPosition(row: pos.row, col: pos.col)

      if let player = playerLetter, let solution = solutionLetter {
        if player != solution {
          gameState.checkedWrongCells.insert(cellPos)
        } else {
          gameState.checkedWrongCells.remove(cellPos)
        }
      }
    }
    save()
  }

  // MARK: - Navigation Helpers

  /// The cells belonging to the currently active word, in order.
  var activeWordCells: [CellPosition] {
    guard let cell = gameState.selectedCell,
      let word = puzzle.word(at: cell.row, col: cell.col, direction: gameState.activeDirection)
    else {
      return []
    }
    return word.cells.map { CellPosition(row: $0.row, col: $0.col) }
  }

  func cellAccessibilityLabel(row: Int, col: Int) -> String {
    if puzzle.isBlackCell(row: row, col: col) {
      return "Black cell, row \(row + 1), column \(col + 1)"
    }

    var parts: [String] = []

    if let word = preferredWord(at: row, col: col) {
      parts.append("\(wordNumber(for: word)) \(directionName(word.direction))")
    }

    parts.append("row \(row + 1), column \(col + 1)")

    if let number = cellNumber(row: row, col: col) {
      parts.append("number \(number)")
    }

    return parts.joined(separator: ", ")
  }

  func cellAccessibilityValue(row: Int, col: Int) -> String? {
    guard !puzzle.isBlackCell(row: row, col: col) else { return nil }

    let cell = CellPosition(row: row, col: col)
    var parts: [String] = []

    if let letter = gameState.playerGrid[row][col] {
      parts.append("Letter \(String(letter))")
    } else {
      parts.append("Empty")
    }

    if gameState.checkedWrongCells.contains(cell) {
      parts.append("Marked incorrect")
    }

    if gameState.selectedCell == cell {
      parts.append("Selected")
    }

    return parts.joined(separator: ", ")
  }

  func cellAccessibilityHint(row: Int, col: Int) -> String? {
    guard !puzzle.isBlackCell(row: row, col: col) else { return nil }

    let cell = CellPosition(row: row, col: col)
    var parts: [String] = []

    if let word = preferredWord(at: row, col: col) {
      parts.append("Clue: \(word.clue).")
    }

    if gameState.selectedCell == cell {
      if let alternate = alternateDirection(at: row, col: col) {
        parts.append("Double-tap to switch to \(directionName(alternate)).")
      } else {
        parts.append("Double-tap to keep editing this word.")
      }
    } else if let word = preferredWord(at: row, col: col) {
      parts.append("Double-tap to select \(directionName(word.direction)).")
    }

    return parts.joined(separator: " ")
  }

  /// Numbered labels for word starts (standard crossword numbering).
  func cellNumber(row: Int, col: Int) -> Int? {
    let wordsHere = puzzle.words.filter { $0.startRow == row && $0.startCol == col }
    guard !wordsHere.isEmpty else { return nil }
    return wordNumber(for: wordsHere[0])
  }

  // MARK: - Timer

  func addElapsedTime(_ seconds: TimeInterval) {
    guard !gameState.isCompleted else { return }
    gameState.elapsedSeconds += seconds
  }

  // MARK: - Word Navigation

  /// All words sorted in standard crossword order (by number, across before down).
  private var sortedWords: [WordEntry] {
    puzzle.words.sorted { a, b in
      let na = wordNumber(for: a)
      let nb = wordNumber(for: b)
      if na != nb { return na < nb }
      return a.direction == .across && b.direction == .down
    }
  }

  /// Move to the next word in the puzzle.
  func selectNextWord() {
    guard !gameState.isCompleted else { return }
    let words = sortedWords
    guard !words.isEmpty else { return }

    let nextWord: WordEntry
    if let cell = gameState.selectedCell,
      let current = puzzle.word(at: cell.row, col: cell.col, direction: gameState.activeDirection),
      let idx = words.firstIndex(where: {
        $0.text == current.text && $0.direction == current.direction
      })
    {
      nextWord = words[(idx + 1) % words.count]
    } else {
      nextWord = words[0]
    }

    gameState.activeDirection = nextWord.direction
    gameState.selectedCell = CellPosition(row: nextWord.startRow, col: nextWord.startCol)
    focusFirstEmptyCell()
  }

  /// Move to the previous word in the puzzle.
  func selectPreviousWord() {
    guard !gameState.isCompleted else { return }
    let words = sortedWords
    guard !words.isEmpty else { return }

    let prevWord: WordEntry
    if let cell = gameState.selectedCell,
      let current = puzzle.word(at: cell.row, col: cell.col, direction: gameState.activeDirection),
      let idx = words.firstIndex(where: {
        $0.text == current.text && $0.direction == current.direction
      })
    {
      prevWord = words[(idx - 1 + words.count) % words.count]
    } else {
      prevWord = words[0]
    }

    gameState.activeDirection = prevWord.direction
    gameState.selectedCell = CellPosition(row: prevWord.startRow, col: prevWord.startCol)
    focusFirstEmptyCell()
  }

  // MARK: - Private

  private func wordNumber(for word: WordEntry) -> Int {
    // Collect all word-start positions, sort by row then col, and assign numbers
    var starts: Set<String> = []
    var orderedStarts: [(row: Int, col: Int)] = []
    for w in puzzle.words {
      let key = "\(w.startRow),\(w.startCol)"
      if !starts.contains(key) {
        starts.insert(key)
        orderedStarts.append((w.startRow, w.startCol))
      }
    }
    orderedStarts.sort { $0.row != $1.row ? $0.row < $1.row : $0.col < $1.col }

    let key = "\(word.startRow),\(word.startCol)"
    if let index = orderedStarts.firstIndex(where: { "\($0.row),\($0.col)" == key }) {
      return index + 1
    }
    return 0
  }

  private var activeWord: WordEntry? {
    guard let cell = gameState.selectedCell else { return nil }
    return puzzle.word(at: cell.row, col: cell.col, direction: gameState.activeDirection)
  }

  private func preferredWord(at row: Int, col: Int) -> WordEntry? {
    let acrossWord = puzzle.word(at: row, col: col, direction: .across)
    let downWord = puzzle.word(at: row, col: col, direction: .down)

    switch (acrossWord, downWord) {
    case (let across?, let down?):
      return gameState.activeDirection == .across ? across : down
    case (let across?, nil):
      return across
    case (nil, let down?):
      return down
    case (nil, nil):
      return nil
    }
  }

  private func alternateDirection(at row: Int, col: Int) -> WordDirection? {
    let acrossWord = puzzle.word(at: row, col: col, direction: .across)
    let downWord = puzzle.word(at: row, col: col, direction: .down)

    if acrossWord != nil && downWord != nil {
      return gameState.activeDirection.toggled
    }

    return nil
  }

  private func directionName(_ direction: WordDirection) -> String {
    switch direction {
    case .across:
      return "across"
    case .down:
      return "down"
    }
  }

  private func advanceToNextCell(wordJustCompleted: Bool = false) {
    guard let cell = gameState.selectedCell else { return }
    let wordCells = activeWordCells
    guard let currentIndex = wordCells.firstIndex(of: cell) else { return }

    // First, try to find an empty cell in the rest of this word
    for i in (currentIndex + 1)..<wordCells.count {
      let pos = wordCells[i]
      if gameState.playerGrid[pos.row][pos.col] == nil {
        gameState.selectedCell = pos
        return
      }
    }

    // No empty cells ahead — if the word just became full (first-time completion),
    // auto-advance to the next word. Otherwise stay in the word so the player
    // can continue editing filled cells.
    if wordJustCompleted {
      selectNextWord()
    } else if currentIndex + 1 < wordCells.count {
      // Move to the next cell in the word even though it's filled
      gameState.selectedCell = wordCells[currentIndex + 1]
    }
  }

  /// Whether every cell in the active word has a letter.
  private var isActiveWordFull: Bool {
    activeWordCells.allSatisfy { gameState.playerGrid[$0.row][$0.col] != nil }
  }

  private func moveToPreviousCell() {
    guard let cell = gameState.selectedCell else { return }
    let wordCells = activeWordCells
    guard let currentIndex = wordCells.firstIndex(of: cell), currentIndex > 0 else { return }
    gameState.selectedCell = wordCells[currentIndex - 1]
  }

  /// Move focus to the first empty cell in the active word, if any.
  private func focusFirstEmptyCell() {
    let wordCells = activeWordCells
    for pos in wordCells {
      if gameState.playerGrid[pos.row][pos.col] == nil {
        gameState.selectedCell = pos
        return
      }
    }
    // All cells filled — stay on the word start (already set by caller)
  }

  /// Whether every non-black cell has a letter (regardless of correctness).
  private var isBoardFull: Bool {
    let dim = puzzle.gridSize.dimension
    for row in 0..<dim {
      for col in 0..<dim {
        if puzzle.solutionLetter(row: row, col: col) != nil {
          if gameState.playerGrid[row][col] == nil { return false }
        }
      }
    }
    return true
  }

  private func checkCompletion() {
    let dim = puzzle.gridSize.dimension
    for row in 0..<dim {
      for col in 0..<dim {
        if let solution = puzzle.solutionLetter(row: row, col: col) {
          guard gameState.playerGrid[row][col] == solution else {
            // Not all correct — but if every cell is filled, alert the user
            if isBoardFull {
              showIncorrectMessage = true
            }
            return
          }
        }
      }
    }
    // All correct!
    gameState.isCompleted = true
    gameState.completedAt = Date()
  }

  private func save() {
    do {
      if gameState.isDaily {
        try persistence.saveDailyGameState(gameState)
      } else {
        try persistence.saveUnlimitedGameState(gameState)
      }
    } catch {
      // Silent fail — persistence is best-effort
    }
  }
}
