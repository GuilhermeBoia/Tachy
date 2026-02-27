import Foundation

enum DictationError: LocalizedError {
    case missingAPIKey(String)
    case networkError(String)
    case apiError(String)
    case recordingError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let msg): return msg
        case .networkError(let msg): return msg
        case .apiError(let msg): return msg
        case .recordingError(let msg): return msg
        }
    }
}
