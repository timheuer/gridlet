import Foundation

/// A word-clue pair from the bundled dictionary.
struct WordClue: Codable, Sendable {
    let word: String
    let clue: String
}

/// Loads and provides access to the bundled word/clue dictionary.
final class WordListService: Sendable {
    static let shared = WordListService()

    let entries: [WordClue]

    /// Index from word (uppercased) to clue for fast lookup.
    let cluesByWord: [String: String]

    private init() {
        guard let url = Bundle.main.url(forResource: "wordlist", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([WordClue].self, from: data) else {
            entries = []
            cluesByWord = [:]
            return
        }
        entries = decoded
        var lookup: [String: String] = [:]
        for entry in decoded {
            lookup[entry.word.uppercased()] = entry.clue
        }
        cluesByWord = lookup
    }

    /// Returns all words that fit within the given maximum length.
    func words(maxLength: Int) -> [String] {
        entries
            .map { $0.word.uppercased() }
            .filter { $0.count >= 3 && $0.count <= maxLength && !WordSafetyFilter.isBlocked($0) }
    }

    /// Look up the clue for a word.
    func clue(for word: String) -> String {
        cluesByWord[word.uppercased()] ?? "No clue available"
    }
}
