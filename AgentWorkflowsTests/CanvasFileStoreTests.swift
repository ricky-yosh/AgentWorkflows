import Foundation
import Testing
@testable import AgentWorkflows

final class FakeCanvasDirectoryWatcher: CanvasDirectoryWatching {
    var onChange: (() -> Void)?
    private(set) var watchedDirectory: URL?
    private(set) var stopped = false

    func watch(directory: URL) {
        watchedDirectory = directory
    }

    func stop() {
        stopped = true
    }

    func simulateChange() {
        onChange?()
    }
}

struct StubCanvasSymbolExtractor: CanvasSymbolExtracting {
    var resultByFileName: [String: CanvasSymbolExtractionResult]
    var defaultResult: CanvasSymbolExtractionResult = .init(pins: [])

    func extractPins(for fileURL: URL) -> CanvasSymbolExtractionResult {
        resultByFileName[fileURL.lastPathComponent] ?? defaultResult
    }
}

@Suite("CanvasFileStore")
struct CanvasFileStoreTests {
    private let baseURL: URL
    private let canvasURL: URL

    init() throws {
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AW-Canvas-\(UUID().uuidString)")
        canvasURL = baseURL.appendingPathComponent("canvas.toml")
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: baseURL)
    }

    @Test func writeThenReadPreservesModel() throws {
        defer { cleanup() }
        let watcher = FakeCanvasDirectoryWatcher()
        let store = CanvasFileStore(
            fileURL: canvasURL,
            symbolExtractor: StubCanvasSymbolExtractor(resultByFileName: [:]),
            watcher: watcher
        )
        let model = WorkbenchModel(
            outskirts: [OutskirtsNode(name: "APIClient", file: "Sources/APIClient.swift", role: "Loads data", pins: ["fetch() -> Void"])],
            inskirts: [InskirtsNode(name: "FeatureViewModel", pattern: "ViewModel", role: "Coordinates", pins: ["load() -> Void"])],
            beachBlankets: [BeachBlanket(name: "Feature", nodes: ["APIClient", "FeatureViewModel"])],
            connections: [Connection(from: "FeatureViewModel", to: "APIClient", type: "calls")]
        )

        try store.save(model)

        let reread = CanvasFileStore(
            fileURL: canvasURL,
            symbolExtractor: StubCanvasSymbolExtractor(resultByFileName: [:]),
            watcher: FakeCanvasDirectoryWatcher()
        )

        #expect(reread.model == model)
    }

    @Test func fileChangeUpdatesModelWithoutManualReload() throws {
        defer { cleanup() }
        let watcher = FakeCanvasDirectoryWatcher()
        _ = try makeCanvasFile(
            model: WorkbenchModel(
                outskirts: [OutskirtsNode(name: "One", file: "One.swift", role: "", pins: ["pin"])],
                inskirts: []
            )
        )

        let store = CanvasFileStore(
            fileURL: canvasURL,
            symbolExtractor: StubCanvasSymbolExtractor(resultByFileName: [:]),
            watcher: watcher
        )

        let updatedModel = WorkbenchModel(
            outskirts: [OutskirtsNode(name: "Two", file: "Two.swift", role: "", pins: ["other"])],
            inskirts: [InskirtsNode(name: "ViewModel", pattern: "ViewModel", role: "", pins: ["load() -> Void"])]
        )
        try writeCanvasFile(updatedModel)

        watcher.simulateChange()

        #expect(store.model == updatedModel)
    }

    @Test func missingPinsTriggerEnrichmentAndWriteBack() throws {
        defer { cleanup() }
        let watcher = FakeCanvasDirectoryWatcher()
        let extractor = StubCanvasSymbolExtractor(resultByFileName: [
            "APIClient.swift": .init(pins: ["fetch() -> Void", "baseURL: URL"])
        ])
        let initial = """
        [[outskirts]]
        name = "APIClient"
        file = "Sources/APIClient.swift"
        role = "Loads data"
        pins = []
        """
        try initial.write(to: canvasURL, atomically: true, encoding: .utf8)

        let store = CanvasFileStore(
            fileURL: canvasURL,
            symbolExtractor: extractor,
            watcher: watcher
        )

        #expect(store.model.outskirts.first?.pins == ["fetch() -> Void", "baseURL: URL"])
        let written = try String(contentsOf: canvasURL, encoding: .utf8)
        #expect(written.contains(#"pins = ["fetch() -> Void", "baseURL: URL"]"#))
    }

    @Test func malformedEntriesAndOrphanConnectionsAreDroppedWithWarning() throws {
        defer { cleanup() }
        let watcher = FakeCanvasDirectoryWatcher()
        let raw = """
        [[outskirts]]
        name = "APIClient"
        file = "Sources/APIClient.swift"
        role = "Loads data"
        pins = ["fetch() -> Void"]

        [[inskirts]]
        name = "FeatureViewModel"
        role = "Missing pattern"
        pins = ["load() -> Void"]

        [[connections]]
        from = "FeatureViewModel"
        to = "MissingNode"
        type = "calls"
        """
        try raw.write(to: canvasURL, atomically: true, encoding: .utf8)

        let store = CanvasFileStore(
            fileURL: canvasURL,
            symbolExtractor: StubCanvasSymbolExtractor(resultByFileName: [:]),
            watcher: watcher
        )

        #expect(store.model.outskirts.count == 1)
        #expect(store.model.inskirts.isEmpty)
        #expect(store.model.connections.isEmpty)
        #expect(store.warningPayload?.isEmpty == false)
    }

    @Test func concurrentOutOfBandWriteIsPreservedOnSave() throws {
        defer { cleanup() }
        let watcher = FakeCanvasDirectoryWatcher()
        let store = CanvasFileStore(
            fileURL: canvasURL,
            symbolExtractor: StubCanvasSymbolExtractor(resultByFileName: [:]),
            watcher: watcher
        )

        let external = WorkbenchModel(
            outskirts: [OutskirtsNode(name: "External", file: "External.swift", role: "", pins: ["external() -> Void"])]
        )
        try writeCanvasFile(external)

        let local = WorkbenchModel(
            inskirts: [InskirtsNode(name: "Local", pattern: "Service", role: "", pins: ["run() -> Void"])]
        )
        try store.save(local)

        let saved = CanvasFileStore(
            fileURL: canvasURL,
            symbolExtractor: StubCanvasSymbolExtractor(resultByFileName: [:]),
            watcher: FakeCanvasDirectoryWatcher()
        )

        #expect(saved.model.outskirts.contains(where: { $0.name == "External" }))
        #expect(saved.model.inskirts.contains(where: { $0.name == "Local" }))
    }

    private func makeCanvasFile(model: WorkbenchModel) throws -> URL {
        try writeCanvasFile(model)
        return canvasURL
    }

    private func writeCanvasFile(_ model: WorkbenchModel) throws {
        try model.canvasSerialization.write(to: canvasURL, atomically: true, encoding: .utf8)
    }
}
