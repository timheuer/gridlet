import SwiftUI

/// The main puzzle-solving screen combining grid, clue bar, and keyboard.
struct PuzzleView: View {
  @Bindable var viewModel: PuzzleViewModel
  @Environment(\.dismiss) private var dismiss

  @State private var timerTask: Task<Void, Never>?
  @State private var showCompletion = false
  @State private var showDevInfo = false
  @State private var showIncorrectBanner = false

  var body: some View {
    VStack(spacing: 0) {
      // Header with timer and check button
      headerBar
        .frame(height: 44)

      Spacer(minLength: 8)

      // Crossword grid
      GridView(viewModel: viewModel)

      Spacer(minLength: 8)

      // Clue bar with prev/next navigation — fixed height
      ClueBarView(
        clueText: viewModel.activeClue,
        accessibilityLabel: viewModel.activeClueAccessibilityLabel,
        accessibilityValue: viewModel.activeClueAccessibilityValue,
        accessibilityHint: viewModel.activeClueAccessibilityHint,
        onPrevious: { viewModel.selectPreviousWord() },
        onNext: { viewModel.selectNextWord() },
        onToggleDirection: { toggleDirection() }
      )

      Spacer(minLength: 8)

      // Keyboard — always present to preserve layout
      KeyboardView(
        onLetter: { letter in
          viewModel.enterLetter(letter)
          checkForCompletion()
        },
        onBackspace: {
          viewModel.backspace()
        }
      )
      .opacity(viewModel.isCompleted ? 0 : 1)
      .disabled(viewModel.isCompleted)
    }
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(viewModel.isCompleted)
    .onAppear { startTimer() }
    .onDisappear { stopTimer() }
    .overlay {
      if showCompletion {
        completionOverlay
      }
    }
    .overlay(alignment: .top) {
      if showIncorrectBanner {
        incorrectBanner
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .onChange(of: viewModel.showIncorrectMessage) { _, newValue in
      if newValue {
        viewModel.showIncorrectMessage = false
        withAnimation(.easeInOut(duration: 0.3)) {
          showIncorrectBanner = true
        }
        // Auto-dismiss after 3 seconds
        Task { @MainActor in
          try? await Task.sleep(for: .seconds(3))
          withAnimation(.easeInOut(duration: 0.3)) {
            showIncorrectBanner = false
          }
        }
      }
    }
    .sheet(isPresented: $showDevInfo) {
      DevInfoView(viewModel: viewModel)
    }
  }

  // MARK: - Header

  private var headerBar: some View {
    HStack {
      // Timer
      Text(formattedTime)
        .font(.system(.body, design: .rounded).monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityLabel("Elapsed time")
        .accessibilityValue(formattedTime)

      Spacer()

      if viewModel.puzzle.isAIGenerated {
        Image(systemName: "sparkles")
          .foregroundStyle(.purple)
          .accessibilityLabel("Generated with Apple Intelligence")
      }

      if viewModel.devMode {
        Button {
          viewModel.devMode.toggle()
        } label: {
          Image(systemName: "eye.fill")
            .foregroundStyle(.orange)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel("Toggle solution letters")
        .accessibilityHint("Shows or hides the dimmed solution letters in developer mode.")

        Button {
          showDevInfo = true
        } label: {
          Image(systemName: "info.circle")
            .foregroundStyle(.orange)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel("Show developer info")
        .accessibilityHint("Opens puzzle metadata and grid statistics.")
      }

      if !viewModel.isCompleted {
        Button("Check") {
          viewModel.checkActiveWord()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(viewModel.gameState.selectedCell == nil)
        .accessibilityLabel("Check current word")
        .accessibilityHint("Marks incorrect letters in the selected word.")
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 4)
  }

  // MARK: - Completion Overlay

  private var completionOverlay: some View {
    ZStack {
      Color.black.opacity(0.3)
        .ignoresSafeArea()
        .accessibilityHidden(true)

      completionCard
        .padding(32)
    }
    .transition(.opacity)
  }

  private var completionCard: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 60))
        .foregroundStyle(.green)
        .accessibilityHidden(true)

      Text("Puzzle Complete!")
        .font(.title.bold())

      Text("Time: \(formattedTime)")
        .font(.title3)

      if viewModel.gameState.checksUsed > 0 {
        Text("Checks used: \(viewModel.gameState.checksUsed)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Button("Done") {
        dismiss()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .padding(.top, 8)
    }
    .padding(32)
    .background {
      RoundedRectangle(cornerRadius: 20)
        .fill(.ultraThickMaterial)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Puzzle complete")
    .accessibilityValue("Finished in \(formattedTime)")
    .accessibilityHint("Use the Done button to return to the home screen.")
  }

  // MARK: - Incorrect Banner

  private var incorrectBanner: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
      Text("Something's not quite right — keep trying!")
        .font(.subheadline.weight(.medium))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.ultraThickMaterial, in: Capsule())
    .padding(.top, 8)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Check result")
    .accessibilityValue("Something is not quite right. Keep trying.")
  }

  // MARK: - Helpers

  private var formattedTime: String {
    let total = Int(viewModel.gameState.elapsedSeconds)
    let minutes = total / 60
    let seconds = total % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  private func toggleDirection() {
    if let cell = viewModel.gameState.selectedCell {
      viewModel.selectCell(row: cell.row, col: cell.col)
    }
  }

  private func checkForCompletion() {
    if viewModel.isCompleted && !showCompletion {
      withAnimation(.easeInOut(duration: 0.5)) {
        showCompletion = true
      }
    }
  }

  private func startTimer() {
    timerTask = Task { @MainActor in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        if !Task.isCancelled {
          viewModel.addElapsedTime(1)
        }
      }
    }
  }

  private func stopTimer() {
    timerTask?.cancel()
    timerTask = nil
  }
}
