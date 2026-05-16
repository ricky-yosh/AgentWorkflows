import Foundation

struct WorkbenchModel: Codable, Equatable {
    var outskirts: [OutskirtsNode]
    var inskirts: [InskirtsNode]
    var beachBlankets: [BeachBlanket]
    var connections: [Connection]

    init(
        outskirts: [OutskirtsNode] = [],
        inskirts: [InskirtsNode] = [],
        beachBlankets: [BeachBlanket] = [],
        connections: [Connection] = []
    ) {
        self.outskirts = outskirts
        self.inskirts = inskirts
        self.beachBlankets = beachBlankets
        self.connections = connections
    }

    mutating func addOutskirts(_ node: OutskirtsNode) {
        Self.upsert(node, in: &outskirts)
    }

    mutating func removeOutskirts(named name: String) {
        outskirts.removeAll { $0.name == name }
        removeReferences(to: name)
    }

    @discardableResult
    mutating func updateOutskirtsRole(named name: String, role: String) -> Bool {
        guard let index = outskirts.firstIndex(where: { $0.name == name }) else { return false }
        outskirts[index].role = role
        return true
    }

    mutating func addInskirts(_ node: InskirtsNode) {
        Self.upsert(node, in: &inskirts)
    }

    mutating func removeInskirts(named name: String) {
        inskirts.removeAll { $0.name == name }
        removeReferences(to: name)
    }

    @discardableResult
    mutating func renameInskirtsNode(from oldName: String, to newName: String) -> Bool {
        guard oldName != newName else { return true }
        guard !containsNode(named: newName), let index = inskirts.firstIndex(where: { $0.name == oldName }) else {
            return false
        }

        inskirts[index].name = newName
        for index in connections.indices {
            if connections[index].from == oldName {
                connections[index].from = newName
            }
            if connections[index].to == oldName {
                connections[index].to = newName
            }
        }
        for index in beachBlankets.indices {
            beachBlankets[index].nodes = beachBlankets[index].nodes.map { $0 == oldName ? newName : $0 }
        }
        return true
    }

    @discardableResult
    mutating func updateInskirtsNode(named oldName: String, to newNode: InskirtsNode) -> Bool {
        guard inskirts.contains(where: { $0.name == oldName }) else { return false }
        if oldName != newNode.name {
            guard renameInskirtsNode(from: oldName, to: newNode.name) else { return false }
        }
        guard let updatedIndex = inskirts.firstIndex(where: { $0.name == newNode.name }) else { return false }
        inskirts[updatedIndex].pattern = newNode.pattern
        inskirts[updatedIndex].role = newNode.role
        inskirts[updatedIndex].pins = newNode.pins
        return true
    }

    mutating func addConnection(_ connection: Connection) {
        guard !connections.contains(connection) else { return }
        connections.append(connection)
    }

    @discardableResult
    mutating func updateConnection(_ connection: Connection, type: String) -> Bool {
        guard let index = connections.firstIndex(of: connection) else { return false }
        connections[index].type = type
        return true
    }

    mutating func removeConnection(from: String, to: String, type: String) {
        connections.removeAll { $0.from == from && $0.to == to && $0.type == type }
    }

    mutating func addBeachBlanket(_ blanket: BeachBlanket) {
        Self.upsert(blanket, in: &beachBlankets)
    }

    mutating func removeBeachBlanket(named name: String) {
        beachBlankets.removeAll { $0.name == name }
    }

    @discardableResult
    mutating func renameBeachBlanket(from oldName: String, to newName: String) -> Bool {
        guard oldName != newName else { return true }
        guard let index = beachBlankets.firstIndex(where: { $0.name == oldName }) else { return false }
        beachBlankets[index].name = newName
        return true
    }

    mutating func addNode(_ nodeName: String, toBeachBlanketNamed blanketName: String) {
        guard let index = beachBlankets.firstIndex(where: { $0.name == blanketName }) else { return }
        guard !beachBlankets[index].nodes.contains(nodeName) else { return }
        beachBlankets[index].nodes.append(nodeName)
    }

    mutating func removeNode(_ nodeName: String, fromBeachBlanketNamed blanketName: String) {
        guard let index = beachBlankets.firstIndex(where: { $0.name == blanketName }) else { return }
        beachBlankets[index].nodes.removeAll { $0 == nodeName }
        if beachBlankets[index].nodes.isEmpty {
            beachBlankets.remove(at: index)
        }
    }

    var canvasSerialization: String {
        CanvasSerializer.render(self)
    }

    func containsNode(named name: String) -> Bool {
        outskirts.contains { $0.name == name } || inskirts.contains { $0.name == name }
    }

    private mutating func removeReferences(to name: String) {
        connections.removeAll { $0.from == name || $0.to == name }
        for index in beachBlankets.indices {
            beachBlankets[index].nodes.removeAll { $0 == name }
        }
    }

    private static func upsert<T: NamedCanvasItem>(_ item: T, in collection: inout [T]) {
        if let index = collection.firstIndex(where: { $0.name == item.name }) {
            collection[index] = item
        } else {
            collection.append(item)
        }
    }
}

protocol NamedCanvasItem {
    var name: String { get set }
}

struct OutskirtsNode: Codable, Equatable, NamedCanvasItem {
    var name: String
    var file: String
    var role: String
    var pins: [String]

    init(name: String, file: String, role: String = "", pins: [String] = []) {
        self.name = name
        self.file = file
        self.role = role
        self.pins = pins
    }
}

struct InskirtsNode: Codable, Equatable, NamedCanvasItem {
    var name: String
    var pattern: String
    var role: String
    var pins: [String]

    init(name: String, pattern: String, role: String = "", pins: [String] = []) {
        self.name = name
        self.pattern = pattern
        self.role = role
        self.pins = pins
    }
}

struct Connection: Codable, Equatable {
    var from: String
    var to: String
    var type: String

    init(from: String, to: String, type: String) {
        self.from = from
        self.to = to
        self.type = type
    }
}

struct BeachBlanket: Codable, Equatable, NamedCanvasItem {
    var name: String
    var nodes: [String]

    init(name: String, nodes: [String] = []) {
        self.name = name
        self.nodes = nodes
    }
}

private enum CanvasSerializer {
    static func render(_ model: WorkbenchModel) -> String {
        var sections: [String] = []

        if !model.outskirts.isEmpty {
            sections.append(renderEntries(model.outskirts) { node in
                [
                    "[[outskirts]]",
                    "name = \(tomlString(node.name))",
                    "file = \(tomlString(node.file))",
                    "role = \(tomlString(node.role))",
                    "pins = \(tomlArray(node.pins))",
                ]
            })
        }

        if !model.inskirts.isEmpty {
            sections.append(renderEntries(model.inskirts) { node in
                [
                    "[[inskirts]]",
                    "name = \(tomlString(node.name))",
                    "pattern = \(tomlString(node.pattern))",
                    "role = \(tomlString(node.role))",
                    "pins = \(tomlArray(node.pins))",
                ]
            })
        }

        if !model.beachBlankets.isEmpty {
            sections.append(renderEntries(model.beachBlankets) { blanket in
                [
                    "[[beach_blankets]]",
                    "name = \(tomlString(blanket.name))",
                    "nodes = \(tomlArray(blanket.nodes))",
                ]
            })
        }

        if !model.connections.isEmpty {
            sections.append(renderEntries(model.connections) { connection in
                [
                    "[[connections]]",
                    "from = \(tomlString(connection.from))",
                    "to = \(tomlString(connection.to))",
                    "type = \(tomlString(connection.type))",
                ]
            })
        }

        return sections.joined(separator: "\n\n")
    }

    private static func renderEntries<T>(_ entries: [T], lines: (T) -> [String]) -> String {
        entries.map { lines($0).joined(separator: "\n") }.joined(separator: "\n\n")
    }

    private static func tomlString(_ value: String) -> String {
        "\"\(escape(value))\""
    }

    private static func tomlArray(_ values: [String]) -> String {
        "[\(values.map(tomlString).joined(separator: ", "))]"
    }

    private static func escape(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "\\": output.append("\\\\")
            case "\"": output.append("\\\"")
            case "\n": output.append("\\n")
            default: output.append(character)
            }
        }
        return output
    }
}
