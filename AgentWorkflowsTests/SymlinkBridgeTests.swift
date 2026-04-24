import Testing
import Foundation
@testable import AgentWorkflows

// MARK: - TemplateResolver Tests

/// Tests for {progress-path} and {signal-path} template variable resolution in prompts.
/// Paths are now UUID-based: .aw-cache/{sessionID}/ instead of .aw-cache/{symlinkName}/.
struct TemplateResolverTests {

    // MARK: - {progress-path} Resolution

    @Test func resolvesProgressPathVariable() {
        let sessionID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let resolver = TemplateResolver(sessionID: sessionID)

        let result = resolver.resolve("Save output to {progress-path}")
        #expect(result == "Save output to .aw-cache/12345678-1234-1234-1234-123456789ABC")
    }

    @Test func resolvesProgressPathVariableInMiddleOfText() {
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let resolver = TemplateResolver(sessionID: sessionID)

        let result = resolver.resolve("Read {progress-path}/tasks.json and process")
        #expect(result == "Read .aw-cache/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/tasks.json and process")
    }

    // MARK: - {signal-path} Resolution

    @Test func resolvesSignalPathVariable() {
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let resolver = TemplateResolver(sessionID: sessionID)

        let result = resolver.resolve("Touch {signal-path} when done")
        #expect(result == "Touch .aw-cache/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/step-complete-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE when done")
    }

    // MARK: - Combined Variables

    @Test func resolvesBothVariablesInSameString() {
        let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let resolver = TemplateResolver(sessionID: sessionID)

        let result = resolver.resolve("Write to {progress-path}/output.txt then touch {signal-path}")
        #expect(result == "Write to .aw-cache/11111111-2222-3333-4444-555555555555/output.txt then touch .aw-cache/11111111-2222-3333-4444-555555555555/step-complete-11111111-2222-3333-4444-555555555555")
    }

    @Test func resolvesMultipleOccurrencesOfSameVariable() {
        let sessionID = UUID(uuidString: "ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB")!
        let resolver = TemplateResolver(sessionID: sessionID)

        let result = resolver.resolve("{progress-path}/a.txt and {progress-path}/b.txt")
        #expect(result == ".aw-cache/ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB/a.txt and .aw-cache/ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB/b.txt")
    }

    // MARK: - No Variables

    @Test func textWithNoVariablesIsUnchanged() {
        let resolver = TemplateResolver(sessionID: UUID())

        let result = resolver.resolve("Just a plain prompt with no variables")
        #expect(result == "Just a plain prompt with no variables")
    }

    @Test func emptyStringReturnsEmpty() {
        let resolver = TemplateResolver(sessionID: UUID())

        let result = resolver.resolve("")
        #expect(result == "")
    }

    @Test func slashCommandPassesThroughVerbatim() {
        let resolver = TemplateResolver(sessionID: UUID())

        let result = resolver.resolve("/gf-save-progress")
        #expect(result == "/gf-save-progress")
    }

    // MARK: - Partial / Invalid Variables

    @Test func partialVariableNameIsNotReplaced() {
        let sessionID = UUID(uuidString: "ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB")!
        let resolver = TemplateResolver(sessionID: sessionID)

        let result = resolver.resolve("{progress} is not {progress-path}")
        #expect(result == "{progress} is not .aw-cache/ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB")
    }

    @Test func oldProgressVariableIsNotReplaced() {
        let resolver = TemplateResolver(sessionID: UUID())

        let result = resolver.resolve("{progress}")
        #expect(result == "{progress}")
    }

    @Test func oldSignalVariableIsNotReplaced() {
        let resolver = TemplateResolver(sessionID: UUID())

        let result = resolver.resolve("{signal}")
        #expect(result == "{signal}")
    }

    @Test func unknownVariablesAreNotReplaced() {
        let resolver = TemplateResolver(sessionID: UUID())

        let result = resolver.resolve("{unknown} stays as-is")
        #expect(result == "{unknown} stays as-is")
    }

    @Test func bracesWithoutVariableNameAreNotReplaced() {
        let resolver = TemplateResolver(sessionID: UUID())

        let result = resolver.resolve("{} and { } are not variables")
        #expect(result == "{} and { } are not variables")
    }

    // MARK: - Signal File Path Format

    @Test func signalFilePathIncludesSessionUUID() {
        let sessionID = UUID(uuidString: "12345678-ABCD-EF01-2345-6789ABCDEF01")!
        let resolver = TemplateResolver(sessionID: sessionID)

        let result = resolver.resolve("{signal-path}")
        #expect(result == ".aw-cache/12345678-ABCD-EF01-2345-6789ABCDEF01/step-complete-12345678-ABCD-EF01-2345-6789ABCDEF01")
    }

    @Test func signalFilePathUsesUppercasedUUID() {
        let sessionID = UUID(uuidString: "abcdefab-cdef-abcd-efab-cdefabcdefab")!
        let resolver = TemplateResolver(sessionID: sessionID)

        let result = resolver.resolve("{signal-path}")
        #expect(result == ".aw-cache/ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB/step-complete-ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB")
    }

    @Test func progressPathMatchesSessionDirectoryLayout() {
        let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let resolver = TemplateResolver(sessionID: sessionID)
        let workingDir = URL(fileURLWithPath: "/some/repo")

        let resolvedPath = resolver.resolve("{progress-path}")
        let layoutPath = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: workingDir,
            sessionID: sessionID
        ).relativePath(from: workingDir)

        #expect(resolvedPath == ".aw-cache/11111111-2222-3333-4444-555555555555")
        #expect(layoutPath == ".aw-cache/11111111-2222-3333-4444-555555555555")
    }
}

// MARK: - URL helpers for relative paths

private extension URL {
    func relativePath(from base: URL) -> String {
        let basePath = base.path
        let selfPath = self.path
        guard selfPath.hasPrefix(basePath) else { return selfPath }
        let relative = selfPath.dropFirst(basePath.count)
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : String(relative)
    }
}
