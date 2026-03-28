#!/usr/bin/env python3
"""
generate_wordlist.py — Generates wordlist.json for Gridlet from Open English WordNet + wordfreq.

Sources:
  - Open English WordNet (ewn:2020) — provides word definitions (clues)
  - wordfreq — filters to common, well-known English words

Usage:
  pip install wordfreq wn
  python3 scripts/generate_wordlist.py

Output:
  Gridlet/Resources/wordlist.json
"""

import json
import random
import re
import sys
from pathlib import Path
from typing import Optional

import wn
from wordfreq import word_frequency, top_n_list

# ── Configuration ──────────────────────────────────────────────────────────────

MIN_LENGTH = 3
MAX_LENGTH = 7
TARGET_COUNT = 7500      # aim for this many word-clue pairs
MAX_CLUE_WORDS = 8       # max words in a clue (truncated at natural boundaries)
LANGUAGE = "en"
FREQ_LIST = "best"       # wordfreq's best-quality list

# Words to exclude (offensive, function words, etc.)
BLOCKLIST = {
    # Offensive
    "ass", "damn", "hell", "crap", "slut", "whore", "bitch", "dick", "cock",
    "shit", "fuck", "piss", "tit", "tits", "cum", "porn", "anus", "rape",
    "nazi", "aids", "die", "dies", "kill", "dead", "death", "drug", "drugs",
    "gun", "guns", "bomb", "slave", "satan", "sex", "sexy",
    # Function words / pronouns / articles (poor crossword entries)
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
    # Proper nouns that sneak through wordfreq
    "france", "africa", "china", "india", "japan", "korea", "spain",
    "texas", "paris", "london", "york", "roman",
}

SENSITIVE_VARIANT_ROOTS = {
    "ass", "damn", "hell", "crap", "slut", "whore", "bitch", "dick", "cock",
    "shit", "fuck", "piss", "tit", "cum", "porn", "anus", "rape",
    "nazi", "aids", "die", "kill", "dead", "death", "drug",
    "gun", "bomb", "slave", "satan", "sex",
}

IRREGULAR_VARIANTS = {
    "rape": {"rapist", "rapists"},
    "die": {"dying"},
    "dead": {"deadly"},
    "kill": {"killer", "killers", "killing"},
    "sex": {"sexual", "sexist"},
}

# Keywords in WordNet definitions that indicate proper nouns / named entities
PROPER_NOUN_INDICATORS = [
    "capital of", "city in", "city on", "town in", "town on",
    "country in", "country on", "state in", "province in", "region in",
    "river in", "river of", "lake in", "mountain in", "island in", "island of",
    "peninsula in", "gulf of", "strait of", "bay of", "sea of",
    "king of", "queen of", "prince of", "princess of", "duke of", "emperor of",
    "president of", "prime minister",
    "united states", "american", "british", "english", "french", "german",
    "italian", "spanish", "russian", "chinese", "japanese", "canadian",
    "australian", "african", "european", "asian", "indian", "mexican",
    "brazilian", "dutch", "swedish", "norwegian", "danish", "finnish",
    "portuguese", "swiss", "austrian", "polish", "irish", "scottish", "welsh",
    "greek god", "roman god", "norse god",
    "in judeo", "old testament", "new testament", "biblical",
    "mythology", "mythological",
    "author of", "author who", "poet who", "painter who", "composer who",
    "novelist who", "playwright who", "philosopher who", "scientist who",
    "mathematician who", "physicist who", "chemist who", "biologist who",
    "astronomer who", "inventor who", "explorer who",
    "surname", "family name", "first name", "given name",
]

# ── Helpers ────────────────────────────────────────────────────────────────────

# Keep these blocked-word rules in sync with Gridlet/Sources/Services/WordSafetyFilter.swift.
def is_valid_word(word: str, wordnet_en=None) -> bool:
    """Check if a word is suitable for crossword use."""
    w = word.lower()
    if len(w) < MIN_LENGTH or len(w) > MAX_LENGTH:
        return False
    if not re.match(r'^[a-z]+$', w):
        return False  # no hyphens, spaces, apostrophes
    if is_blocked_or_variant(w):
        return False
    # If WordNet is available, reject words that ONLY have proper noun senses
    if wordnet_en:
        senses = wordnet_en.senses(w)
        if senses:
            all_proper = all(
                is_proper_noun_definition(s.synset().definition() or '')
                for s in senses
            )
            if all_proper:
                return False
    return True


def is_blocked_or_variant(word: str) -> bool:
    w = word.lower()
    if w in BLOCKLIST:
        return True

    for root in SENSITIVE_VARIANT_ROOTS:
        if w in variant_forms(root) or w in IRREGULAR_VARIANTS.get(root, set()):
            return True

    return False


def variant_forms(root: str) -> set[str]:
    forms = {root}
    ends_with_ie = root.endswith('ie')

    if root.endswith('e'):
        stem = root[:-1]
        if ends_with_ie:
            progressive = root[:-2] + 'ying'
        else:
            progressive = stem + 'ing'
        forms.update({
            root + 'd',
            progressive,
            stem + 'er',
            stem + 'ers',
            root + 's',
        })
    else:
        plural = root + 'es' if needs_es_plural(root) else root + 's'
        forms.update({
            plural,
            root + 'ed',
            root + 'ing',
            root + 'er',
            root + 'ers',
        })

    return forms


def needs_es_plural(root: str) -> bool:
    return root.endswith(('s', 'x', 'z', 'sh', 'ch'))


def clean_definition(definition: str) -> str:
    """Trim a WordNet definition into a concise crossword-style clue."""
    # Remove parenthetical remarks
    clue = re.sub(r'\([^)]*\)', '', definition)
    # Remove quotes
    clue = re.sub(r'["\']', '', clue)
    # Remove leading articles for brevity
    clue = re.sub(r'^(a |an |the )', '', clue.strip(), flags=re.IGNORECASE)
    # Collapse whitespace
    clue = ' '.join(clue.split())
    # Capitalize first letter
    clue = clue.strip()
    if clue:
        clue = clue[0].upper() + clue[1:]
    # Truncate at a natural boundary (semicolon, comma, or "or" clause) if too long
    # First, try splitting at semicolons
    if ';' in clue:
        clue = clue.split(';')[0].strip()
    # Then try splitting at " or " if still long
    words = clue.split()
    if len(words) > MAX_CLUE_WORDS and ' or ' in clue:
        clue = clue.split(' or ')[0].strip()
    # Truncate to MAX_CLUE_WORDS but only at a natural word boundary
    # (avoid cutting after articles, prepositions, conjunctions)
    words = clue.split()
    if len(words) > MAX_CLUE_WORDS:
        stop_words = {'a','an','the','of','to','in','for','on','at','by','or','and',
                       'with','as','from','that','is','it','its','into','not','be',
                       'no','so','if','than','but','up','out','some','how'}
        # Find the best cut point at or before MAX_CLUE_WORDS
        cut = MAX_CLUE_WORDS
        while cut > 3 and words[cut - 1].lower().rstrip('.,;:') in stop_words:
            cut -= 1
        clue = ' '.join(words[:cut])
    # Remove trailing punctuation artifacts
    clue = clue.rstrip(' ;,.:')
    return clue


def is_proper_noun_definition(definition: str) -> bool:
    """Check if a WordNet definition describes a proper noun or named entity."""
    defn_lower = definition.lower()
    return any(ind in defn_lower for ind in PROPER_NOUN_INDICATORS)


def make_clue_playful(word: str, clue: str, pos: str) -> str:
    """Transform a dictionary-style clue into a more crossword-style clue.

    Applies lightweight rewriting rules to make clues feel indirect,
    playful, or misdirecting — closer to a modern mini crossword.
    """
    original = clue

    # --- Pattern-based transformations ---

    # "Act of X-ing" → "X-ing" (shorter, punchier)
    m = re.match(r'^Act of (.+)$', clue, re.IGNORECASE)
    if m:
        clue = m.group(1).capitalize()

    # "The act of X-ing" → "X-ing"
    m = re.match(r'^(?:The )?act of (.+)$', clue, re.IGNORECASE)
    if m:
        clue = m.group(1).capitalize()

    # "Cause to be/become X" → "Make X"
    m = re.match(r'^Cause to (?:be|become) (.+)$', clue, re.IGNORECASE)
    if m:
        clue = f"Make {m.group(1).lower()}"

    # "Having the quality of X" → "Kind of X"
    m = re.match(r'^Having the quality of (.+)$', clue, re.IGNORECASE)
    if m:
        clue = f"Kind of {m.group(1).lower()}"

    # "Lacking X" → "Without X"
    m = re.match(r'^Lacking (.+)$', clue, re.IGNORECASE)
    if m:
        clue = f"Without {m.group(1).lower()}"

    # "Characterized by X" → "Full of X" or "Showing X"
    m = re.match(r'^Characterized by (.+)$', clue, re.IGNORECASE)
    if m:
        clue = f"Full of {m.group(1).lower()}"

    # "State of being X" → "Being X"
    m = re.match(r'^(?:The )?state of being (.+)$', clue, re.IGNORECASE)
    if m:
        clue = f"Being {m.group(1).lower()}"

    # "One who X-s" → "X-er, of sorts"
    m = re.match(r'^(?:One|Person|Someone) who (.+)$', clue, re.IGNORECASE)
    if m:
        clue = f"One who {m.group(1).lower()}, perhaps"

    # "Used to X" or "Used for X" → "It helps you X"
    m = re.match(r'^Used (?:to|for) (.+)$', clue, re.IGNORECASE)
    if m and len(m.group(1).split()) <= 5:
        clue = f"Helps with {m.group(1).lower()}"

    # "Relating to X" → "X-related, in a way"
    m = re.match(r'^(?:Of or )?[Rr]elating to (.+)$', clue, re.IGNORECASE)
    if m:
        clue = f"Connected to {m.group(1).lower()}"

    # --- Add playful suffixes to plain definitions ---
    # Only if the clue wasn't already transformed and is short enough
    if clue == original and len(clue.split()) <= 6:
        # For verbs, add indirect phrasing
        if pos == 'v':
            suffixes = [", say", ", perhaps", ", maybe", ", in a way"]
            rng = random.Random(hash(word))
            # Only apply ~40% of the time for variety
            if rng.random() < 0.4:
                clue = clue.rstrip('.') + rng.choice(suffixes)
        # For nouns, occasionally use "Kind of" or "Type of" prefix
        elif pos == 'n' and len(clue.split()) <= 4:
            rng = random.Random(hash(word))
            if rng.random() < 0.3:
                prefixes = ["Sort of", "Type of", "Kind of"]
                prefix = rng.choice(prefixes)
                clue = f"{prefix} {clue[0].lower()}{clue[1:]}"
        # For adjectives, occasionally add "perhaps"
        elif pos in ('a', 's') and len(clue.split()) <= 5:
            rng = random.Random(hash(word))
            if rng.random() < 0.35:
                clue = clue.rstrip('.') + ", perhaps"

    # Ensure first letter is capitalized
    if clue:
        clue = clue[0].upper() + clue[1:]

    # Re-truncate if transformations made it too long
    words = clue.split()
    if len(words) > MAX_CLUE_WORDS:
        clue = ' '.join(words[:MAX_CLUE_WORDS]).rstrip(' ;,.:')

    return clue


def get_best_clue(word: str, wordnet_en) -> Optional[str]:
    """Get the best non-proper-noun definition from WordNet and make it crossword-style."""
    senses = wordnet_en.senses(word.lower())
    if not senses:
        return None

    candidates = []

    for i, sense in enumerate(senses):
        synset = sense.synset()
        defn = synset.definition()
        if not defn:
            continue

        # Skip proper noun definitions
        if is_proper_noun_definition(defn):
            continue

        cleaned = clean_definition(defn)
        if not cleaned or len(cleaned) < 3:
            continue

        # Don't use clues that contain the answer word
        if word.lower() in cleaned.lower().split():
            continue

        # Skip inappropriate or overly clinical definitions
        inappropriate = ['sexual', 'intercourse', 'genitals', 'excrement', 'urinate', 'defecate']
        if any(bad in cleaned.lower() for bad in inappropriate):
            continue

        # Determine part of speech for clue styling
        pos = synset.pos

        # Score: strongly prefer first sense (most common meaning)
        # Lower score = better
        length_penalty = max(0, len(cleaned) - 50) * 0.5
        sense_rank = i * 50  # very strong preference for first sense
        score = sense_rank + length_penalty
        candidates.append((score, cleaned, pos))

    if not candidates:
        return None

    candidates.sort(key=lambda x: x[0])
    best_clue = candidates[0][1]
    best_pos = candidates[0][2]

    # Transform into a more playful crossword-style clue
    return make_clue_playful(word, best_clue, best_pos)


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    print("Loading Open English WordNet...")
    wordnet_en = wn.Wordnet("ewn:2020")

    print("Getting common English words from wordfreq...")
    # Get top N most frequent English words
    common_words = top_n_list(LANGUAGE, 100000, wordlist=FREQ_LIST)

    # Filter to valid crossword words (with WordNet proper noun check)
    candidates = [w for w in common_words if is_valid_word(w, wordnet_en)]
    print(f"  {len(candidates)} candidate words after filtering (length {MIN_LENGTH}-{MAX_LENGTH}, alpha-only)")

    results = []
    skipped_no_clue = 0

    for word in candidates:
        if len(results) >= TARGET_COUNT:
            break

        clue = get_best_clue(word, wordnet_en)
        if clue:
            results.append({
                "word": word.upper(),
                "clue": clue
            })
        else:
            skipped_no_clue += 1

    # Sort alphabetically for readability
    results.sort(key=lambda x: x["word"])

    # Write output
    output_path = Path(__file__).parent.parent / "Gridlet" / "Resources" / "wordlist.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "w") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    print(f"\nGenerated {len(results)} word-clue pairs → {output_path}")
    print(f"Skipped {skipped_no_clue} words (no suitable clue found)")

    # Print some stats
    lengths = {}
    for entry in results:
        l = len(entry["word"])
        lengths[l] = lengths.get(l, 0) + 1
    print("\nBy word length:")
    for l in sorted(lengths):
        print(f"  {l} letters: {lengths[l]} words")


if __name__ == "__main__":
    main()
