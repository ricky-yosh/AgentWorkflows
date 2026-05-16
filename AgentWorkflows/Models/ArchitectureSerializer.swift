import Foundation

enum ArchitectureSerializer {
    static func render(_ model: WorkbenchModel) -> String {
        let connectedOutskirtsNames = Set(model.connections.flatMap { [$0.from, $0.to] })
            .intersection(model.outskirts.map(\.name))
        let includedNames = connectedOutskirtsNames.union(model.inskirts.map(\.name))

        var sections: [String] = []

        let outskirts = model.outskirts.filter { connectedOutskirtsNames.contains($0.name) }
        if !outskirts.isEmpty {
            sections.append(renderEntries(outskirts) { node in
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

        let beachBlankets = model.beachBlankets.compactMap { blanket -> BeachBlanket? in
            let nodes = blanket.nodes.filter { includedNames.contains($0) }
            guard !nodes.isEmpty else { return nil }
            return BeachBlanket(name: blanket.name, nodes: nodes)
        }
        if !beachBlankets.isEmpty {
            sections.append(renderEntries(beachBlankets) { blanket in
                [
                    "[[beach_blankets]]",
                    "name = \(tomlString(blanket.name))",
                    "nodes = \(tomlArray(blanket.nodes))",
                ]
            })
        }

        let connections = model.connections.filter { connection in
            includedNames.contains(connection.from) && includedNames.contains(connection.to)
        }
        if !connections.isEmpty {
            sections.append(renderEntries(connections) { connection in
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
