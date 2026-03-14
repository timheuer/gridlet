import Foundation

/// The two supported grid sizes for Crucigram puzzles.
enum GridSize: Int, Codable, CaseIterable, Sendable {
    case five = 5
    case six = 6

    /// The number of rows and columns (grids are always square).
    var dimension: Int { rawValue }
}
