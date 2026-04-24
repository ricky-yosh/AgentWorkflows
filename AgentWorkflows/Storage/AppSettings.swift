import Foundation

// MARK: - Error

enum AppSettingsError: Error {
    case malformedGlobal(underlying: Error)
    case malformedPerRepo(underlying: Error)
}

// MARK: - AppSettings

/// Pure load, merge, and save for Global and Per-Repo Settings.
/// Stateless — reads from disk on every call to `load()`.
/// All file-system operations are injected so tests never touch real disk.
nonisolated struct AppSettings {

    // MARK: - FileSystem

    struct FileSystem {
        var fileExists: (URL) -> Bool
        var readData: (URL) throws -> Data
        var writeAtomically: (Data, URL) throws -> Void
        var createDirectory: (URL) throws -> Void

        static let live = FileSystem(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            readData: { try Data(contentsOf: $0) },
            writeAtomically: { data, url in try data.write(to: url, options: .atomic) },
            createDirectory: { url in
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        )
    }

    // MARK: - URLs

    static let defaultGlobalURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("AW/settings.json")
    }()

    let globalURL: URL
    let perRepoURL: URL?
    let fileSystem: FileSystem

    init(
        globalURL: URL = defaultGlobalURL,
        perRepoURL: URL? = nil,
        fileSystem: FileSystem = .live
    ) {
        self.globalURL = globalURL
        self.perRepoURL = perRepoURL
        self.fileSystem = fileSystem
    }

    // MARK: - Load

    /// Returns the effective Settings by merging Per-Repo on top of Global.
    /// Missing files fall back to compile-time defaults; malformed JSON surfaces a typed error.
    func load() throws -> Settings {
        let base = try loadGlobal()

        guard let perRepoURL, fileSystem.fileExists(perRepoURL) else {
            return base
        }

        let perRepoPartial = try loadPartial(from: perRepoURL) { AppSettingsError.malformedPerRepo(underlying: $0) }
        return perRepoPartial?.merged(onto: base) ?? base
    }

    /// Returns Global Settings resolved against compile-time defaults.
    func loadGlobal() throws -> Settings {
        let partial = try loadPartial(from: globalURL) { AppSettingsError.malformedGlobal(underlying: $0) }
        return partial?.merged(onto: .default) ?? .default
    }

    /// Returns the raw Per-Repo partial (nil fields = inherit from global), or nil if no file exists.
    func loadPerRepoPartial() throws -> PerRepoSettings? {
        guard let perRepoURL, fileSystem.fileExists(perRepoURL) else { return nil }
        return try loadPartial(from: perRepoURL) { AppSettingsError.malformedPerRepo(underlying: $0) }
    }

    // MARK: - Save

    func saveGlobal(_ settings: Settings) throws {
        try atomicWrite(settings, to: globalURL)
    }

    /// Saves a full Settings value to the per-repo file (all four fields written).
    func savePerRepo(_ settings: Settings) throws {
        guard let url = perRepoURL else { return }
        try atomicWrite(settings, to: url)
    }

    /// Saves a partial Per-Repo Settings value; nil fields are omitted from the JSON file,
    /// so they continue to inherit from Global Settings on next load.
    func savePerRepoPartial(_ perRepo: PerRepoSettings) throws {
        guard let url = perRepoURL else { return }
        try atomicWrite(perRepo, to: url)
    }

    // MARK: - Private

    private func loadPartial(
        from url: URL,
        wrap: (Error) -> AppSettingsError
    ) throws -> PerRepoSettings? {
        guard fileSystem.fileExists(url) else { return nil }
        let data = try fileSystem.readData(url)
        do {
            return try JSONDecoder().decode(PerRepoSettings.self, from: data)
        } catch {
            throw wrap(error)
        }
    }

    private func atomicWrite<T: Encodable>(_ value: T, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try fileSystem.createDirectory(parent)
        let data = try JSONEncoder().encode(value)
        try fileSystem.writeAtomically(data, url)
    }
}
