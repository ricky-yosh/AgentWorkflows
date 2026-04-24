import Foundation

nonisolated struct SessionRegistryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var workingDirectory: String
    var workflowName: String
}

enum SessionRegistryError: Error {
    case malformedJSON(underlying: Error)
}

/// Owns the sessions.json pointer file. Stateless between calls — reads the file
/// on each mutating operation to avoid stale-in-memory divergence.
nonisolated struct SessionRegistry {

    let fileURL: URL

    static let defaultFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("AW/sessions.json")
    }()

    init(fileURL: URL = defaultFileURL) {
        self.fileURL = fileURL
    }

    // MARK: - Load

    /// Returns all entries, or an empty array when the file does not yet exist.
    /// Throws `SessionRegistryError.malformedJSON` when the file exists but cannot be decoded.
    func load() throws -> [SessionRegistryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONDecoder().decode([SessionRegistryEntry].self, from: data)
        } catch {
            throw SessionRegistryError.malformedJSON(underlying: error)
        }
    }

    // MARK: - Mutations

    func add(_ entry: SessionRegistryEntry) throws {
        var entries = try load()
        entries.append(entry)
        try atomicWrite(entries)
    }

    func remove(id: UUID) throws {
        var entries = try load()
        entries.removeAll(where: { $0.id == id })
        try atomicWrite(entries)
    }

    func rename(id: UUID, to newName: String) throws {
        var entries = try load()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].name = newName
        try atomicWrite(entries)
    }

    func relocate(id: UUID, to newWorkingDirectory: String) throws {
        var entries = try load()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].workingDirectory = newWorkingDirectory
        try atomicWrite(entries)
    }

    // MARK: - Private

    private func atomicWrite(_ entries: [SessionRegistryEntry]) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
