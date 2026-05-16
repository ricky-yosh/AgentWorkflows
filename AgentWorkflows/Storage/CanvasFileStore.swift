import Foundation
import Observation

protocol CanvasDirectoryWatching: AnyObject {
    var onChange: (() -> Void)? { get set }
    func watch(directory: URL)
    func stop()
}

protocol CanvasSymbolExtracting {
    func extractPins(for fileURL: URL) -> CanvasSymbolExtractionResult
}

struct CanvasSymbolExtractionResult: Equatable {
    var pins: [String]
    var warning: String?

    init(pins: [String], warning: String? = nil) {
        self.pins = pins
        self.warning = warning
    }
}

extension DirectoryWatcher: CanvasDirectoryWatching {}

struct DefaultCanvasSymbolExtractor: CanvasSymbolExtracting {
    private let extractor = SymbolExtractor()

    func extractPins(for fileURL: URL) -> CanvasSymbolExtractionResult {
        extractor.extractPins(for: fileURL)
    }
}

@Observable
final class CanvasFileStore {
    private(set) var model: WorkbenchModel
    private(set) var warningPayload: String?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let symbolExtractor: any CanvasSymbolExtracting
    @ObservationIgnored private let watcher: any CanvasDirectoryWatching
    @ObservationIgnored private var baselineModel: WorkbenchModel
    @ObservationIgnored private var isWriting = false

    init(
        fileURL: URL,
        symbolExtractor: any CanvasSymbolExtracting = DefaultCanvasSymbolExtractor(),
        watcher: any CanvasDirectoryWatching = DirectoryWatcher(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.symbolExtractor = symbolExtractor
        self.watcher = watcher

        let loaded = Self.loadModel(
            from: fileURL,
            fileManager: fileManager,
            symbolExtractor: symbolExtractor
        )
        self.model = loaded.model
        self.warningPayload = loaded.warningPayload
        self.baselineModel = loaded.model

        watcher.onChange = { [weak self] in
            self?.reloadFromDisk()
        }
        watcher.watch(directory: fileURL.deletingLastPathComponent())
    }

    deinit {
        watcher.stop()
    }

    func reloadFromDisk() {
        guard !isWriting else { return }
        let loaded = Self.loadModel(
            from: fileURL,
            fileManager: fileManager,
            symbolExtractor: symbolExtractor
        )
        model = loaded.model
        warningPayload = loaded.warningPayload
        baselineModel = loaded.model
    }

    func save(_ newModel: WorkbenchModel? = nil) throws {
        let pendingModel = newModel ?? model
        let diskModel = Self.loadModel(
            from: fileURL,
            fileManager: fileManager,
            symbolExtractor: symbolExtractor
        ).model
        let merged = Self.merge(
            baseline: baselineModel,
            disk: diskModel,
            pending: pendingModel
        )
        isWriting = true
        defer { isWriting = false }
        try Self.writeModel(merged, to: fileURL, fileManager: fileManager)
        baselineModel = merged
        model = merged
        warningPayload = nil
    }

    private static func loadModel(
        from fileURL: URL,
        fileManager: FileManager,
        symbolExtractor: any CanvasSymbolExtracting
    ) -> (model: WorkbenchModel, warningPayload: String?) {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return (WorkbenchModel(), nil)
        }

        let parsed = CanvasTomlParser.parse(text)
        var model = parsed.model
        var warnings = parsed.warnings

        var didEnrich = false
        for index in model.outskirts.indices where model.outskirts[index].pins.isEmpty {
            let result = symbolExtractor.extractPins(
                for: resolveFileURL(model.outskirts[index].file, relativeTo: fileURL.deletingLastPathComponent())
            )
            if !result.pins.isEmpty {
                model.outskirts[index].pins = result.pins
                didEnrich = true
            }
            if let warning = result.warning, !warning.isEmpty {
                warnings.append(warning)
            }
        }

        if didEnrich {
            try? writeModel(model, to: fileURL, fileManager: fileManager)
        }

        return (model, warnings.isEmpty ? nil : warnings.joined(separator: "\n"))
    }

    private static func merge(
        baseline: WorkbenchModel,
        disk: WorkbenchModel,
        pending: WorkbenchModel
    ) -> WorkbenchModel {
        var merged = pending
        let baselineOutskirts = Set(baseline.outskirts.map(\.name))
        let baselineInskirts = Set(baseline.inskirts.map(\.name))
        let baselineBlankets = Set(baseline.beachBlankets.map(\.name))
        let baselineConnections = Set(baseline.connections.map(connectionKey))

        for node in disk.outskirts where !baselineOutskirts.contains(node.name) && !merged.outskirts.contains(where: { $0.name == node.name }) {
            merged.outskirts.append(node)
        }
        for node in disk.inskirts where !baselineInskirts.contains(node.name) && !merged.inskirts.contains(where: { $0.name == node.name }) {
            merged.inskirts.append(node)
        }
        for blanket in disk.beachBlankets where !baselineBlankets.contains(blanket.name) && !merged.beachBlankets.contains(where: { $0.name == blanket.name }) {
            merged.beachBlankets.append(blanket)
        }
        for connection in disk.connections where !baselineConnections.contains(connectionKey(connection)) && !merged.connections.contains(connection) {
            merged.connections.append(connection)
        }

        return merged
    }

    private static func connectionKey(_ connection: Connection) -> String {
        "\(connection.from)\u{001F}\(connection.to)\u{001F}\(connection.type)"
    }

    private static func writeModel(
        _ model: WorkbenchModel,
        to fileURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try model.canvasSerialization.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func resolveFileURL(_ path: String, relativeTo baseURL: URL) -> URL {
        URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL
    }
}

private enum CanvasTomlParser {
    private struct PendingEntry {
        var section: Section
        var values: [String: Value] = [:]
    }

    private enum Section {
        case outskirts, inskirts, beachBlankets, connections
    }

    private enum Value {
        case string(String)
        case array([String])
    }

    static func parse(_ text: String) -> (model: WorkbenchModel, warnings: [String]) {
        var warnings: [String] = []
        var model = WorkbenchModel()
        var current: PendingEntry?

        func finalizeCurrent() {
            guard let entry = current else { return }
            switch entry.section {
            case .outskirts:
                if let node = makeOutskirts(entry.values) {
                    model.addOutskirts(node)
                } else {
                    warnings.append("Dropped malformed outskirts entry")
                }
            case .inskirts:
                if let node = makeInskirts(entry.values) {
                    model.addInskirts(node)
                } else {
                    warnings.append("Dropped malformed inskirts entry")
                }
            case .beachBlankets:
                if let blanket = makeBeachBlanket(entry.values) {
                    model.addBeachBlanket(blanket)
                } else {
                    warnings.append("Dropped malformed beach blanket entry")
                }
            case .connections:
                if let connection = makeConnection(entry.values) {
                    model.addConnection(connection)
                } else {
                    warnings.append("Dropped malformed connection entry")
                }
            }
            current = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line == "[[outskirts]]" || line == "[[inskirts]]" || line == "[[beach_blankets]]" || line == "[[connections]]" {
                finalizeCurrent()
                current = PendingEntry(section: section(from: line))
                continue
            }

            guard let equalIndex = line.firstIndex(of: "="), var entry = current else {
                warnings.append("Ignored malformed line: \(line)")
                continue
            }

            let key = line[..<equalIndex].trimmingCharacters(in: .whitespaces)
            let valueText = line[line.index(after: equalIndex)...].trimmingCharacters(in: .whitespaces)
            guard let value = parseValue(valueText) else {
                warnings.append("Ignored malformed value for \(key)")
                continue
            }
            entry.values[String(key)] = value
            current = entry
        }

        finalizeCurrent()

        let validNames = Set(model.outskirts.map(\.name)).union(model.inskirts.map(\.name))
        let filteredConnections = model.connections.filter { validNames.contains($0.from) && validNames.contains($0.to) }
        if filteredConnections.count != model.connections.count {
            warnings.append("Dropped orphaned connection reference")
            model.connections = filteredConnections
        }

        return (model, warnings)
    }

    private static func section(from text: String) -> Section {
        switch text {
        case "[[outskirts]]": return .outskirts
        case "[[inskirts]]": return .inskirts
        case "[[beach_blankets]]": return .beachBlankets
        default: return .connections
        }
    }

    private static func parseValue(_ text: String) -> Value? {
        if text.hasPrefix("[") {
            guard text.hasSuffix("]") else { return nil }
            let inner = text.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return .array([]) }
            var values: [String] = []
            var cursor = String(inner)
            while !cursor.isEmpty {
                cursor = cursor.trimmingCharacters(in: .whitespaces)
                guard cursor.first == "\"" else { return nil }
                cursor.removeFirst()
                var token = ""
                var escaped = false
                var consumedClosingQuote = false
                while !cursor.isEmpty {
                    let character = cursor.removeFirst()
                    if escaped {
                        token.append(unescape(character))
                        escaped = false
                        continue
                    }
                    if character == "\\" {
                        escaped = true
                        continue
                    }
                    if character == "\"" {
                        consumedClosingQuote = true
                        break
                    }
                    token.append(character)
                }
                guard consumedClosingQuote else { return nil }
                values.append(token)
                cursor = cursor.trimmingCharacters(in: .whitespaces)
                if cursor.first == "," {
                    cursor.removeFirst()
                    continue
                }
                break
            }
            return .array(values)
        }

        guard text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 else { return nil }
        return .string(unescapeString(String(text.dropFirst().dropLast())))
    }

    private static func unescape(_ character: Character) -> Character {
        switch character {
        case "n": return "\n"
        case "\"": return "\""
        case "\\": return "\\"
        default: return character
        }
    }

    private static func unescapeString(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            if escaping {
                result.append(String(unescape(character)))
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        if escaping {
            result.append("\\")
        }
        return result
    }

    private static func stringValue(_ values: [String: Value], _ key: String) -> String? {
        guard case let .string(value)? = values[key] else { return nil }
        return value
    }

    private static func arrayValue(_ values: [String: Value], _ key: String) -> [String]? {
        guard case let .array(value)? = values[key] else { return nil }
        return value
    }

    private static func makeOutskirts(_ values: [String: Value]) -> OutskirtsNode? {
        guard let name = stringValue(values, "name"),
              let file = stringValue(values, "file") else { return nil }
        let role = stringValue(values, "role") ?? ""
        let pins = arrayValue(values, "pins") ?? []
        return OutskirtsNode(name: name, file: file, role: role, pins: pins)
    }

    private static func makeInskirts(_ values: [String: Value]) -> InskirtsNode? {
        guard let name = stringValue(values, "name"),
              let pattern = stringValue(values, "pattern") else { return nil }
        let role = stringValue(values, "role") ?? ""
        let pins = arrayValue(values, "pins") ?? []
        return InskirtsNode(name: name, pattern: pattern, role: role, pins: pins)
    }

    private static func makeBeachBlanket(_ values: [String: Value]) -> BeachBlanket? {
        guard let name = stringValue(values, "name") else { return nil }
        let nodes = arrayValue(values, "nodes") ?? []
        return BeachBlanket(name: name, nodes: nodes)
    }

    private static func makeConnection(_ values: [String: Value]) -> Connection? {
        guard let from = stringValue(values, "from"),
              let to = stringValue(values, "to"),
              let type = stringValue(values, "type") else { return nil }
        return Connection(from: from, to: to, type: type)
    }
}
