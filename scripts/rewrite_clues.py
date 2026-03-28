#!/usr/bin/env python3
"""
rewrite_clues.py — Rewrites fallback wordlist clues using an LLM to match
the on-device AI clue style (playful, indirect, crossword-worthy).

Uses the same style guidelines as AIWordService.swift so fallback clues
feel consistent with AI-generated ones.

Usage:
  export OPENAI_API_KEY="sk-..."
  python3 scripts/rewrite_clues.py

  # Preview without writing (dry run):
  python3 scripts/rewrite_clues.py --dry-run

  # Rewrite only entries whose clues look like fragments:
  python3 scripts/rewrite_clues.py --fragments-only

Output:
  Gridlet/Resources/wordlist.json (overwritten in-place)
"""

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

# openai is imported lazily in main() so fragment detection can be used standalone

# ── Configuration ──────────────────────────────────────────────────────────────

BATCH_SIZE = 40          # entries per API call
MODEL = "gpt-4o-mini"   # fast + cheap; use "gpt-4o" for higher quality
MAX_RETRIES = 3
RETRY_DELAY = 5          # seconds between retries

# Matches the style instructions from AIWordService.swift
SYSTEM_PROMPT = """\
You are an expert constructor for a modern mini crossword puzzle.

Rewrite each crossword clue to be clever, playful, and crossword-worthy.
Rules:
- Keep the exact same answer word — only rewrite the clue.
- Each clue must be 2 to 8 words long.
- Clues must read as a complete natural phrase, not a fragment.
- Must not contain the answer word or any form of it.
- Prefer playful, indirect, figurative, conversational, or lightly witty clues.
- At least one third should use mild misdirection, double meaning, or light humor.
- Avoid plain dictionary definitions.
- Prefer indirect phrasing, wordplay, and everyday language.

Respond with a JSON array of objects, each with "word" and "clue" keys.
Return ONLY the JSON array, no other text."""

# ── Fragment detection ─────────────────────────────────────────────────────────

INCOMPLETE_ENDINGS = {
    'a', 'an', 'the', 'of', 'to', 'in', 'for', 'on', 'at', 'by', 'or', 'and',
    'with', 'as', 'from', 'that', 'into', 'not', 'be', 'between', 'about',
    'through', 'under', 'over', 'after', 'before', 'without', 'within',
    'upon', 'toward', 'towards', 'against', 'having', 'being', 'whose',
    'where', 'which', 'when', 'while', 'especially', 'particularly',
    'typically', 'usually', 'often', 'associated', 'consisting',
    'including', 'involving', 'containing', 'related', 'resulting',
    'causing', 'producing', 'providing',
}

DICTIONARY_PATTERNS = [
    r'^(?:Any|Some) (?:of )?(?:various|several|numerous)',
    r'^(?:The )?(?:act|process|state) of',
    r'^(?:Of or )?[Rr]elating to',
    r'^(?:A |An )?(?:large |small )?(?:group|collection|set|body|piece) of',
]


def is_fragment(clue: str) -> bool:
    """Detect clues that are likely incomplete sentences or dictionary-style."""
    words = clue.split()
    if not words:
        return True
    last_word = words[-1].lower().rstrip('.,;:')
    if last_word in INCOMPLETE_ENDINGS:
        return True
    for pattern in DICTIONARY_PATTERNS:
        if re.match(pattern, clue):
            return True
    return False


# ── LLM rewriting ─────────────────────────────────────────────────────────────

def rewrite_batch(client, entries: list[dict], model: str = MODEL) -> list[dict]:
    """Send a batch of word-clue pairs to the LLM for rewriting."""
    user_content = json.dumps(
        [{"word": e["word"], "clue": e["clue"]} for e in entries],
        ensure_ascii=False,
    )

    for attempt in range(MAX_RETRIES):
        try:
            response = client.chat.completions.create(
                model=MODEL,
                temperature=0.8,
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": user_content},
                ],
                response_format={"type": "json_object"},
            )

            text = response.choices[0].message.content.strip()
            parsed = json.loads(text)

            # Handle both {"entries": [...]} and [...] formats
            if isinstance(parsed, dict):
                parsed = parsed.get("entries") or parsed.get("results") or list(parsed.values())[0]
            if not isinstance(parsed, list):
                raise ValueError(f"Expected list, got {type(parsed)}")

            # Build lookup by word
            rewritten = {item["word"].upper(): item["clue"] for item in parsed}

            # Merge back, keeping originals for any missing entries
            results = []
            for entry in entries:
                word = entry["word"]
                new_clue = rewritten.get(word, entry["clue"])
                # Validate: clue must not contain the answer word
                if word.lower() in new_clue.lower().split():
                    new_clue = entry["clue"]  # keep original if LLM included answer
                # Validate: clue should be 2-8 words
                clue_words = new_clue.split()
                if len(clue_words) < 2 or len(clue_words) > 10:
                    new_clue = entry["clue"]
                results.append({"word": word, "clue": new_clue})

            return results

        except (json.JSONDecodeError, KeyError, ValueError) as e:
            print(f"  ⚠ Batch parse error (attempt {attempt + 1}/{MAX_RETRIES}): {e}")
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_DELAY)
        except Exception as e:
            print(f"  ⚠ API error (attempt {attempt + 1}/{MAX_RETRIES}): {e}")
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_DELAY)

    # All retries failed — return originals
    print("  ✗ All retries failed, keeping original clues for this batch")
    return entries


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Rewrite wordlist clues using an LLM")
    parser.add_argument("--dry-run", action="store_true",
                        help="Preview changes without writing to file")
    parser.add_argument("--fragments-only", action="store_true",
                        help="Only rewrite clues that look like incomplete fragments")
    parser.add_argument("--model", default=MODEL,
                        help=f"OpenAI model to use (default: {MODEL})")
    args = parser.parse_args()

    if not args.dry_run:
        try:
            from openai import OpenAI
        except ImportError:
            print("Error: openai package required. Install with: pip install openai")
            sys.exit(1)

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key and not args.dry_run:
        print("Error: Set OPENAI_API_KEY environment variable")
        sys.exit(1)

    wordlist_path = Path(__file__).parent.parent / "Gridlet" / "Resources" / "wordlist.json"
    if not wordlist_path.exists():
        print(f"Error: {wordlist_path} not found. Run generate_wordlist.py first.")
        sys.exit(1)

    with open(wordlist_path) as f:
        wordlist = json.load(f)

    print(f"Loaded {len(wordlist)} entries from {wordlist_path}")

    # Determine which entries need rewriting
    if args.fragments_only:
        to_rewrite = [e for e in wordlist if is_fragment(e["clue"])]
        to_keep = [e for e in wordlist if not is_fragment(e["clue"])]
        print(f"Found {len(to_rewrite)} fragment/dictionary-style clues to rewrite")
        print(f"Keeping {len(to_keep)} clues as-is")
    else:
        to_rewrite = wordlist
        to_keep = []
        print(f"Rewriting all {len(to_rewrite)} clues")

    if not to_rewrite:
        print("Nothing to rewrite!")
        return

    if args.dry_run:
        print(f"\n--- DRY RUN: showing {min(20, len(to_rewrite))} sample fragments ---")
        for entry in to_rewrite[:20]:
            print(f"  {entry['word']:>7s} → {entry['clue']}")
        if len(to_rewrite) > 20:
            print(f"  ... and {len(to_rewrite) - 20} more")
        return

    client = OpenAI(api_key=api_key)
    model = args.model

    # Process in batches
    rewritten = []
    total_batches = (len(to_rewrite) + BATCH_SIZE - 1) // BATCH_SIZE
    for i in range(0, len(to_rewrite), BATCH_SIZE):
        batch = to_rewrite[i:i + BATCH_SIZE]
        batch_num = i // BATCH_SIZE + 1
        print(f"  Batch {batch_num}/{total_batches} ({len(batch)} entries)...", end=" ", flush=True)

        result = rewrite_batch(client, batch, model=model)
        rewritten.extend(result)

        # Show a sample
        if result:
            sample = result[0]
            original = batch[0]["clue"]
            print(f"✓  e.g. {sample['word']}: \"{original}\" → \"{sample['clue']}\"")

        # Rate limiting
        if i + BATCH_SIZE < len(to_rewrite):
            time.sleep(1)

    # Merge rewritten + kept entries, sorted alphabetically
    final = rewritten + to_keep
    final.sort(key=lambda x: x["word"])

    # Count changes
    original_map = {e["word"]: e["clue"] for e in wordlist}
    changed = sum(1 for e in final if e["clue"] != original_map.get(e["word"], ""))
    print(f"\nChanged {changed}/{len(final)} clues")

    # Write output
    with open(wordlist_path, "w") as f:
        json.dump(final, f, indent=2, ensure_ascii=False)
    print(f"Written to {wordlist_path}")


if __name__ == "__main__":
    main()
