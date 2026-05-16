import Foundation
import Observation

struct CanvasLayout: Equatable {
    var nodes: [CanvasLayoutNode]
    var reroutes: [CanvasRerouteWaypoint]
    var zoom: Double
    var panX: Double
    var panY: Double

    init(
        nodes: [CanvasLayoutNode] = [],
        reroutes: [CanvasRerouteWaypoint] = [],
        zoom: Double = 1,
        panX: Double = 0,
        panY: Double = 0
    ) {
        self.nodes = nodes
        self.reroutes = reroutes
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
    }

    static func autoLayout(outskirts: [UUID], inskirts: [UUID]) -> CanvasLayout {
        var layout = CanvasLayout()
        layout.nodes = autoLayoutNodes(outskirts: outskirts, inskirts: inskirts)
        return layout
    }

    private static func autoLayoutNodes(outskirts: [UUID], inskirts: [UUID]) -> [CanvasLayoutNode] {
        var nodes: [CanvasLayoutNode] = []

        let centerSpacing: Double = 72
        let centerCount = max(1, inskirts.count)
        let centerColumns = max(1, Int(ceil(sqrt(Double(centerCount)))))
        let centerRowOffset = Double(max(0, centerCount - 1)) * centerSpacing / 2
        let centerColumnOffset = Double(max(0, centerColumns - 1)) * centerSpacing / 2

        for (index, id) in inskirts.enumerated() {
            let row = index / centerColumns
            let column = index % centerColumns
            nodes.append(
                CanvasLayoutNode(
                    id: id,
                    x: Double(column) * centerSpacing - centerColumnOffset,
                    y: Double(row) * centerSpacing - centerRowOffset
                )
            )
        }

        let radiusBase: Double = 280
        let radiusStep: Double = 18
        let radius = radiusBase + Double(max(0, outskirts.count - 1)) * radiusStep

        for (index, id) in outskirts.enumerated() {
            let angle = Double(index) / Double(max(1, outskirts.count)) * (2 * Double.pi)
            nodes.append(
                CanvasLayoutNode(
                    id: id,
                    x: cos(angle) * radius,
                    y: sin(angle) * radius
                )
            )
        }

        return nodes
    }
}

struct CanvasLayoutNode: Equatable {
    var id: UUID
    var x: Double
    var y: Double
}

struct CanvasRerouteWaypoint: Equatable {
    var id: UUID
    var connectionFrom: String
    var connectionTo: String
    var index: Int
    var x: Double
    var y: Double
}

@Observable
final class CanvasLayoutStore {
    private(set) var layout: CanvasLayout
    private(set) var warningPayload: String?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let fileManager: FileManager

    init(
        fileURL: URL,
        initialLayout: CanvasLayout = CanvasLayout(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let loaded = Self.loadLayout(from: fileURL, fileManager: fileManager)
        self.layout = loaded.layout ?? initialLayout
        self.warningPayload = loaded.warningPayload
    }

    func reloadFromDisk() {
        let loaded = Self.loadLayout(from: fileURL, fileManager: fileManager)
        layout = loaded.layout ?? layout
        warningPayload = loaded.warningPayload
    }

    func save(_ newLayout: CanvasLayout? = nil) throws {
        let pendingLayout = newLayout ?? layout
        try Self.writeLayout(pendingLayout, to: fileURL, fileManager: fileManager)
        layout = pendingLayout
        warningPayload = nil
    }

    private static func loadLayout(
        from fileURL: URL,
        fileManager: FileManager
    ) -> (layout: CanvasLayout?, warningPayload: String?) {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return (nil, nil)
        }

        let parsed = CanvasLayoutTomlParser.parse(text)
        return (parsed.layout, parsed.warnings.isEmpty ? nil : parsed.warnings.joined(separator: "\n"))
    }

    private static func writeLayout(
        _ layout: CanvasLayout,
        to fileURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CanvasLayoutTomlWriter.render(layout).write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

private enum CanvasLayoutTomlWriter {
    static func render(_ layout: CanvasLayout) -> String {
        var sections: [String] = []

        if !layout.nodes.isEmpty {
            sections.append(layout.nodes.map { node in
                [
                    "[[nodes]]",
                    "uuid = \(tomlString(node.id.uuidString))",
                    "x = \(tomlNumber(node.x))",
                    "y = \(tomlNumber(node.y))",
                ].joined(separator: "\n")
            }.joined(separator: "\n\n"))
        }

        if !layout.reroutes.isEmpty {
            sections.append(layout.reroutes.map { reroute in
                [
                    "[[reroutes]]",
                    "uuid = \(tomlString(reroute.id.uuidString))",
                    "connection_from = \(tomlString(reroute.connectionFrom))",
                    "connection_to = \(tomlString(reroute.connectionTo))",
                    "index = \(reroute.index)",
                    "x = \(tomlNumber(reroute.x))",
                    "y = \(tomlNumber(reroute.y))",
                ].joined(separator: "\n")
            }.joined(separator: "\n\n"))
        }

        sections.append([
            "zoom = \(tomlNumber(layout.zoom))",
            "pan_x = \(tomlNumber(layout.panX))",
            "pan_y = \(tomlNumber(layout.panY))",
        ].joined(separator: "\n"))

        return sections.joined(separator: "\n\n")
    }

    private static func tomlString(_ value: String) -> String {
        "\"\(escape(value))\""
    }

    private static func tomlNumber(_ value: Double) -> String {
        value.rounded(.towardZero) == value ? String(Int(value)) : String(value)
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

private enum CanvasLayoutTomlParser {
    private struct PendingEntry {
        var section: Section
        var values: [String: Value] = [:]
    }

    private enum Section {
        case nodes
        case reroutes
    }

    private enum Value {
        case string(String)
        case integer(Int)
        case double(Double)
    }

    static func parse(_ text: String) -> (layout: CanvasLayout?, warnings: [String]) {
        var warnings: [String] = []
        var layout = CanvasLayout()
        var current: PendingEntry?

        func finalizeCurrent() {
            guard let entry = current else { return }
            switch entry.section {
            case .nodes:
                if let node = makeNode(entry.values) {
                    layout.nodes.append(node)
                } else {
                    warnings.append("Dropped malformed node layout entry")
                }
            case .reroutes:
                if let reroute = makeReroute(entry.values) {
                    layout.reroutes.append(reroute)
                } else {
                    warnings.append("Dropped malformed reroute layout entry")
                }
            }
            current = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line == "[[nodes]]" || line == "[[reroutes]]" {
                finalizeCurrent()
                current = PendingEntry(section: section(from: line))
                continue
            }

            guard let equalIndex = line.firstIndex(of: "=") else {
                warnings.append("Ignored malformed line: \(line)")
                continue
            }

            let key = line[..<equalIndex].trimmingCharacters(in: .whitespaces)
            let valueText = line[line.index(after: equalIndex)...].trimmingCharacters(in: .whitespaces)

            if key == "zoom" {
                if let value = parseNumber(valueText) {
                    layout.zoom = value
                } else {
                    warnings.append("Ignored malformed zoom value")
                }
                continue
            }
            if key == "pan_x" {
                if let value = parseNumber(valueText) {
                    layout.panX = value
                } else {
                    warnings.append("Ignored malformed pan_x value")
                }
                continue
            }
            if key == "pan_y" {
                if let value = parseNumber(valueText) {
                    layout.panY = value
                } else {
                    warnings.append("Ignored malformed pan_y value")
                }
                continue
            }

            guard var entry = current, let value = parseValue(valueText) else {
                warnings.append("Ignored malformed value for \(key)")
                continue
            }

            entry.values[String(key)] = value
            current = entry
        }

        finalizeCurrent()

        guard !layout.nodes.isEmpty || !layout.reroutes.isEmpty || layout.zoom != 1 || layout.panX != 0 || layout.panY != 0 else {
            return (CanvasLayout(), warnings)
        }
        return (layout, warnings)
    }

    private static func section(from line: String) -> Section {
        line == "[[nodes]]" ? .nodes : .reroutes
    }

    private static func parseValue(_ text: String) -> Value? {
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            return .string(unescape(String(text.dropFirst().dropLast())))
        }
        if let integer = Int(text) {
            return .integer(integer)
        }
        if let double = Double(text) {
            return .double(double)
        }
        return nil
    }

    private static func parseNumber(_ text: String) -> Double? {
        if let integer = Int(text) { return Double(integer) }
        return Double(text)
    }

    private static func makeNode(_ values: [String: Value]) -> CanvasLayoutNode? {
        guard case let .string(uuidString)? = values["uuid"],
              let id = UUID(uuidString: uuidString),
              let x = values["x"].flatMap(doubleValue),
              let y = values["y"].flatMap(doubleValue) else {
            return nil
        }
        return CanvasLayoutNode(id: id, x: x, y: y)
    }

    private static func makeReroute(_ values: [String: Value]) -> CanvasRerouteWaypoint? {
        guard case let .string(uuidString)? = values["uuid"],
              let id = UUID(uuidString: uuidString),
              case let .string(connectionFrom)? = values["connection_from"],
              case let .string(connectionTo)? = values["connection_to"],
              let index = values["index"].flatMap(intValue),
              let x = values["x"].flatMap(doubleValue),
              let y = values["y"].flatMap(doubleValue) else {
            return nil
        }
        return CanvasRerouteWaypoint(
            id: id,
            connectionFrom: connectionFrom,
            connectionTo: connectionTo,
            index: index,
            x: x,
            y: y
        )
    }

    private static func doubleValue(_ value: Value) -> Double? {
        switch value {
        case let .double(value):
            return value
        case let .integer(value):
            return Double(value)
        case .string:
            return nil
        }
    }

    private static func intValue(_ value: Value) -> Int? {
        switch value {
        case let .integer(value):
            return value
        case let .double(value):
            return Int(value)
        case .string:
            return nil
        }
    }

    private static func unescape(_ value: String) -> String {
        var output = ""
        var iterator = value.makeIterator()
        while let character = iterator.next() {
            if character == "\\" {
                guard let next = iterator.next() else { break }
                switch next {
                case "\\": output.append("\\")
                case "\"": output.append("\"")
                case "n": output.append("\n")
                default:
                    output.append(next)
                }
            } else {
                output.append(character)
            }
        }
        return output
    }
}
