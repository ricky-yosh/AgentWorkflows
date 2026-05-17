import Testing
import Foundation
@testable import AgentWorkflows

@Suite("AppSettings")
struct AppSettingsTests {

    // MARK: - In-Memory File System

    final class InMemoryStore {
        var files: [URL: Data] = [:]

        func makeFileSystem() -> AppSettings.FileSystem {
            AppSettings.FileSystem(
                fileExists: { [unowned self] in self.files[$0] != nil },
                readData: { [unowned self] url in
                    guard let data = self.files[url] else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    return data
                },
                writeAtomically: { [unowned self] data, url in self.files[url] = data },
                createDirectory: { _ in }
            )
        }
    }

    // MARK: - Fixture URLs

    let globalURL = URL(string: "mem://settings/global.json")!
    let perRepoURL = URL(string: "mem://settings/per-repo.json")!

    private func encode(_ settings: Settings) -> Data {
        try! JSONEncoder().encode(settings)
    }

    private func makeAppSettings(store: InMemoryStore, includePerRepo: Bool = true) -> AppSettings {
        AppSettings(
            globalURL: globalURL,
            perRepoURL: includePerRepo ? perRepoURL : nil,
            fileSystem: store.makeFileSystem()
        )
    }

    // MARK: - Load: neither present

    @Test func neitherPresentReturnsDefaults() throws {
        let store = InMemoryStore()
        let appSettings = makeAppSettings(store: store)
        let settings = try appSettings.load()
        #expect(settings == .default)
    }

    // MARK: - Load: only global present

    @Test func onlyGlobalPresentUsesGlobal() throws {
        let store = InMemoryStore()
        // Global JSON omits sidebarTitleCLI — tests that missing fields fall back to compile-time default
        let json = #"{"planCLI":"codex","verifyCLI":"codex","buildCLI":"codex"}"#
        store.files[globalURL] = Data(json.utf8)
        let appSettings = makeAppSettings(store: store)
        let settings = try appSettings.load()
        #expect(settings.sidebarTitleCLI == .claude) // missing field → compile-time default
        #expect(settings.planCLI == .codex)
        #expect(settings.verifyCLI == .codex)
        #expect(settings.buildCLI == .codex)
    }

    // MARK: - Load: only per-repo present

    @Test func onlyPerRepoPresentMergesOntoDefaults() throws {
        let store = InMemoryStore()
        let json = #"{"buildCLI":"codex"}"#
        store.files[perRepoURL] = Data(json.utf8)
        let appSettings = makeAppSettings(store: store)
        let settings = try appSettings.load()
        // Non-overridden fields fall back to compile-time defaults
        #expect(settings.sidebarTitleCLI == .claude)
        #expect(settings.planCLI == .claude)
        #expect(settings.verifyCLI == .claude)
        // Overridden field comes from per-repo
        #expect(settings.buildCLI == .codex)
    }

    // MARK: - Load: both present (field-by-field merge)

    @Test func bothPresentPerRepoOverridesGlobalFieldByField() throws {
        let store = InMemoryStore()
        // Global sets planCLI to codex
        let globalJSON = #"{"planCLI":"codex"}"#
        store.files[globalURL] = Data(globalJSON.utf8)
        // Per-repo overrides only buildCLI
        let perRepoJSON = #"{"buildCLI":"codex"}"#
        store.files[perRepoURL] = Data(perRepoJSON.utf8)
        let appSettings = makeAppSettings(store: store)
        let settings = try appSettings.load()
        #expect(settings.sidebarTitleCLI == .claude)   // default (neither set)
        #expect(settings.planCLI == .codex)            // from global
        #expect(settings.verifyCLI == .claude)          // default (neither set)
        #expect(settings.buildCLI == .codex)            // from per-repo
    }

    @Test func piValuesLoadFromGlobalAndPerRepo() throws {
        let store = InMemoryStore()
        let globalJSON = #"{"sidebarTitleProvider":"pi","planCLI":"pi","verifyCLI":"claude","buildCLI":"claude"}"#
        store.files[globalURL] = Data(globalJSON.utf8)
        let perRepoJSON = #"{"verifyCLI":"pi","buildCLI":"pi"}"#
        store.files[perRepoURL] = Data(perRepoJSON.utf8)
        let appSettings = makeAppSettings(store: store)
        let settings = try appSettings.load()

        #expect(settings.sidebarTitleProvider == .pi)
        #expect(settings.planCLI == .pi)
        #expect(settings.verifyCLI == .pi)
        #expect(settings.buildCLI == .pi)
    }

    // MARK: - Load: malformed JSON

    @Test func malformedGlobalThrowsMalformedGlobalError() throws {
        let store = InMemoryStore()
        store.files[globalURL] = Data("not valid json {{{".utf8)
        let appSettings = makeAppSettings(store: store, includePerRepo: false)
        #expect {
            _ = try appSettings.load()
        } throws: { error in
            guard let appError = error as? AppSettingsError,
                  case .malformedGlobal = appError else { return false }
            return true
        }
    }

    @Test func malformedPerRepoThrowsMalformedPerRepoError() throws {
        let store = InMemoryStore()
        store.files[globalURL] = encode(.default)
        store.files[perRepoURL] = Data("not valid json {{{".utf8)
        let appSettings = makeAppSettings(store: store)
        #expect {
            _ = try appSettings.load()
        } throws: { error in
            guard let appError = error as? AppSettingsError,
                  case .malformedPerRepo = appError else { return false }
            return true
        }
    }

    // MARK: - Save: atomic write round-trip

    @Test func saveGlobalRoundTrips() throws {
        let store = InMemoryStore()
        let appSettings = makeAppSettings(store: store, includePerRepo: false)
        try appSettings.saveGlobal(.default)
        let loaded = try appSettings.load()
        #expect(loaded == .default)
    }

    @Test func savePerRepoRoundTrips() throws {
        let store = InMemoryStore()
        store.files[globalURL] = encode(.default)
        let appSettings = makeAppSettings(store: store)
        // Write a non-default per-repo (all fields present, so per-repo fully replaces base)
        let perRepo = Settings(sidebarTitleCLI: .codex, planCLI: .codex, verifyCLI: .codex, buildCLI: .codex)
        try appSettings.savePerRepo(perRepo)
        let loaded = try appSettings.load()
        #expect(loaded == perRepo)
    }
}
