import SwiftUI

struct HomeView: View {
  @State private var puzzleVM: PuzzleViewModel?
  @State private var navigateToPuzzle = false
  @State private var stats = PersistenceService.shared.loadPlayerStats()
  @State private var isGenerating = false
  @State private var generatingPhraseIndex = 0
  @State private var generatingTimer: Timer?
  @State private var countdownSeconds: Int = 0
  @State private var titleTapCount = 0
  @State private var showOnboarding = false
  @State private var showResumeAlert = false
  @AppStorage("devModeEnabled") private var devModeEnabled = false
  @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

  private let persistence = PersistenceService.shared
  private let warmupService = PuzzleWarmupService.shared

  private let generatingPhrases = [
    "Searching the dictionary…",
    "Finding good words…",
    "Asking the crossword wizards…",
    "Sharpening pencils…",
    "Checking 4 across…",
    "Erasing and trying again…",
    "Consulting the thesaurus…",
    "Debating vowel placement…",
    "Almost there…",
    "Convincing words to intersect…",
    "Brewing crossword magic…",
    "Untangling letters…",
  ]

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Spacer()

        // Title area
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("Crucigram")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                    .onTapGesture {
                        titleTapCount += 1
                        if titleTapCount >= 5 {
                            devModeEnabled.toggle()
                            titleTapCount = 0
                        }
                    }
                Image(systemName: "sparkles")
                  .symbolRenderingMode(.hierarchical)
                  .foregroundStyle(Color.accentColor)
            }

            Text("Daily unlimited crossword puzzles")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }

        Spacer()
          .frame(height: 32)

        // Streak — fixed height so it never shifts buttons
        HStack(spacing: 4) {
          if stats.currentStreak > 0 {
            Image(systemName: "flame.fill")
            Text("\(stats.currentStreak) day streak")
          }
        }
        .font(.headline)
        .foregroundStyle(.orange)
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          stats.currentStreak > 0
            ? "Current streak \(stats.currentStreak) days" : "No current streak")

        Spacer()
          .frame(height: 20)

        // Buttons
        VStack(spacing: 12) {
          Button {
            startDailyPuzzle()
          } label: {
            HStack {
              Image(systemName: "calendar")
              Text(dailyButtonLabel)
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .disabled(isDailyCompleted || isGenerating)
          .accessibilityHint(
            isDailyCompleted
              ? "Today\'s daily puzzle is already complete."
              : "Starts or resumes today\'s daily crossword.")

          Button {
            handleUnlimitedTap()
          } label: {
            HStack {
              if isGenerating {
                Image(systemName: "sparkles")
                  .symbolEffect(.bounce, options: .repeating)
              } else {
                Image(systemName: "play.fill")
              }
              Text(isGenerating ? generatingPhrases[generatingPhraseIndex] : unlimitedButtonLabel)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .disabled(isGenerating)
          .accessibilityHint(
            hasUnlimitedInProgress
              ? "Opens your unfinished unlimited puzzle." : "Starts a new unlimited puzzle.")

          if devModeEnabled {
            Button {
              resetDaily()
            } label: {
              HStack {
                Image(systemName: "calendar.badge.minus")
                Text("Reset Daily")
              }
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.orange)
            .accessibilityHint("Clears the saved daily puzzle so you can replay it.")

            Button {
              showOnboarding = true
            } label: {
              HStack {
                Image(systemName: "arrow.counterclockwise")
                Text("Replay Onboarding")
              }
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.orange)
            .accessibilityHint("Shows the onboarding tutorial again.")

            Button {
              testNotification()
            } label: {
              HStack {
                Image(systemName: "bell.badge")
                Text("Test Notification (5s)")
              }
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.orange)
            .accessibilityHint("Sends a test daily reminder notification in 5 seconds.")

            Button {
              AIWordService.shared.clearRecentWords()
            } label: {
              HStack {
                Image(systemName: "trash")
                Text("Clear Word History")
              }
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.orange)
            .accessibilityHint("Clears the AI recent words history so previously used words can appear again.")
          }
        }
        .padding(.horizontal, 32)

        if devModeEnabled && isGenerating {
          Text("AI timeout: \(countdownSeconds)s")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.orange)
            .padding(.top, 8)
        }

        Spacer()
      }
      .padding()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          if devModeEnabled {
            Button {
              devModeEnabled = false
            } label: {
              Label("Dev Mode", systemImage: "hammer.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            }
            .accessibilityLabel("Disable developer mode")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: 16) {
            NavigationLink {
              StatsView()
            } label: {
              Image(systemName: "chart.bar.fill")
            }
            .accessibilityLabel("Statistics")
            NavigationLink {
              SettingsView()
            } label: {
              Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
          }
        }
      }
      .navigationDestination(isPresented: $navigateToPuzzle) {
        if let vm = puzzleVM {
          PuzzleView(viewModel: vm)
            .onDisappear {
              handlePuzzleReturn()
            }
        }
      }
      .onAppear {
        refreshStats()
        Task(priority: .utility) {
          await warmupService.startWarmup()
        }
      }
      .fullScreenCover(isPresented: $showOnboarding) {
        OnboardingView()
      }
      .alert("Resume Puzzle?", isPresented: $showResumeAlert) {
        Button("Resume") { resumeUnlimitedPuzzle() }
        Button("New Puzzle", role: .destructive) { startNewUnlimitedPuzzle() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("You have an unfinished puzzle. Would you like to continue where you left off?")
      }
      .onAppear {
        if !hasSeenOnboarding {
          showOnboarding = true
          hasSeenOnboarding = true
        }
      }
    }
  }

  // MARK: - Daily Puzzle

  private var isDailyCompleted: Bool {
    stats.lastDailyCompletedDate == PlayerStats.todayString()
  }

  private var dailyButtonLabel: String {
    if isDailyCompleted {
      return "Daily Complete ✓"
    }
    if persistence.loadDailyGameState() != nil {
      return "Resume Daily"
    }
    return "Daily Puzzle"
  }

  private func startDailyPuzzle() {
    startGenerating()

    Task {
      let puzzle = await warmupService.dailyPuzzle()

      let gameState: GameState
      if let saved = persistence.loadDailyGameState(), saved.puzzleId == puzzle.id {
        gameState = saved
      } else {
        gameState = GameState(puzzleId: puzzle.id, isDaily: true, gridSize: puzzle.gridSize)
      }

      await MainActor.run {
        puzzleVM = PuzzleViewModel(puzzle: puzzle, gameState: gameState)
        puzzleVM?.devMode = devModeEnabled
        stopGenerating()
        navigateToPuzzle = true
      }
    }
  }

  // MARK: - Unlimited Puzzle

  private var hasUnlimitedInProgress: Bool {
    persistence.loadUnlimitedGameState() != nil && persistence.loadUnlimitedPuzzle() != nil
  }

  private var unlimitedButtonLabel: String {
    hasUnlimitedInProgress ? "Resume Play" : "Play"
  }

  private func handleUnlimitedTap() {
    if hasUnlimitedInProgress {
      showResumeAlert = true
    } else {
      startNewUnlimitedPuzzle()
    }
  }

  private func resumeUnlimitedPuzzle() {
    guard let puzzle = persistence.loadUnlimitedPuzzle(),
      let savedState = persistence.loadUnlimitedGameState(),
      savedState.puzzleId == puzzle.id
    else {
      startNewUnlimitedPuzzle()
      return
    }

    puzzleVM = PuzzleViewModel(puzzle: puzzle, gameState: savedState)
    puzzleVM?.devMode = devModeEnabled
    navigateToPuzzle = true
    Task {
      await warmupService.warmNextUnlimitedPuzzle()
    }
  }

  private func startNewUnlimitedPuzzle() {
    // Clear any saved unlimited state
    persistence.clearUnlimitedGameState()
    persistence.clearUnlimitedPuzzle()

    Task {
      let timeoutSeconds = await warmupService.unlimitedWarmupTimeoutSeconds()
      startGenerating(timeoutSeconds: timeoutSeconds)
      let puzzle = await warmupService.unlimitedPuzzle()
      let gameState = GameState(puzzleId: puzzle.id, isDaily: false, gridSize: puzzle.gridSize)

      // Save puzzle so we can resume later
      try? persistence.saveUnlimitedPuzzle(puzzle)

      await MainActor.run {
        puzzleVM = PuzzleViewModel(puzzle: puzzle, gameState: gameState)
        puzzleVM?.devMode = devModeEnabled
        stopGenerating()
        navigateToPuzzle = true
      }
    }
  }

  // MARK: - Return from puzzle

  private func handlePuzzleReturn() {
    guard let vm = puzzleVM, vm.isCompleted else {
      refreshStats()
      Task {
        await warmupService.startWarmup()
      }
      return
    }

    let record = CompletionRecord(
      puzzleId: vm.gameState.puzzleId,
      elapsedSeconds: vm.gameState.elapsedSeconds,
      gridSize: vm.puzzle.gridSize,
      checksUsed: vm.gameState.checksUsed,
      isDaily: vm.gameState.isDaily
    )

    if vm.gameState.isDaily {
      stats.recordDailyCompletion(record: record)
      persistence.clearDailyGameState()
    } else {
      stats.recordUnlimitedCompletion(record: record)
      persistence.clearUnlimitedGameState()
      persistence.clearUnlimitedPuzzle()
    }

    try? persistence.savePlayerStats(stats)
    puzzleVM = nil
    Task {
      await warmupService.startWarmup()
    }
  }

  private func refreshStats() {
    stats = persistence.loadPlayerStats()
    stats.validateStreak()
  }

  // MARK: - Generating Phrases

  private func startGenerating(timeoutSeconds: TimeInterval = AIWordService.aiTimeoutSeconds) {
    generatingPhraseIndex = Int.random(in: 0..<generatingPhrases.count)
    countdownSeconds = Int(timeoutSeconds.rounded())
    isGenerating = true
    generatingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
      Task { @MainActor in
        withAnimation {
          if countdownSeconds > 0 {
            countdownSeconds -= 1
          }
          // Rotate phrase every 2 seconds
          if countdownSeconds % 2 == 0 {
            generatingPhraseIndex = (generatingPhraseIndex + 1) % generatingPhrases.count
          }
        }
      }
    }
  }

  private func stopGenerating() {
    generatingTimer?.invalidate()
    generatingTimer = nil
    isGenerating = false
    countdownSeconds = 0
  }

  // MARK: - Dev Mode Actions

  private func resetDaily() {
    persistence.clearDailyGameState()
    stats.lastDailyCompletedDate = nil
    try? persistence.savePlayerStats(stats)
    refreshStats()
  }

  private func testNotification() {
    Task {
      await NotificationService.shared.requestPermission()
      NotificationService.shared.scheduleTestNotification(streak: stats.currentStreak)
    }
  }
}

#Preview {
  HomeView()
}
