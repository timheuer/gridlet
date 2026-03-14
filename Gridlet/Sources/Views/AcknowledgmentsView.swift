import SwiftUI

/// Displays open source licenses and acknowledgments.
struct AcknowledgmentsView: View {
  private let crosswordGeneratorURL = URL(
    string: "https://github.com/maximbilan/iOS-Crosswords-Generator")
  private let wordNetURL = URL(string: "https://en-word.net/")
  private let wordfreqURL = URL(string: "https://github.com/rspeer/wordfreq")

  var body: some View {
    List {
      Section {
        Text("Crucigram uses the following open source software and data.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Section("Crossword Generator") {
        VStack(alignment: .leading, spacing: 8) {
          if let url = crosswordGeneratorURL {
            Link(destination: url) {
              HStack {
                Text("iOS-Crosswords-Generator")
                  .font(.headline)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          Text("by Maxim Bilan")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text("MIT License")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      }

      Section("Word Data") {
        VStack(alignment: .leading, spacing: 8) {
          if let url = wordNetURL {
            Link(destination: url) {
              HStack {
                Text("Open English WordNet")
                  .font(.headline)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          Text("Derived from Princeton WordNet by the Open English Wordnet Community")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text("CC-BY 4.0 License")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 8) {
          if let url = wordfreqURL {
            Link(destination: url) {
              HStack {
                Text("wordfreq")
                  .font(.headline)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          Text("by Robyn Speer")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text("Apache 2.0 / CC-BY-SA 4.0 License")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("Includes data from SUBTLEX (Marc Brysbaert et al.) and Google Books Ngrams")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      }
    }
    .navigationTitle("Acknowledgments")
  }
}

#Preview {
  NavigationStack {
    AcknowledgmentsView()
  }
}
