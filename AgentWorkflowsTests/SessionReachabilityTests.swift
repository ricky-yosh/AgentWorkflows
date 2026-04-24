import Testing
import Foundation
@testable import AgentWorkflows

@Suite("SessionReachability")
struct SessionReachabilityTests {

    private func makeEntry(workingDirectory: String) -> SessionRegistryEntry {
        SessionRegistryEntry(
            id: UUID(), name: "S", workingDirectory: workingDirectory, workflowName: "ralph"
        )
    }

    // MARK: - Injected probe (no disk I/O)

    @Test func reachableWhenProbeReturnsTrue() {
        let reachability = SessionReachability(isDirectory: { _ in true })
        let entry = makeEntry(workingDirectory: "/any/path")
        #expect(reachability.classify(entry: entry) == .reachable)
    }

    @Test func missingWhenProbeReturnsFalseForAbsentPath() {
        let reachability = SessionReachability(isDirectory: { _ in false })
        let entry = makeEntry(workingDirectory: "/nonexistent/path")
        #expect(reachability.classify(entry: entry) == .missing)
    }

    @Test func missingWhenProbeReturnsFalseForFilePath() {
        let reachability = SessionReachability(isDirectory: { _ in false })
        let entry = makeEntry(workingDirectory: "/some/file.txt")
        #expect(reachability.classify(entry: entry) == .missing)
    }

    @Test func probeReceivesWorkingDirectoryPath() {
        var probedPath: String?
        let reachability = SessionReachability(isDirectory: { path in
            probedPath = path
            return true
        })
        let entry = makeEntry(workingDirectory: "/expected/path")
        _ = reachability.classify(entry: entry)
        #expect(probedPath == "/expected/path")
    }

    // MARK: - Live probe against real disk

    @Test func liveReachableWhenDirectoryExists() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionReachabilityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let entry = makeEntry(workingDirectory: tmpDir.path)
        #expect(SessionReachability.live.classify(entry: entry) == .reachable)
    }

    @Test func liveMissingWhenPathAbsent() {
        let entry = makeEntry(workingDirectory: "/nonexistent-\(UUID().uuidString)/path")
        #expect(SessionReachability.live.classify(entry: entry) == .missing)
    }

    @Test func liveMissingWhenPathIsFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionReachabilityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("not-a-dir.txt")
        try Data().write(to: fileURL)

        let entry = makeEntry(workingDirectory: fileURL.path)
        #expect(SessionReachability.live.classify(entry: entry) == .missing)
    }
}
