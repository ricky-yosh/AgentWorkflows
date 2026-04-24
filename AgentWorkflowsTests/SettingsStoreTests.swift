import Testing
import Foundation
@testable import AgentWorkflows

@Suite("SettingsStore")
struct SettingsStoreTests {

    // MARK: - In-Memory Disk

    final class InMemoryDisk {
        var files: [URL: Data] = [:]
        var writeCounts: [URL: Int] = [:]

        func makeFileSystem() -> AppSettings.FileSystem {
            AppSettings.FileSystem(
                fileExists: { [unowned self] in self.files[$0] != nil },
                readData: { [unowned self] url in
                    guard let data = self.files[url] else { throw CocoaError(.fileNoSuchFile) }
                    return data
                },
                writeAtomically: { [unowned self] data, url in
                    self.files[url] = data
                    self.writeCounts[url, default: 0] += 1
                },
                createDirectory: { _ in }
            )
        }
    }

    let globalURL = URL(string: "mem://settings/global.json")!
    let perRepoURL = URL(string: "mem://settings/per-repo.json")!

    private func makeAppSettings(disk: InMemoryDisk) -> AppSettings {
        AppSettings(globalURL: globalURL, perRepoURL: perRepoURL, fileSystem: disk.makeFileSystem())
    }

    private func makeStore(
        disk: InMemoryDisk,
        scheduler: @escaping SettingsStore.Scheduler = { _, block in block() }
    ) -> SettingsStore {
        SettingsStore(appSettings: makeAppSettings(disk: disk), debounceDelay: 0, scheduler: scheduler)
    }

    // MARK: - Initialization

    @Test func initLoadsEffectiveSettingsFromDisk() throws {
        let disk = InMemoryDisk()
        let stored = Settings(sidebarTitleCLI: .codex, planCLI: .codex, verifyCLI: .codex, buildCLI: .codex)
        disk.files[globalURL] = try JSONEncoder().encode(stored)
        let store = makeStore(disk: disk)
        #expect(store.settings == stored)
    }

    @Test func initFallsBackToDefaultsWhenNoFilesPresent() {
        let disk = InMemoryDisk()
        let store = makeStore(disk: disk)
        #expect(store.settings == .default)
    }

    // MARK: - Observable Updates

    @Test func updateGlobalChangesSettingsImmediately() {
        let disk = InMemoryDisk()
        let store = makeStore(disk: disk)
        let updated = Settings(sidebarTitleCLI: .codex, planCLI: .codex, verifyCLI: .codex, buildCLI: .codex)
        store.updateGlobal(updated)
        #expect(store.settings == updated)
    }

    @Test func updatePerRepoChangesSettingsImmediately() {
        let disk = InMemoryDisk()
        let store = makeStore(disk: disk)
        let perRepo = PerRepoSettings(sidebarTitleCLI: .codex, planCLI: .codex, verifyCLI: .codex, buildCLI: .codex)
        store.updatePerRepo(perRepo)
        let expected = Settings(sidebarTitleCLI: .codex, planCLI: .codex, verifyCLI: .codex, buildCLI: .codex)
        #expect(store.settings == expected)
    }

    // MARK: - Debounced Persistence

    @Test func updateGlobalPersistsAfterSchedulerFires() throws {
        let disk = InMemoryDisk()
        let store = makeStore(disk: disk) // immediate scheduler by default
        let updated = Settings(sidebarTitleCLI: .codex, planCLI: .codex, verifyCLI: .codex, buildCLI: .codex)
        store.updateGlobal(updated)
        let savedData = try #require(disk.files[globalURL])
        let saved = try JSONDecoder().decode(Settings.self, from: savedData)
        #expect(saved == updated)
    }

    @Test func debounceCancelsPriorGlobalWriteOnRapidMutations() throws {
        let disk = InMemoryDisk()
        var capturedBlocks: [() -> Void] = []
        let captureScheduler: SettingsStore.Scheduler = { _, block in capturedBlocks.append(block) }
        let store = makeStore(disk: disk, scheduler: captureScheduler)

        let first = Settings(sidebarTitleCLI: .codex, planCLI: .claude, verifyCLI: .claude, buildCLI: .claude)
        let second = Settings(sidebarTitleCLI: .claude, planCLI: .codex, verifyCLI: .claude, buildCLI: .claude)

        store.updateGlobal(first)
        store.updateGlobal(second)

        capturedBlocks.forEach { $0() }

        #expect(disk.writeCounts[globalURL] == 1)
        let savedData = try #require(disk.files[globalURL])
        let saved = try JSONDecoder().decode(Settings.self, from: savedData)
        #expect(saved == second)
    }

    @Test func updatePerRepoPersistsAfterSchedulerFires() throws {
        let disk = InMemoryDisk()
        let store = makeStore(disk: disk)
        let perRepo = PerRepoSettings(sidebarTitleCLI: .codex, planCLI: .codex, verifyCLI: .codex, buildCLI: .codex)
        store.updatePerRepo(perRepo)
        let savedData = try #require(disk.files[perRepoURL])
        let saved = try JSONDecoder().decode(PerRepoSettings.self, from: savedData)
        #expect(saved == perRepo)
    }

    // MARK: - Per-Repo Partial Inheritance

    @Test func perRepoNilFieldInheritsFromGlobal() {
        let disk = InMemoryDisk()
        let store = makeStore(disk: disk)
        let global = Settings(sidebarTitleCLI: .codex, planCLI: .codex, verifyCLI: .claude, buildCLI: .claude)
        store.updateGlobal(global)
        // Override only buildCLI; sidebarTitleCLI/planCLI/verifyCLI inherit from global
        let perRepo = PerRepoSettings(buildCLI: .claude)
        store.updatePerRepo(perRepo)
        #expect(store.settings.sidebarTitleCLI == .codex)  // inherited
        #expect(store.settings.planCLI == .codex)           // inherited
        #expect(store.settings.verifyCLI == .claude)         // inherited
        #expect(store.settings.buildCLI == .claude)          // per-repo override
    }
}
