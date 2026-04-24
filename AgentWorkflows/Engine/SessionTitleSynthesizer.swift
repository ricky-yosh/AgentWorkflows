import Foundation
import FoundationModels

// MARK: - Public protocol

/// Converts a braindump string into a short session title (≤40 chars).
/// Always returns — fallback is handled internally.
protocol SessionTitleSynthesizer: AnyObject {
    func synthesize(_ braindump: String) async -> String
}

// MARK: - Injectable backend seam

/// Throws on unavailability or model error; allows test fakes.
protocol TitleSynthesisBackend {
    func generateTitle(for braindump: String) async throws -> String
}

// MARK: - Production synthesizer

final class DefaultSessionTitleSynthesizer: SessionTitleSynthesizer {
    private let backend: any TitleSynthesisBackend
    static let maxLength = 40

    init(backend: (any TitleSynthesisBackend)? = nil) {
        self.backend = backend ?? FoundationModelsTitleBackend()
    }

    func synthesize(_ braindump: String) async -> String {
        let raw: String
        do {
            raw = try await backend.generateTitle(for: braindump)
        } catch {
            raw = fallbackTitle(braindump)
        }
        return String(raw.prefix(Self.maxLength))
    }

    private func fallbackTitle(_ braindump: String) -> String {
        String(braindump.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxLength))
    }
}

// MARK: - FoundationModels production backend

final class FoundationModelsTitleBackend: TitleSynthesisBackend {
    func generateTitle(for braindump: String) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw TitleSynthesisError.modelUnavailable
        }
        let session = LanguageModelSession()
        let prompt = """
            Generate a short session title of at most 40 characters for the following work description. \
            Return only the title text, no quotes or punctuation.

            \(braindump)
            """
        let response = try await session.respond(to: prompt)
        return response.content
    }
}

enum TitleSynthesisError: Error {
    case modelUnavailable
}

// MARK: - Seed synthesis coordinator

/// Writes the seed braindump, synthesizes a title, and renames the session.
/// Store errors are silently discarded; the rename uses manual=false so a
/// prior user-applied rename always takes precedence.
func writeSeedAndSynthesizeTitle(
    text: String,
    sessionID: UUID,
    store: SessionStore,
    synthesizer: any SessionTitleSynthesizer
) async {
    try? store.writeBraindump(sessionID: sessionID, text: text)
    let title = await synthesizer.synthesize(text)
    try? store.rename(sessionID: sessionID, to: title, manual: false)
}

// MARK: - CLI subprocess backend

/// `TitleSynthesisBackend` that spawns `<binary> -p <prompt>` and captures
/// the plain-text response. Binary name comes from `CLIPreset.invocationRecipe`
/// so there is no hardcoded CLI reference here.
final class CLISubprocessTitleBackend: TitleSynthesisBackend {
    private let preset: CLIPreset

    init(preset: CLIPreset) {
        self.preset = preset
    }

    func generateTitle(for braindump: String) async throws -> String {
        guard let recipe = preset.invocationRecipe else {
            throw TitleSynthesisError.modelUnavailable
        }
        let prompt = """
            Generate a short session title of at most 40 characters for the following \
            work description. Return only the title text, no quotes or punctuation.

            \(braindump)
            """
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [recipe.binaryName, "-p", prompt]

            var env = ProcessInfo.processInfo.environment
            let existing = env["PATH"] ?? ""
            let home = NSHomeDirectory()
            let pathPrefix = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = existing.isEmpty ? pathPrefix : "\(pathPrefix):\(existing)"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            let errPipe = Pipe()
            process.standardError = errPipe

            process.terminationHandler = { p in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if p.terminationStatus == 0, let output = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.resume(throwing: TitleSynthesisError.modelUnavailable)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: TitleSynthesisError.modelUnavailable)
            }
        }
    }
}
