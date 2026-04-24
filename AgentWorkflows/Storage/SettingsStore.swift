import Foundation
import Observation

@Observable
final class SettingsStore {

    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

    // MARK: - Observable State

    private(set) var globalSettings: Settings
    private(set) var perRepoSettings: PerRepoSettings?
    private(set) var perRepoURL: URL?

    /// The effective settings: per-repo fields override global, nil per-repo fields inherit global.
    var settings: Settings {
        perRepoSettings?.merged(onto: globalSettings) ?? globalSettings
    }

    var hasActiveSession: Bool { perRepoURL != nil }

    // MARK: - Private

    @ObservationIgnored private var appSettings: AppSettings
    @ObservationIgnored private let debounceDelay: TimeInterval
    @ObservationIgnored private let schedule: Scheduler
    @ObservationIgnored private var pendingGlobal: DispatchWorkItem?
    @ObservationIgnored private var pendingPerRepo: DispatchWorkItem?

    // MARK: - Init

    init(
        appSettings: AppSettings = AppSettings(),
        debounceDelay: TimeInterval = 0.3,
        scheduler: @escaping Scheduler = { delay, block in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
        }
    ) {
        self.appSettings = appSettings
        self.debounceDelay = debounceDelay
        self.schedule = scheduler
        self.perRepoURL = appSettings.perRepoURL
        self.globalSettings = (try? appSettings.loadGlobal()) ?? .default
        self.perRepoSettings = try? appSettings.loadPerRepoPartial()
    }

    // MARK: - Mutations

    func updateGlobal(_ newSettings: Settings) {
        globalSettings = newSettings
        pendingGlobal?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            try? self.appSettings.saveGlobal(newSettings)
        }
        pendingGlobal = item
        schedule(debounceDelay) { item.perform() }
    }

    func updatePerRepo(_ perRepo: PerRepoSettings?) {
        perRepoSettings = perRepo
        pendingPerRepo?.cancel()
        guard let perRepo else { return }
        let snapshot = appSettings
        let item = DispatchWorkItem {
            try? snapshot.savePerRepoPartial(perRepo)
        }
        pendingPerRepo = item
        schedule(debounceDelay) { item.perform() }
    }

    /// Changes the active per-repo URL (call when the selected Session changes).
    /// Immediately reloads per-repo partial settings from the new path.
    func setPerRepoURL(_ url: URL?) {
        perRepoURL = url
        appSettings = AppSettings(
            globalURL: appSettings.globalURL,
            perRepoURL: url,
            fileSystem: appSettings.fileSystem
        )
        perRepoSettings = try? appSettings.loadPerRepoPartial()
    }
}
