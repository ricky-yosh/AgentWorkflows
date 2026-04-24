import Foundation

// MARK: - Errors

enum DigestError: LocalizedError, Equatable {
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Add your key to the tool definition or set ANTHROPIC_API_KEY."
        case .invalidResponse:
            return "Received an invalid response."
        case .apiError(let msg):
            return "API error: \(msg)"
        case .notImplemented(let name):
            return "\(name) provider is not yet implemented."
        }
    }
}

// MARK: - Streaming stub (not yet implemented)

protocol DigestStreamingProvider {
    func generateDigestStream(content: String, promptTemplate: String) -> AsyncThrowingStream<String, Error>
}

// MARK: - DigestService

/// Dispatches digest generation. The Tool registry has been removed; the
/// implementation currently always throws `.notImplemented` and will be
/// replaced by a progress-log surface in a later task.
enum DigestService {
    static func generate(
        content: String,
        promptTemplate: String,
        tool: CLIToolDefinition
    ) async throws -> String {
        _ = promptTemplate.replacingOccurrences(of: "{content}", with: content)
        _ = tool
        throw DigestError.notImplemented("CLI tools cannot generate digests")
    }
}
