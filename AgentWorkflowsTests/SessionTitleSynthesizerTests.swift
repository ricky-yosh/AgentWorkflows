import Testing
import Foundation
@testable import AgentWorkflows

// MARK: - Fake backend

private final class FakeTitleBackend: TitleSynthesisBackend {
    var titleToReturn: String = "Refactor Auth Layer"
    var shouldThrow: Bool = false

    func generateTitle(for braindump: String) async throws -> String {
        if shouldThrow { throw TitleSynthesisError.modelUnavailable }
        return titleToReturn
    }
}

@Suite("SessionTitleSynthesizer")
struct SessionTitleSynthesizerTests {

    @Test func happyPathReturnsTitleFromBackend() async {
        let fake = FakeTitleBackend()
        fake.titleToReturn = "Refactor Auth Layer"
        let synthesizer = DefaultSessionTitleSynthesizer(backend: fake)

        let title = await synthesizer.synthesize("I want to refactor the auth layer")
        #expect(title == "Refactor Auth Layer")
    }

    @Test func lengthCapTruncatesLongBackendTitle() async {
        let fake = FakeTitleBackend()
        fake.titleToReturn = "A Very Long Title That Exceeds Forty Characters Easily"
        let synthesizer = DefaultSessionTitleSynthesizer(backend: fake)

        let title = await synthesizer.synthesize("some braindump")
        #expect(title.count <= DefaultSessionTitleSynthesizer.maxLength)
    }

    @Test func fallbackUsedWhenBackendThrows() async {
        let fake = FakeTitleBackend()
        fake.shouldThrow = true
        let synthesizer = DefaultSessionTitleSynthesizer(backend: fake)

        let braindump = "I want to refactor the auth layer"
        let title = await synthesizer.synthesize(braindump)
        #expect(title == String(braindump.prefix(DefaultSessionTitleSynthesizer.maxLength)))
    }

    @Test func fallbackTruncatesLongBraindump() async {
        let fake = FakeTitleBackend()
        fake.shouldThrow = true
        let synthesizer = DefaultSessionTitleSynthesizer(backend: fake)

        let braindump = String(repeating: "x", count: 100)
        let title = await synthesizer.synthesize(braindump)
        #expect(title.count == DefaultSessionTitleSynthesizer.maxLength)
    }

    @Test func fallbackTrimsBraindumpWhitespace() async {
        let fake = FakeTitleBackend()
        fake.shouldThrow = true
        let synthesizer = DefaultSessionTitleSynthesizer(backend: fake)

        let title = await synthesizer.synthesize("  short braindump  ")
        #expect(title == "short braindump")
    }
}

// MARK: - Seed synthesis regression test

private final class SpySynthesizer: SessionTitleSynthesizer {
    private(set) var receivedBraindump: String?
    func synthesize(_ braindump: String) async -> String {
        receivedBraindump = braindump
        return "Spy Title"
    }
}

@Suite("writeSeedAndSynthesizeTitle")
struct WriteSeedAndSynthesizeTitleTests {

    @Test func plainProseSeedInvokesSynthesizer() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeedSynthesisTests-\(UUID().uuidString)")
        let registryURL = base.appendingPathComponent("sessions.json")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let store = SessionStore(registryURL: registryURL, watcherFactory: { FakeStateFileWatcher() })
        let spy = SpySynthesizer()

        await writeSeedAndSynthesizeTitle(
            text: "I want to build a todo app with tags",
            sessionID: UUID(),
            store: store,
            synthesizer: spy
        )

        #expect(spy.receivedBraindump == "I want to build a todo app with tags")
    }
}
