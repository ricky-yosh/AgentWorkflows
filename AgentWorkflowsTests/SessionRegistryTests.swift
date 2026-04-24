import Testing
import Foundation
@testable import AgentWorkflows

@Suite("SessionRegistry")
struct SessionRegistryTests {

    private func makeRegistry() throws -> (SessionRegistry, URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionRegistryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let fileURL = tmpDir.appendingPathComponent("sessions.json")
        return (SessionRegistry(fileURL: fileURL), tmpDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Load

    @Test func loadReturnsEmptyArrayWhenFileAbsent() throws {
        let (registry, tmpDir) = try makeRegistry()
        defer { cleanup(tmpDir) }
        let entries = try registry.load()
        #expect(entries.isEmpty)
    }

    @Test func loadThrowsMalformedJSONErrorOnCorruptFile() throws {
        let (registry, tmpDir) = try makeRegistry()
        defer { cleanup(tmpDir) }
        try Data("not valid json {{{".utf8).write(to: registry.fileURL)
        #expect(throws: SessionRegistryError.self) {
            _ = try registry.load()
        }
    }

    // MARK: - Add

    @Test func addProducesEntry() throws {
        let (registry, tmpDir) = try makeRegistry()
        defer { cleanup(tmpDir) }
        let entry = SessionRegistryEntry(
            id: UUID(), name: "My Session",
            workingDirectory: "/repos/project", workflowName: "ralph"
        )
        try registry.add(entry)
        let loaded = try registry.load()
        #expect(loaded == [entry])
    }

    @Test func addAccumulatesMultipleEntries() throws {
        let (registry, tmpDir) = try makeRegistry()
        defer { cleanup(tmpDir) }
        let e1 = SessionRegistryEntry(id: UUID(), name: "A", workingDirectory: "/a", workflowName: "ralph")
        let e2 = SessionRegistryEntry(id: UUID(), name: "B", workingDirectory: "/b", workflowName: "ralph")
        try registry.add(e1)
        try registry.add(e2)
        let loaded = try registry.load()
        #expect(loaded.count == 2)
        #expect(loaded.contains(e1))
        #expect(loaded.contains(e2))
    }

    @Test func addThrowsWhenExistingFileIsCorrupt() throws {
        let (registry, tmpDir) = try makeRegistry()
        defer { cleanup(tmpDir) }
        // Pre-corrupt the file so add() fails on load()
        try Data("corrupt".utf8).write(to: registry.fileURL)
        let entry = SessionRegistryEntry(id: UUID(), name: "X", workingDirectory: "/x", workflowName: "ralph")
        #expect(throws: SessionRegistryError.self) {
            try registry.add(entry)
        }
    }

    // MARK: - Remove

    @Test func removeDeletesMatchingEntry() throws {
        let (registry, tmpDir) = try makeRegistry()
        defer { cleanup(tmpDir) }
        let id = UUID()
        let entry = SessionRegistryEntry(id: id, name: "S", workingDirectory: "/p", workflowName: "ralph")
        try registry.add(entry)
        try registry.remove(id: id)
        let loaded = try registry.load()
        #expect(loaded.isEmpty)
    }

    @Test func removeIsNoOpForUnknownID() throws {
        let (registry, tmpDir) = try makeRegistry()
        defer { cleanup(tmpDir) }
        let entry = SessionRegistryEntry(id: UUID(), name: "S", workingDirectory: "/p", workflowName: "ralph")
        try registry.add(entry)
        try registry.remove(id: UUID())
        let loaded = try registry.load()
        #expect(loaded == [entry])
    }

    // MARK: - Rename

    @Test func renameChangesNameOnly() throws {
        let (registry, tmpDir) = try makeRegistry()
        defer { cleanup(tmpDir) }
        let id = UUID()
        let entry = SessionRegistryEntry(id: id, name: "Old", workingDirectory: "/repos/p", workflowName: "ralph")
        try registry.add(entry)
        try registry.rename(id: id, to: "New")
        let loaded = try registry.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "New")
        #expect(loaded[0].workingDirectory == "/repos/p")
        #expect(loaded[0].workflowName == "ralph")
        #expect(loaded[0].id == id)
    }

    @Test func renameIsNoOpForUnknownID() throws {
        let (registry, tmpDir) = try makeRegistry()
        defer { cleanup(tmpDir) }
        let entry = SessionRegistryEntry(id: UUID(), name: "Same", workingDirectory: "/p", workflowName: "ralph")
        try registry.add(entry)
        try registry.rename(id: UUID(), to: "Changed")
        let loaded = try registry.load()
        #expect(loaded[0].name == "Same")
    }

    // MARK: - Relocate

    @Test func relocateChangesWorkingDirectoryOnly() throws {
        let (registry, tmpDir) = try makeRegistry()
        defer { cleanup(tmpDir) }
        let id = UUID()
        let entry = SessionRegistryEntry(id: id, name: "S", workingDirectory: "/old", workflowName: "ralph")
        try registry.add(entry)
        try registry.relocate(id: id, to: "/new")
        let loaded = try registry.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].workingDirectory == "/new")
        #expect(loaded[0].name == "S")
        #expect(loaded[0].workflowName == "ralph")
        #expect(loaded[0].id == id)
    }

    @Test func relocateIsNoOpForUnknownID() throws {
        let (registry, tmpDir) = try makeRegistry()
        defer { cleanup(tmpDir) }
        let entry = SessionRegistryEntry(id: UUID(), name: "S", workingDirectory: "/original", workflowName: "ralph")
        try registry.add(entry)
        try registry.relocate(id: UUID(), to: "/different")
        let loaded = try registry.load()
        #expect(loaded[0].workingDirectory == "/original")
    }

    // MARK: - Atomic write

    @Test func atomicWriteCreatesParentDirectoryIfAbsent() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionRegistryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        // Parent dir does not exist yet
        let nested = tmpDir.appendingPathComponent("AW/sessions.json")
        let registry = SessionRegistry(fileURL: nested)
        let entry = SessionRegistryEntry(id: UUID(), name: "S", workingDirectory: "/p", workflowName: "ralph")
        try registry.add(entry)
        let loaded = try registry.load()
        #expect(loaded.count == 1)
    }

    @Test func atomicWriteLeavesNoTempFilesAfterSuccessfulWrite() throws {
        let (registry, tmpDir) = try makeRegistry()
        defer { cleanup(tmpDir) }
        let entry = SessionRegistryEntry(id: UUID(), name: "S", workingDirectory: "/p", workflowName: "ralph")
        try registry.add(entry)
        let parent = registry.fileURL.deletingLastPathComponent()
        let contents = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        let tempFiles = contents.filter { $0.hasSuffix(".sessions-tmp") }
        #expect(tempFiles.isEmpty)
    }
}
