import Testing
import Foundation
@testable import AgentWorkflows

@Suite("WorkbenchModel")
struct WorkbenchModelTests {

    @Test func addRemoveNodesConnectionsAndBlankets() {
        var model = WorkbenchModel()

        model.addOutskirts(OutskirtsNode(name: "APIClient", file: "Sources/API/APIClient.swift", role: "Loads data", pins: ["fetch() -> Void"]))
        model.addInskirts(InskirtsNode(name: "FeatureViewModel", pattern: "ViewModel", role: "Coordinates state", pins: ["load() -> Void"]))
        model.addConnection(Connection(from: "FeatureViewModel", to: "APIClient", type: "calls"))
        model.addBeachBlanket(BeachBlanket(name: "Feature", nodes: ["APIClient", "FeatureViewModel"]))

        #expect(model.outskirts.count == 1)
        #expect(model.inskirts.count == 1)
        #expect(model.connections.count == 1)
        #expect(model.beachBlankets.count == 1)

        model.removeOutskirts(named: "APIClient")
        #expect(model.outskirts.isEmpty)
        #expect(model.connections.isEmpty)
        #expect(model.beachBlankets.first?.nodes == ["FeatureViewModel"])

        model.removeInskirts(named: "FeatureViewModel")
        #expect(model.inskirts.isEmpty)
        #expect(model.beachBlankets.first?.nodes.isEmpty == true)

        model.removeBeachBlanket(named: "Feature")
        #expect(model.beachBlankets.isEmpty)
    }

    @Test func renameInskirtsNodePropagatesToConnectionsAndBlankets() {
        var model = WorkbenchModel(
            outskirts: [OutskirtsNode(name: "APIClient", file: "Sources/API/APIClient.swift", role: "Loads data", pins: [])],
            inskirts: [InskirtsNode(name: "FeatureViewModel", pattern: "ViewModel", role: "Coordinates state", pins: [])],
            beachBlankets: [BeachBlanket(name: "Feature", nodes: ["FeatureViewModel", "APIClient"])],
            connections: [Connection(from: "FeatureViewModel", to: "APIClient", type: "calls")]
        )

        let renamed = model.renameInskirtsNode(from: "FeatureViewModel", to: "DashboardViewModel")
        #expect(renamed)
        #expect(model.inskirts.first?.name == "DashboardViewModel")
        #expect(model.connections.first?.from == "DashboardViewModel")
        #expect(model.beachBlankets.first?.nodes == ["DashboardViewModel", "APIClient"])
    }

    @Test func inspectorStyleEditsUpdateNodeFieldsAndConnectionType() {
        var model = WorkbenchModel(
            outskirts: [OutskirtsNode(name: "APIClient", file: "Sources/API/APIClient.swift", role: "Loads data", pins: ["fetch() -> Void"])],
            inskirts: [InskirtsNode(name: "FeatureViewModel", pattern: "ViewModel", role: "Coordinates state", pins: ["load() -> Void"])],
            beachBlankets: [BeachBlanket(name: "Feature", nodes: ["FeatureViewModel", "APIClient"])],
            connections: [Connection(from: "FeatureViewModel", to: "APIClient", type: "calls")]
        )

        let updatedInskirts = InskirtsNode(
            name: "DashboardCoordinator",
            pattern: "Coordinator",
            role: "Coordinates dashboard flow",
            pins: ["start() -> Void", "state: State"]
        )
        let didUpdateInskirts = model.updateInskirtsNode(named: "FeatureViewModel", to: updatedInskirts)
        #expect(didUpdateInskirts)
        #expect(model.inskirts.first?.name == updatedInskirts.name)
        #expect(model.inskirts.first?.pattern == updatedInskirts.pattern)
        #expect(model.inskirts.first?.role == updatedInskirts.role)
        #expect(model.inskirts.first?.pins == updatedInskirts.pins)
        #expect(model.connections.first?.from == "DashboardCoordinator")
        #expect(model.beachBlankets.first?.nodes == ["DashboardCoordinator", "APIClient"])

        let didUpdateOutskirts = model.updateOutskirtsRole(named: "APIClient", role: "Loads remote data")
        #expect(didUpdateOutskirts)
        #expect(model.outskirts.first?.role == "Loads remote data")

        let oldConnection = Connection(from: "DashboardCoordinator", to: "APIClient", type: "calls")
        let didUpdateConnection = model.updateConnection(oldConnection, type: "observes")
        #expect(didUpdateConnection)
        #expect(model.connections.first?.from == "DashboardCoordinator")
        #expect(model.connections.first?.to == "APIClient")
        #expect(model.connections.first?.type == "observes")
    }

    @Test func canvasSerializationMatchesFixture() {
        let model = WorkbenchModel(
            outskirts: [
                OutskirtsNode(
                    name: "APIClient",
                    file: "Sources/API/APIClient.swift",
                    role: "Loads remote data",
                    pins: ["fetch() -> Void", "baseURL: URL"]
                )
            ],
            inskirts: [
                InskirtsNode(
                    name: "FeatureViewModel",
                    pattern: "ViewModel",
                    role: "Coordinates feature flow",
                    pins: ["load() -> Void", "state: State"]
                )
            ],
            beachBlankets: [
                BeachBlanket(name: "Feature", nodes: ["APIClient", "FeatureViewModel"])
            ],
            connections: [
                Connection(from: "FeatureViewModel", to: "APIClient", type: "calls")
            ]
        )

        let expected = """
        [[outskirts]]
        name = "APIClient"
        file = "Sources/API/APIClient.swift"
        role = "Loads remote data"
        pins = ["fetch() -> Void", "baseURL: URL"]

        [[inskirts]]
        name = "FeatureViewModel"
        pattern = "ViewModel"
        role = "Coordinates feature flow"
        pins = ["load() -> Void", "state: State"]

        [[beach_blankets]]
        name = "Feature"
        nodes = ["APIClient", "FeatureViewModel"]

        [[connections]]
        from = "FeatureViewModel"
        to = "APIClient"
        type = "calls"
        """

        #expect(model.canvasSerialization == expected)
    }

    @Test func architectureSerializationFiltersToImplementationGraph() {
        let model = WorkbenchModel(
            outskirts: [
                OutskirtsNode(name: "APIClient", file: "Sources/APIClient.swift", role: "Loads remote data", pins: ["fetch() -> Void"]),
                OutskirtsNode(name: "Logger", file: "Sources/Logger.swift", role: "Writes logs", pins: ["log() -> Void"]),
                OutskirtsNode(name: "Orphan", file: "Sources/Orphan.swift", role: "Unused", pins: ["noop() -> Void"])
            ],
            inskirts: [
                InskirtsNode(name: "FeatureViewModel", pattern: "ViewModel", role: "Coordinates feature flow", pins: ["load() -> Void"])
            ],
            beachBlankets: [
                BeachBlanket(name: "Feature", nodes: ["APIClient", "FeatureViewModel", "Logger"]),
                BeachBlanket(name: "Empty", nodes: ["Orphan"])
            ],
            connections: [
                Connection(from: "FeatureViewModel", to: "APIClient", type: "calls"),
                Connection(from: "Logger", to: "APIClient", type: "observes")
            ]
        )

        let expected = """
        [[outskirts]]
        name = "APIClient"
        file = "Sources/APIClient.swift"
        role = "Loads remote data"
        pins = ["fetch() -> Void"]

        [[outskirts]]
        name = "Logger"
        file = "Sources/Logger.swift"
        role = "Writes logs"
        pins = ["log() -> Void"]

        [[inskirts]]
        name = "FeatureViewModel"
        pattern = "ViewModel"
        role = "Coordinates feature flow"
        pins = ["load() -> Void"]

        [[beach_blankets]]
        name = "Feature"
        nodes = ["APIClient", "FeatureViewModel", "Logger"]

        [[connections]]
        from = "FeatureViewModel"
        to = "APIClient"
        type = "calls"

        [[connections]]
        from = "Logger"
        to = "APIClient"
        type = "observes"
        """

        #expect(ArchitectureSerializer.render(model) == expected)
    }
}
