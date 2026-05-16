import Foundation
import CoreGraphics
import Testing
@testable import AgentWorkflows

@Suite("Workbench canvas helpers")
struct WorkbenchCanvasViewTests {

    @Test func classifyPinsSplitsPropertiesAndMethodsInOrder() {
        let pins = [
            "title: String",
            "load() -> Void",
            "state: State",
            "reload(animated: Bool) -> Void"
        ]

        let classified = CanvasNodePresentationFactory.classifyPins(pins)

        #expect(classified.properties == ["title: String", "state: State"])
        #expect(classified.methods == ["load() -> Void", "reload(animated: Bool) -> Void"])
    }

    @Test func accentTokensMapKnownPatternsAndUnknownToGrey() {
        #expect(CanvasNodePresentationFactory.accentToken(forPattern: "Observer") == .observer)
        #expect(CanvasNodePresentationFactory.accentToken(forPattern: "Repository") == .repository)
        #expect(CanvasNodePresentationFactory.accentToken(forPattern: "Service") == .service)
        #expect(CanvasNodePresentationFactory.accentToken(forPattern: "Custom") == .unknown)
        #expect(CanvasNodePresentationFactory.accentToken(forPattern: nil) == .unknown)
    }

    @Test func estimatedCardSizeClampsWithinExpectedRange() {
        let presentation = CanvasNodePresentation(
            id: "inskirts:FeatureViewModel",
            kind: .inskirts,
            kindLabel: "ViewModel",
            name: "FeatureViewModel",
            filePath: nil,
            role: "",
            pattern: "ViewModel",
            properties: ["state: State"],
            methods: ["load(animated: Bool) -> Void", "refresh() -> Void"]
        )

        let size = CanvasNodePresentationFactory.estimatedSize(for: presentation)

        #expect(size.width >= 120)
        #expect(size.width <= 300)
        #expect(size.height >= 180)
    }

    @Test func presentationsPreserveCardMetadataForCanvasRendering() {
        let model = WorkbenchModel(
            outskirts: [
                OutskirtsNode(
                    name: "APIClient",
                    file: "Sources/APIClient.swift",
                    role: "Loads data",
                    pins: ["fetch() -> Void", "baseURL: URL"]
                )
            ],
            inskirts: [
                InskirtsNode(
                    name: "FeatureViewModel",
                    pattern: "ViewModel",
                    role: "Coordinates state",
                    pins: ["state: State", "load() -> Void"]
                )
            ]
        )

        let presentations = CanvasNodePresentationFactory.presentations(for: model)

        #expect(presentations.count == 2)
        #expect(presentations[0].kind == .inskirts)
        #expect(presentations[0].kindLabel == "ViewModel")
        #expect(presentations[0].filePath == nil)
        #expect(presentations[0].properties == ["state: State"])
        #expect(presentations[0].methods == ["load() -> Void"])

        #expect(presentations[1].kind == .outskirts)
        #expect(presentations[1].kindLabel == "Outskirts")
        #expect(presentations[1].filePath == "Sources/APIClient.swift")
        #expect(presentations[1].properties == ["baseURL: URL"])
        #expect(presentations[1].methods == ["fetch() -> Void"])
    }

    @Test func zoomClampKeepsCanvasWithinAllowedRange() {
        #expect(CanvasNodeLayoutPlanner.clampedZoom(0.1) == 0.25)
        #expect(CanvasNodeLayoutPlanner.clampedZoom(1.0) == 1.0)
        #expect(CanvasNodeLayoutPlanner.clampedZoom(5.0) == 4.0)
    }

    @Test func fitTransformCentersBoundsAndClampsZoom() {
        let model = WorkbenchModel(
            outskirts: [
                OutskirtsNode(name: "APIClient", file: "Sources/APIClient.swift", role: "", pins: ["fetch() -> Void"])
            ],
            inskirts: [
                InskirtsNode(name: "FeatureViewModel", pattern: "ViewModel", role: "", pins: ["load() -> Void"])
            ]
        )
        let placements = CanvasNodeLayoutPlanner.placements(
            for: CanvasNodePresentationFactory.presentations(for: model)
        )

        let transform = CanvasNodeLayoutPlanner.fitTransform(
            for: placements,
            in: CGSize(width: 1440, height: 900)
        )

        #expect(transform.zoom >= 0.25)
        #expect(transform.zoom <= 4)
        #expect(transform.pan != .zero)
    }

    @Test func pinGeometryKeepsInputsLeftAndOutputsRight() {
        let presentation = CanvasNodePresentation(
            id: "inskirts:Coordinator",
            kind: .inskirts,
            kindLabel: "Coordinator",
            name: "FeatureCoordinator",
            filePath: nil,
            role: "",
            pattern: "Coordinator",
            properties: ["state: State", "service: Service"],
            methods: ["start() -> Void", "stop() -> Void"]
        )
        let placement = CanvasNodePlacement(
            id: presentation.id,
            presentation: presentation,
            worldPosition: .zero,
            size: CanvasNodePresentationFactory.estimatedSize(for: presentation)
        )

        let hits = CanvasPinGeometry.hits(
            for: placement,
            presentation: presentation,
            zoom: 1,
            pan: .zero,
            canvasSize: CGSize(width: 1000, height: 800)
        )
        let input = hits.first { $0.reference.role == .input }
        let output = hits.first { $0.reference.role == .output }

        #expect(input != nil)
        #expect(output != nil)
        #expect(input!.center.x < output!.center.x)
    }

    @Test func patternBasedConnectionSuggestionUsesKnownRules() {
        let source = CanvasNodePresentation(
            id: "inskirts:Coordinator",
            kind: .inskirts,
            kindLabel: "Coordinator",
            name: "FeatureCoordinator",
            filePath: nil,
            role: "",
            pattern: "Coordinator",
            properties: [],
            methods: []
        )
        let destination = CanvasNodePresentation(
            id: "inskirts:Service",
            kind: .inskirts,
            kindLabel: "Service",
            name: "FeatureService",
            filePath: nil,
            role: "",
            pattern: "Service",
            properties: [],
            methods: []
        )

        #expect(CanvasConnectionSuggestionEngine.suggestedType(from: source, to: destination) == .delegatesTo)
        #expect(CanvasConnectionSuggestionEngine.suggestedType(from: destination, to: destination) == nil)
    }

    @Test func connectionRoutingUsesHorizontalControlPointsForRightwardWires() {
        let offset = CanvasConnectionRouting.controlOffset(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 260, y: 140)
        )

        #expect(offset.width > 0)
        #expect(abs(offset.height) < 1)
    }

    @Test func patternPaletteInsertionCreatesBlueprintNodesConnectionsAndBlanket() {
        var model = WorkbenchModel()

        PatternPaletteInsertion.apply(.observer, to: &model)

        #expect(model.inskirts.count == 3)
        #expect(model.connections.count == 2)
        #expect(model.beachBlankets.count == 1)
        #expect(model.beachBlankets.first?.name == "Observer Subsystem")
        #expect(model.inskirts.map { $0.pattern } == ["Observer", "Observer", "Observer"])
        #expect(model.connections.map { $0.type } == ["observes", "calls"])
        #expect(model.beachBlankets.first?.nodes == model.inskirts.map { $0.name })
    }

    @Test func patternPaletteInsertionCreatesSingleNodeArchetypeWithoutBlanket() {
        var model = WorkbenchModel()

        PatternPaletteInsertion.apply(.service, to: &model)

        #expect(model.inskirts.count == 1)
        #expect(model.connections.isEmpty)
        #expect(model.beachBlankets.isEmpty)
        #expect(model.inskirts.first?.pattern == "Service")
    }

    @Test func finalizationWarningAppearsOnlyWhenCanvasHasNoConnections() {
        let emptyModel = WorkbenchModel(
            outskirts: [
                OutskirtsNode(name: "APIClient", file: "Sources/APIClient.swift", role: "", pins: [])
            ]
        )
        let connectedModel = WorkbenchModel(
            outskirts: [
                OutskirtsNode(name: "APIClient", file: "Sources/APIClient.swift", role: "", pins: [])
            ],
            inskirts: [
                InskirtsNode(name: "FeatureViewModel", pattern: "ViewModel", role: "", pins: [])
            ],
            connections: [
                Connection(from: "FeatureViewModel", to: "APIClient", type: "calls")
            ]
        )

        #expect(WorkbenchCanvasFinalizationState.warning(for: emptyModel) == "Canvas has no connections - ARCHITECTURE.toml will be nearly empty")
        #expect(WorkbenchCanvasFinalizationState.warning(for: connectedModel) == nil)
    }

    @Test func excavateRunButtonDisablesOnlyWhileExcavationEngineIsRunning() {
        #expect(WorkbenchExcavateRunState.isDisabled(excavationEngineState: .running))
        #expect(!WorkbenchExcavateRunState.isDisabled(excavationEngineState: .idle))
        #expect(!WorkbenchExcavateRunState.isDisabled(excavationEngineState: .terminated))
    }

    @Test func beachBlanketGeometrySelectsAndSynchronizesNodeMembership() {
        var model = WorkbenchModel(
            inskirts: [
                InskirtsNode(name: "Anchor", pattern: "Service", role: "", pins: ["run() -> Void"]),
                InskirtsNode(name: "Core Anchor", pattern: "Service", role: "", pins: ["run() -> Void"]),
                InskirtsNode(name: "Mover", pattern: "Service", role: "", pins: ["run() -> Void"])
            ],
            beachBlankets: [
                BeachBlanket(name: "Feature", nodes: ["Anchor"]),
                BeachBlanket(name: "Core Services", nodes: ["Core Anchor"])
            ]
        )

        let presentations = CanvasNodePresentationFactory.presentations(for: model)
        let parkedPlacements = CanvasNodeLayoutPlanner.placements(
            for: presentations,
            overrides: [
                "Anchor": CGPoint(x: 0, y: 0),
                "Core Anchor": CGPoint(x: 0, y: 0),
                "Mover": CGPoint(x: 420, y: 0)
            ]
        )
        let anchorPlacement = parkedPlacements.first(where: { $0.presentation.name == "Anchor" })!
        let selection = CanvasPinGeometry.frame(
            for: anchorPlacement,
            zoom: 1,
            pan: .zero,
            canvasSize: CGSize(width: 1200, height: 900)
        ).insetBy(dx: -12, dy: -12)
        let selectedNames = CanvasBeachBlanketGeometry.memberNames(
            in: selection,
            placements: parkedPlacements,
            zoom: 1,
            pan: .zero,
            canvasSize: CGSize(width: 1200, height: 900)
        )

        #expect(selectedNames.contains("Anchor"))
        #expect(selectedNames.contains("Core Anchor"))
        #expect(!selectedNames.contains("Mover"))

        CanvasBeachBlanketGeometry.syncMembership(
            for: "Mover",
            in: &model,
            placements: parkedPlacements,
            zoom: 1,
            pan: .zero,
            canvasSize: CGSize(width: 1200, height: 900)
        )

        #expect(model.beachBlankets.first(where: { $0.name == "Feature" })?.nodes == ["Anchor"])
        #expect(model.beachBlankets.first(where: { $0.name == "Core Services" })?.nodes == ["Core Anchor"])

        let movedPlacements = CanvasNodeLayoutPlanner.placements(
            for: presentations,
            overrides: [
                "Anchor": CGPoint(x: 0, y: 0),
                "Core Anchor": CGPoint(x: 0, y: 0),
                "Mover": CGPoint(x: 40, y: 0)
            ]
        )

        CanvasBeachBlanketGeometry.syncMembership(
            for: "Mover",
            in: &model,
            placements: movedPlacements,
            zoom: 1,
            pan: .zero,
            canvasSize: CGSize(width: 1200, height: 900)
        )

        #expect(model.beachBlankets.first(where: { $0.name == "Feature" })?.nodes.contains("Mover") == true)
        #expect(model.beachBlankets.first(where: { $0.name == "Core Services" })?.nodes.contains("Mover") == true)

        model.addNode("Mover", toBeachBlanketNamed: "Feature")
        model.addNode("Mover", toBeachBlanketNamed: "Core Services")

        #expect(model.beachBlankets.first(where: { $0.name == "Feature" })?.nodes.contains("Mover") == true)
        #expect(model.beachBlankets.first(where: { $0.name == "Core Services" })?.nodes.contains("Mover") == true)
    }
}
