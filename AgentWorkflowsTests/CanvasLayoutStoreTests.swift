import Foundation
import Testing
@testable import AgentWorkflows

@Suite("CanvasLayoutStore")
struct CanvasLayoutStoreTests {
    private let baseURL: URL
    private let layoutURL: URL
    private let canvasURL: URL

    init() throws {
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AW-CanvasLayout-\(UUID().uuidString)")
        layoutURL = baseURL.appendingPathComponent("canvas-layout.toml")
        canvasURL = baseURL.appendingPathComponent("canvas.toml")
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: baseURL)
    }

    @Test func writeThenReadPreservesLayout() throws {
        defer { cleanup() }

        let layout = CanvasLayout(
            nodes: [
                CanvasLayoutNode(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, x: -320, y: 0),
                CanvasLayoutNode(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, x: 0, y: 0)
            ],
            reroutes: [
                CanvasRerouteWaypoint(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    connectionFrom: "FeatureViewModel",
                    connectionTo: "APIClient",
                    index: 0,
                    x: -120,
                    y: 64
                )
            ],
            zoom: 1.5,
            panX: 88,
            panY: -42
        )

        let store = CanvasLayoutStore(fileURL: layoutURL, initialLayout: layout)
        try store.save()

        let reread = CanvasLayoutStore(fileURL: layoutURL)
        #expect(reread.layout == layout)
    }

    @Test func autoLayoutPlacesOutskirtsOnRingAndInskirtsAtCenter() {
        let outskirts = [
            UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        ]
        let inskirts = [
            UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        ]

        let layout = CanvasLayout.autoLayout(outskirts: outskirts, inskirts: inskirts)
        let outskirtsNodes = layout.nodes.filter { outskirts.contains($0.id) }
        let inskirtsNodes = layout.nodes.filter { inskirts.contains($0.id) }

        #expect(outskirtsNodes.count == outskirts.count)
        #expect(inskirtsNodes.count == inskirts.count)
        #expect(outskirtsNodes.allSatisfy { hypot($0.x, $0.y) > 250 })
        #expect(inskirtsNodes.allSatisfy { hypot($0.x, $0.y) < 150 })
    }

    @Test func missingLayoutFileUsesProvidedAutoLayout() {
        defer { cleanup() }

        let outskirts = [
            UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        ]
        let inskirts = [
            UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        ]
        let autoLayout = CanvasLayout.autoLayout(outskirts: outskirts, inskirts: inskirts)

        let store = CanvasLayoutStore(fileURL: layoutURL, initialLayout: autoLayout)

        #expect(store.layout == autoLayout)
        #expect(!FileManager.default.fileExists(atPath: layoutURL.path))
    }

    @Test func writingLayoutDoesNotTouchCanvasToml() throws {
        defer { cleanup() }

        try "canvas = true\n".write(to: canvasURL, atomically: true, encoding: .utf8)

        let layout = CanvasLayout(
            nodes: [CanvasLayoutNode(id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!, x: 16, y: 24)],
            reroutes: [],
            zoom: 1,
            panX: 0,
            panY: 0
        )
        let store = CanvasLayoutStore(fileURL: layoutURL, initialLayout: layout)
        try store.save()

        let canvasText = try String(contentsOf: canvasURL, encoding: .utf8)
        #expect(canvasText == "canvas = true\n")
        #expect(!canvasText.contains("99999999-9999-9999-9999-999999999999"))
    }
}
