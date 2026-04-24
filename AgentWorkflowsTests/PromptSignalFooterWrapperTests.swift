import Foundation
import Testing
@testable import AgentWorkflows

@Suite("PromptSignalFooterWrapper")
struct PromptSignalFooterWrapperTests {

    private let progress = "/sessions/abc/.aw-cache/ralph"
    private let sessionId = "11111111-2222-3333-4444-555555555555"

    /// One snapshot per intended bundled prompt (task #9 ships these six).
    /// Bodies are short stand-ins for the real Skill SKILL.md content; the
    /// snapshot asserts the wrapper appends a footer that names the Signal
    /// path the engine watches, not the prose of the Skill itself.
    private static let bundledBodies: [(name: String, body: String)] = [
        ("grill-me", "# Grill Me\n\nInterview the user until requirements are clear."),
        ("ubiquitous-language", "# Ubiquitous Language\n\nExtract a glossary."),
        ("to-prd", "# To PRD\n\nWrite the PRD to PRD.md."),
        ("prd-to-tasks", "# PRD to Tasks\n\nDecompose PRD.md into tasks.json."),
        ("ralph", "# Ralph\n\nRun one iteration of the loop."),
        ("qa", "# QA\n\nInteractive QA session.")
    ]

    @Test("each bundled prompt body gets the Signal-file footer appended",
          arguments: bundledBodies)
    func snapshotPerBundledPrompt(arg: (name: String, body: String)) throws {
        let wrapped = try PromptSignalFooterWrapper.wrap(
            promptBody: arg.body,
            progressPath: progress,
            sessionId: sessionId
        )

        #expect(wrapped.hasPrefix(arg.body))
        #expect(wrapped.contains("\(progress)/step-complete-\(sessionId)"))
        #expect(wrapped.contains("AgentWorkflows engine"))
        // Body and footer must be separated by a blank line so prompt readers
        // don't see the footer glued onto the body's last line.
        #expect(wrapped.contains("\n\n"))
    }

    @Test func emptyBodyReturnsFooterOnly() throws {
        let wrapped = try PromptSignalFooterWrapper.wrap(
            promptBody: "",
            progressPath: progress,
            sessionId: sessionId
        )
        #expect(wrapped.contains("\(progress)/step-complete-\(sessionId)"))
    }

    @Test func bodyWithTrailingNewlineDoesNotProduceTripleBlankLine() throws {
        let wrapped = try PromptSignalFooterWrapper.wrap(
            promptBody: "body line\n",
            progressPath: progress,
            sessionId: sessionId
        )
        #expect(!wrapped.contains("\n\n\n"))
    }

    @Test func emptyProgressPathThrows() {
        #expect(throws: PromptSignalFooterWrapper.WrapError.emptyProgressPath) {
            _ = try PromptSignalFooterWrapper.wrap(
                promptBody: "body",
                progressPath: "",
                sessionId: sessionId
            )
        }
    }

    @Test func emptySessionIdThrows() {
        #expect(throws: PromptSignalFooterWrapper.WrapError.emptySessionId) {
            _ = try PromptSignalFooterWrapper.wrap(
                promptBody: "body",
                progressPath: progress,
                sessionId: ""
            )
        }
    }
}
