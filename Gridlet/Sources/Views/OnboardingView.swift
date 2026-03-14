import SwiftUI

/// First-run onboarding flow explaining how to play Crucigram.
struct OnboardingView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var currentPage = 0

  private let pages: [OnboardingPage] = [
    OnboardingPage(
      icon: "square.grid.3x3.fill",
      title: "Welcome to Crucigram",
      description:
        "A bite-sized crossword puzzle you can solve in minutes. Fill the grid with words that run across and down."
    ),
    OnboardingPage(
      icon: "calendar.badge.clock",
      title: "Two Ways to Play",
      description:
        "Solve the Daily Puzzle to build your streak — a new one every day. Or tap Unlimited to play as many puzzles as you want, anytime."
    ),
    OnboardingPage(
      icon: "sparkles",
      title: "Crafted On-Device",
      description:
        "Each puzzle is generated in real time using on-device intelligence. It may take a few seconds to create your puzzle — the smart robots are thinking!"
    ),
    OnboardingPage(
      icon: "hand.tap.fill",
      title: "Tap to Select",
      description:
        "Tap any cell to select it and see the clue. Tap the same cell again to switch between across and down."
    ),
    OnboardingPage(
      icon: "keyboard.fill",
      title: "Type to Fill",
      description:
        "Use the keyboard to enter letters. The cursor automatically advances to the next empty cell in the word."
    ),
    OnboardingPage(
      icon: "checkmark.circle.fill",
      title: "Check Your Work",
      description:
        "Tap Check to verify the currently selected word. Wrong letters are highlighted in red — fix them and try again."
    ),
  ]

  var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $currentPage) {
        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
          VStack(spacing: 24) {
            Spacer()

            Image(systemName: page.icon)
              .font(.system(size: 64))
              .foregroundStyle(Color.accentColor)
              .accessibilityHidden(true)

            Text(page.title)
              .font(.system(size: 28, weight: .bold, design: .rounded))
              .multilineTextAlignment(.center)
              .accessibilityAddTraits(.isHeader)

            Text(page.description)
              .font(.body)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 40)

            Spacer()
            Spacer()
          }
          .tag(index)
          .accessibilityElement(children: .combine)
          .accessibilityLabel(page.title)
          .accessibilityValue(page.description)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .always))

      // Bottom button
      Button {
        if currentPage < pages.count - 1 {
          withAnimation {
            currentPage += 1
          }
        } else {
          dismiss()
        }
      } label: {
        Text(currentPage < pages.count - 1 ? "Next" : "Let's Play!")
          .font(.headline)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .padding(.horizontal, 32)
      .padding(.bottom, 32)
      .accessibilityValue("Page \(currentPage + 1) of \(pages.count)")
      .accessibilityHint(
        currentPage < pages.count - 1
          ? "Moves to the next onboarding page." : "Closes onboarding and starts the game.")

      if currentPage < pages.count - 1 {
        Button("Skip") {
          dismiss()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.bottom, 16)
        .accessibilityLabel("Skip onboarding")
        .accessibilityHint("Closes the tutorial and goes to the home screen.")
      }
    }
  }
}

private struct OnboardingPage {
  let icon: String
  let title: String
  let description: String
}

#Preview {
  OnboardingView()
}
