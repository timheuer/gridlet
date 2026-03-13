import Foundation

/// Captures how Apple Intelligence participated in puzzle generation.
enum AIGenerationStatus: String, Codable, Sendable, Equatable {
    case generatedWithAI
    case generatedWithAISupplement
    case appleIntelligenceUnavailable
    case generationRequestFailed
    case validationFailed
    case fallbackReasonUnknown

    var isAIGenerated: Bool {
        switch self {
        case .generatedWithAI, .generatedWithAISupplement:
            return true
        case .appleIntelligenceUnavailable, .generationRequestFailed, .validationFailed, .fallbackReasonUnknown:
            return false
        }
    }

    var developerSummary: String {
        switch self {
        case .generatedWithAI:
            return "Generated with Apple Intelligence"
        case .generatedWithAISupplement:
            return "Generated with Apple Intelligence plus bundled word fallback"
        case .appleIntelligenceUnavailable:
            return "Apple Intelligence not supported or unavailable"
        case .generationRequestFailed:
            return "Apple Intelligence request failed"
        case .validationFailed:
            return "Apple Intelligence output failed validation"
        case .fallbackReasonUnknown:
            return "Fallback reason unavailable for this cached puzzle"
        }
    }
}