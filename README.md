# Crucigram

A bite-sized crossword puzzle game for iPhone. Daily puzzles, unlimited play, fully offline.

## Features

- **Daily Puzzle** — A new crossword every day with streak tracking
- **Unlimited Play** — Generate and play as many puzzles as you want
- **Apple Intelligence** — Words and clues generated on-device using Foundation Models
- **Fully Offline** — No internet, no accounts, no tracking
- **Check Your Work** — Highlights incorrect letters so you can fix and keep going
- **5×5 & 6×6 Grids** — Quick, satisfying puzzles designed for mobile

## Requirements

- iOS 26.0+
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Getting Started

```bash
# Generate the Xcode project
xcodegen generate

# Open in Xcode
open Gridlet.xcodeproj
```

Build and run on an iPhone simulator or device running iOS 26+.

## Building from Command Line

```bash
xcodegen generate

xcodebuild -project Gridlet.xcodeproj \
  -scheme Gridlet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build
```

## Running Tests

```bash
xcodebuild -project Gridlet.xcodeproj \
  -scheme Gridlet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  test
```

## Project Structure

```
Gridlet/
├── Sources/
│   ├── Generator/        # Crossword grid layout engine
│   ├── Models/            # Puzzle, clue, and game state models
│   ├── Services/          # Persistence, daily puzzle, AI word generation
│   ├── ViewModels/        # Game logic and state management
│   └── Views/             # SwiftUI views and components
├── Resources/             # Assets, word list, privacy manifest
docs/                      # Landing page (GitHub Pages)
scripts/                   # Build and utility scripts
```

## Privacy

Crucigram collects no data. All game state and statistics are stored locally on-device. See the full [Privacy Policy](https://timheuer.com/gridlet/privacy).

## License

[MIT](LICENSE)
