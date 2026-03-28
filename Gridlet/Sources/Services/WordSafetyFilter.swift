import Foundation

// Keep this filter in sync with scripts/generate_wordlist.py.
enum WordSafetyFilter {
  private static let blockedWords: Set<String> = [
    // Offensive / unsafe
    "ass", "damn", "hell", "crap", "slut", "whore", "bitch", "dick", "cock",
    "shit", "fuck", "piss", "tit", "tits", "cum", "porn", "anus", "rape",
    "nazi", "aids", "die", "dies", "kill", "dead", "death", "drug", "drugs",
    "gun", "guns", "bomb", "slave", "satan", "sex", "sexy",
    // Function words / poor crossword fill
    "the", "and", "for", "are", "but", "not", "you", "all", "can", "had",
    "her", "was", "one", "our", "out", "has", "his", "how", "its", "may",
    "did", "get", "got", "let", "say", "she", "too", "use", "who", "why",
    "also", "been", "call", "each", "from", "have", "into", "just", "like",
    "long", "make", "many", "more", "most", "much", "must", "only", "over",
    "said", "same", "some", "such", "take", "than", "that", "them", "then",
    "they", "this", "very", "what", "when", "will", "with", "your",
    "about", "after", "being", "could", "every", "first", "found", "great",
    "these", "thing", "think", "those", "under", "where", "which", "while",
    "would", "their", "there", "other", "shall", "still", "since",
    // Proper nouns
    "france", "africa", "china", "india", "japan", "korea", "spain",
    "texas", "paris", "london", "york", "roman",
  ]

  // Only generate variants for safety-sensitive roots. Keeping this narrower than
  // blockedWords avoids over-blocking benign fill such as CANS from the exact
  // blocklisted function word CAN.
  private static let sensitiveRoots: Set<String> = [
    "ass", "damn", "hell", "crap", "slut", "whore", "bitch", "dick", "cock",
    "shit", "fuck", "piss", "tit", "cum", "porn", "anus", "rape",
    "nazi", "aids", "die", "kill", "dead", "death", "drug",
    "gun", "bomb", "slave", "satan", "sex",
  ]

  private static let irregularVariantsByRoot: [String: Set<String>] = [
    "rape": ["rapist", "rapists"],
    "die": ["dying"],
    "dead": ["deadly"],
    "kill": ["killer", "killers", "killing"],
    "sex": ["sexual", "sexist"],
  ]

  private static let sensitiveVariants: Set<String> = {
    var variants = Set<String>()
    for root in sensitiveRoots {
      variants.formUnion(variantForms(for: root))
      variants.formUnion(irregularVariantsByRoot[root] ?? [])
    }
    return variants
  }()

  static func isBlocked(_ word: String) -> Bool {
    let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }
    return blockedWords.contains(normalized) || sensitiveVariants.contains(normalized)
  }

  /// Generates a small, safety-focused set of common inflections for blocked roots.
  /// Handles regular -s/-es plurals, -ed/-ing verb forms, and common agent-noun
  /// forms like RAPE -> RAPER. Roots ending in -ie switch to -ying (DIE -> DYING).
  private static func variantForms(for root: String) -> Set<String> {
    var forms: Set<String> = [root]
    let endsWithIE = root.hasSuffix("ie")

    if root.hasSuffix("e") {
      let stem = String(root.dropLast())
      forms.insert(root + "d")
      let progressive: String
      if endsWithIE {
        progressive = String(root.dropLast(2)) + "ying"
      } else {
        progressive = stem + "ing"
      }
      forms.insert(progressive)
      forms.insert(stem + "er")
      forms.insert(stem + "ers")
      forms.insert(root + "s")
    } else {
      forms.insert(pluralForm(for: root))
      forms.insert(root + "ed")
      forms.insert(root + "ing")
      forms.insert(root + "er")
      forms.insert(root + "ers")
    }

    return forms
  }

  /// Forms plurals for roots that need runtime safety matching. Appending "zes" to
  /// a single-z root naturally yields the doubled-z spelling (QUIZ -> QUIZZES).
  private static func pluralForm(for root: String) -> String {
    if root.hasSuffix("z") && !root.hasSuffix("zz") {
      return root + "zes"
    }
    return needsESPlural(root) ? root + "es" : root + "s"
  }

  private static func needsESPlural(_ root: String) -> Bool {
    let esSuffixes = ["s", "x", "z", "sh", "ch"]
    return esSuffixes.contains { root.hasSuffix($0) }
  }
}
