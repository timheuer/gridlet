# Crucigram — Copilot Instructions

## Project Overview
Crucigram is an offline-first iPhone word puzzle game built with SwiftUI (iOS 26+, `com.timheuer.gridlet`). Players solve 5×5, 6×6, or 7×7 crossword-style grids with words running horizontally and vertically only. The app offers a deterministic daily puzzle plus unlimited algorithmically-generated puzzles — all generated on-device with no backend.

## Build Instructions
- **Always run `xcodegen generate` before building.** The Xcode project is generated from `project.yml` — never edit `Gridlet.xcodeproj` directly.
- Use **iPhone 17 Pro Max** as the simulator destination for all builds and tests:
  ```
  xcodegen generate
  xcodebuild build -project Gridlet.xcodeproj -scheme Gridlet -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
  ```
- **For routine verification**, run the fast test suites only (excludes the slow `PuzzleGenerationPipelineTests`):
  ```
  xcodebuild test -project Gridlet.xcodeproj -scheme GridletTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -skip-testing:GridletTests/PuzzleGenerationPipelineTests
  ```
- **For full test runs** (e.g., before release or when changing generation logic), run all tests:
  ```
  xcodebuild test -project Gridlet.xcodeproj -scheme GridletTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
  ```
- Use `-quiet` flag for routine builds; omit it when debugging build failures.

## Architecture
- **Pattern**: MVVM with `@Observable` (iOS 17+ Observation framework)
- **No Combine**, no UIKit — pure SwiftUI
- **No backend** — fully offline
- **Persistence**: JSON files via `PersistenceService` (documents directory)
- **Word/Clue Generation**: Apple Intelligence (Foundation Models framework) for on-device AI generation, with bundled wordlist fallback

## Key Systems
| System | Files | Purpose |
|--------|-------|---------|
| Models | `Gridlet/Sources/Models/` | `PuzzleDefinition`, `GameState`, `PlayerStats`, `WordEntry`, etc. |
| Generator | `Gridlet/Sources/Generator/` | `CrosswordLayoutGenerator` — seeded crossword layout engine optimized for 5×5/6×6/7×7 grids |
| Services | `Gridlet/Sources/Services/` | `PuzzleGeneratorService`, `DailyPuzzleService`, `PuzzleWarmupService`, `AIWordService`, `WordListService`, `PersistenceService` |
| ViewModels | `Gridlet/Sources/ViewModels/` | `PuzzleViewModel`, `StatsViewModel` |
| Views | `Gridlet/Sources/Views/` | `HomeView`, `PuzzleView`, `StatsView`, `SettingsView`, `OnboardingView`, `AcknowledgmentsView`, plus `Components/` |
| Tests | `GridletTests/` | `ModelTests`, `GeneratorTests`, `GridDensityTests` |
| Scripts | `scripts/` | `generate_wordlist.py` — generates fallback `wordlist.json` from Open English WordNet + wordfreq |
| Store Info | `store-info/` | `app-information.md` — App Store metadata, descriptions, review notes |
| Privacy | `Gridlet/Resources/PrivacyInfo.xcprivacy` | Required iOS 17+ privacy manifest (declares no data collection) |
| Licenses | `LICENSE` | MIT license for Crucigram + third-party notices (iOS-Crosswords-Generator, Open English WordNet, wordfreq) |

## Word & Clue Generation
- **Primary**: `AIWordService` uses Apple Intelligence (Foundation Models, `@Generable` macro) to generate word-clue pairs on-device.
- **Fallback**: Bundled `Gridlet/Resources/wordlist.json` is used when Apple Intelligence is unavailable (older devices, simulator).
- **Fallback with AI clues**: When AI word generation fails but Apple Intelligence is still available, the app uses bundled words but rewrites their clues with AI for a more playful crossword style (10s timeout).
- **Solved-word exclusion**: Words from completed puzzles are persisted and hard-excluded from future AI, fallback, and supplement candidate pools until the word history is cleared in developer mode.
- The `PuzzleGeneratorService` exposes both `generate(seed:)` (sync, bundled list) and `generateWithAI(seed:)` (async, AI-powered) methods.
- `PuzzleWarmupService` starts speculative Daily and Play generation from the home screen so taps can reuse an in-flight or completed puzzle, and it keeps the next unlimited puzzle warming in the background while an unlimited game is being played (using a 30s AI timeout budget for that background work).
- To regenerate fallback wordlist: `pip install wordfreq wn && python3 scripts/generate_wordlist.py`

## Game Rules (Fixed — Do Not Change)
- Grid sizes: **only 5×5, 6×6, or 7×7** — never any other sizes
- Words run **only horizontally or vertically** — no diagonals
- Tapping a cell reveals the clue for the active word (across or down)
- Tapping the same cell again toggles between across and down
- Clue bar shows `N→ clue` for across and `N↓ clue` for down (arrows, not words)
- Clue bar has prev/next chevron navigation to cycle through words
- **Check** marks wrong letters in the *currently selected word* with a transparent red overlay (`Color.red.opacity(0.3)`)
- Daily puzzle: deterministic via `SHA256(bundleId + "YYYY-MM-DD")` seed
- Unlimited play: random seed per session, with resume/restart flow

## UI/UX Design Patterns (Fixed — Do Not Change)
- **Typography**: Use SF Pro Rounded (`.design(.rounded)`) for all game UI — grid cells, keyboard, titles. Use `.monospacedDigit()` for timers.
- **Grid colors are fixed black/white like a real crossword** — they do NOT adapt to dark/light mode:
  - Empty cells: `.white`
  - Black/blocked cells: `.black`
  - Selected cell: warm yellow `Color(red: 1.0, green: 0.85, blue: 0.35)`
  - Active word cells: light blue `Color(red: 0.73, green: 0.87, blue: 1.0)`
  - All text/numbers in grid: `Color.black`
  - Cell borders: `Color.gray` (0.5pt)
  - Outer grid border: `Color.gray` (2pt)
- **Layout stability**: UI elements that may appear/disappear (streak badge, clue bar, etc.) must use fixed-height frames so they never shift other elements. Clue bar: 56pt. Header bar: 44pt. Streak area: 28pt.
- **No flexible Spacers** between title and buttons on home screen — use fixed spacing.

## Developer Mode
- Activated by tapping the "Crucigram" title 5 times on the home screen (works in release builds)
- Persisted via `@AppStorage("devModeEnabled")`
- Deactivated by tapping the hammer icon in the toolbar
- Features: show solution letters (dimmed), dev info sheet (puzzle metadata, word list, grid stats), reset daily, replay onboarding

## Conventions
- Swift 6 strict concurrency (`@unchecked Sendable` for services wrapping non-Sendable types)
- All models conform to `Codable` and `Sendable`
- Use `@Observable` for view models, not `ObservableObject`
- Crossword numbering: standard order (top-to-bottom, left-to-right)
- Accessibility: all interactive elements must have VoiceOver labels
- `ForEach` with index ranges may fail in Swift 6.2 — use helper functions or `ForEach(collection)` with `Identifiable` types instead

## Keeping Instructions Current
**After making any changes to the codebase, review and update this file as needed.** If you add new systems, change the architecture, modify build steps, or alter game rules, reflect those changes here so these instructions stay accurate.
