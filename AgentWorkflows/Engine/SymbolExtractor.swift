import Foundation

#if canImport(SwiftParser)
import SwiftParser
#endif

#if canImport(SwiftSyntax)
import SwiftSyntax
#endif

struct SymbolExtractor {
    struct SymbolEntry: Equatable {
        var name: String
        var file: String
        var members: [String]
    }

    struct Result: Equatable {
        var types: [SymbolEntry]
        var warning: String?

        var toml: String {
            SymbolIndexTomlRenderer.render(types)
        }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func extractSymbols(in repositoryRoot: URL) -> Result {
        let root = repositoryRoot.standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return Result(types: [], warning: "Unable to enumerate \(root.path)")
        }

        var entries: [SymbolEntry] = []
        var warnings: [String] = []

        while let item = enumerator.nextObject() as? URL {
            if shouldSkip(item) {
                enumerator.skipDescendants()
                continue
            }

            guard isSupportedSourceFile(item) else {
                continue
            }

            let result = extractSymbols(at: item, repositoryRoot: root)
            entries.append(contentsOf: result.types)
            if let warning = result.warning, !warning.isEmpty {
                warnings.append(warning)
            }
        }

        return Result(types: entries, warning: warnings.isEmpty ? nil : warnings.joined(separator: "\n"))
    }

    func extractSymbols(at fileURL: URL, repositoryRoot: URL? = nil) -> Result {
        let sourceURL = fileURL.standardizedFileURL
        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            return Result(types: [], warning: "Unable to read \(sourceURL.lastPathComponent)")
        }

        let resolvedRelativePath = repositoryRoot.map { relativePath(for: sourceURL, root: $0.standardizedFileURL) } ?? sourceURL.path
        let language = language(for: sourceURL)

        switch language {
        case .swift:
            return extractSwiftSymbols(from: source, file: resolvedRelativePath)
        case .objectiveC:
            return extractObjectiveCSymbols(from: source, file: resolvedRelativePath)
        case .javascript:
            return extractJavaScriptSymbols(from: source, file: resolvedRelativePath)
        case .python:
            return extractPythonSymbols(from: source, file: resolvedRelativePath)
        case .gdscript:
            return extractGDScriptSymbols(from: source, file: resolvedRelativePath)
        case .unsupported:
            return Result(types: [], warning: "Unsupported language: \(sourceURL.pathExtension.isEmpty ? sourceURL.lastPathComponent : sourceURL.pathExtension)")
        }
    }

    func extractPins(for fileURL: URL) -> CanvasSymbolExtractionResult {
        let result = extractSymbols(at: fileURL)
        guard let entry = selectPrimaryEntry(from: result.types, fileURL: fileURL) else {
            return CanvasSymbolExtractionResult(
                pins: [],
                warning: result.warning ?? "No extractable symbols found"
            )
        }

        if let warning = result.warning, !warning.isEmpty {
            return CanvasSymbolExtractionResult(pins: entry.members, warning: warning)
        }
        return CanvasSymbolExtractionResult(pins: entry.members)
    }

    private func selectPrimaryEntry(from types: [SymbolEntry], fileURL: URL) -> SymbolEntry? {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        return types.first(where: { URL(fileURLWithPath: $0.file).deletingPathExtension().lastPathComponent == stem }) ?? types.first
    }

    private func relativePath(for fileURL: URL, root: URL) -> String {
        let standardizedFile = fileURL.standardizedFileURL.path
        let standardizedRoot = root.standardizedFileURL.path
        let prefix = standardizedRoot.hasSuffix("/") ? standardizedRoot : standardizedRoot + "/"
        if standardizedFile.hasPrefix(prefix) {
            return String(standardizedFile.dropFirst(prefix.count))
        }
        return fileURL.lastPathComponent
    }

    private func shouldSkip(_ url: URL) -> Bool {
        let ignoredComponents = Set([".build", "DerivedData", "node_modules", "Pods", "dist"])
        let components = url.standardizedFileURL.pathComponents
        if components.contains(".git") || components.contains(".svn") {
            return true
        }
        return components.contains { ignoredComponents.contains($0) }
    }

    private func isSupportedSourceFile(_ url: URL) -> Bool {
        switch language(for: url) {
        case .swift, .objectiveC, .javascript, .python, .gdscript:
            return true
        case .unsupported:
            return false
        }
    }

    private enum SourceLanguage {
        case swift
        case objectiveC
        case javascript
        case python
        case gdscript
        case unsupported
    }

    private func language(for url: URL) -> SourceLanguage {
        switch url.pathExtension.lowercased() {
        case "swift":
            return .swift
        case "m", "mm", "h":
            return .objectiveC
        case "js", "mjs", "cjs", "jsx":
            return .javascript
        case "py":
            return .python
        case "gd":
            return .gdscript
        default:
            return .unsupported
        }
    }

    // MARK: Swift

    private func extractSwiftSymbols(from source: String, file: String) -> Result {
#if canImport(SwiftParser) && canImport(SwiftSyntax)
        let tree = Parser.parse(source: source)
        var entries: [SymbolEntry] = []
        for statement in tree.statements {
            guard let decl = statement.item.as(DeclSyntax.self) else {
                continue
            }
            collectSwiftType(from: decl, file: file, into: &entries)
        }
        return Result(types: entries, warning: nil)
#else
        return Result(types: [], warning: "SwiftSyntax is unavailable")
#endif
    }

#if canImport(SwiftParser) && canImport(SwiftSyntax)
    private func collectSwiftType(from decl: DeclSyntax, file: String, into entries: inout [SymbolEntry]) {
        if let type = decl.as(ClassDeclSyntax.self) {
            entries.append(
                SymbolEntry(
                    name: type.name.text,
                    file: file,
                    members: swiftMembers(
                        from: type.memberBlock.members,
                        typeName: type.name.text,
                        treatsAllMembersAsPublic: false
                    )
                )
            )
            for member in type.memberBlock.members {
                if let nested = member.decl.as(DeclSyntax.self) {
                    collectSwiftType(from: nested, file: file, into: &entries)
                }
            }
        } else if let type = decl.as(StructDeclSyntax.self) {
            entries.append(
                SymbolEntry(
                    name: type.name.text,
                    file: file,
                    members: swiftMembers(
                        from: type.memberBlock.members,
                        typeName: type.name.text,
                        treatsAllMembersAsPublic: false
                    )
                )
            )
            for member in type.memberBlock.members {
                if let nested = member.decl.as(DeclSyntax.self) {
                    collectSwiftType(from: nested, file: file, into: &entries)
                }
            }
        } else if let type = decl.as(EnumDeclSyntax.self) {
            entries.append(
                SymbolEntry(
                    name: type.name.text,
                    file: file,
                    members: swiftMembers(
                        from: type.memberBlock.members,
                        typeName: type.name.text,
                        treatsAllMembersAsPublic: false
                    )
                )
            )
            for member in type.memberBlock.members {
                if let nested = member.decl.as(DeclSyntax.self) {
                    collectSwiftType(from: nested, file: file, into: &entries)
                }
            }
        } else if let type = decl.as(ProtocolDeclSyntax.self) {
            entries.append(
                SymbolEntry(
                    name: type.name.text,
                    file: file,
                    members: swiftMembers(
                        from: type.memberBlock.members,
                        typeName: type.name.text,
                        treatsAllMembersAsPublic: true
                    )
                )
            )
            for member in type.memberBlock.members {
                if let nested = member.decl.as(DeclSyntax.self) {
                    collectSwiftType(from: nested, file: file, into: &entries)
                }
            }
        } else if let type = decl.as(ActorDeclSyntax.self) {
            entries.append(
                SymbolEntry(
                    name: type.name.text,
                    file: file,
                    members: swiftMembers(
                        from: type.memberBlock.members,
                        typeName: type.name.text,
                        treatsAllMembersAsPublic: false
                    )
                )
            )
            for member in type.memberBlock.members {
                if let nested = member.decl.as(DeclSyntax.self) {
                    collectSwiftType(from: nested, file: file, into: &entries)
                }
            }
        }
    }

    private func swiftMembers(
        from members: MemberBlockItemListSyntax,
        typeName: String,
        treatsAllMembersAsPublic: Bool
    ) -> [String] {
        var pins: [String] = []

        for item in members {
            let decl = item.decl

            if decl.as(ClassDeclSyntax.self) != nil
                || decl.as(StructDeclSyntax.self) != nil
                || decl.as(EnumDeclSyntax.self) != nil
                || decl.as(ProtocolDeclSyntax.self) != nil
                || decl.as(ActorDeclSyntax.self) != nil
            {
                continue
            }

            if let variable = decl.as(VariableDeclSyntax.self) {
                guard treatsAllMembersAsPublic || isPublicOrOpen(variable.modifiers) else {
                    continue
                }
                pins.append(contentsOf: swiftPins(from: variable))
                continue
            }

            if let function = decl.as(FunctionDeclSyntax.self) {
                guard treatsAllMembersAsPublic || isPublicOrOpen(function.modifiers) else {
                    continue
                }
                pins.append(swiftFunctionPin(for: function))
                continue
            }

            if let initializer = decl.as(InitializerDeclSyntax.self) {
                guard treatsAllMembersAsPublic || isPublicOrOpen(initializer.modifiers) else {
                    continue
                }
                pins.append("init() -> \(typeName)")
                continue
            }
        }

        return pins
    }

    private func swiftPins(from variable: VariableDeclSyntax) -> [String] {
        variable.bindings.compactMap { binding in
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                return nil
            }

            let type = binding.typeAnnotation?.type.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Any"
            return "\(name): \(normalizeType(type))"
        }
    }

    private func swiftFunctionPin(for function: FunctionDeclSyntax) -> String {
        let returnType = function.signature.returnClause?.type.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Void"
        return "\(function.name.text)() -> \(normalizeType(returnType))"
    }

    private func isPublicOrOpen(_ modifiers: DeclModifierListSyntax?) -> Bool {
        guard let modifiers else { return false }
        return modifiers.contains { modifier in
            let name = modifier.name.text
            return name == "public" || name == "open"
        }
    }
#endif

    // MARK: Objective-C

    private func extractObjectiveCSymbols(from source: String, file: String) -> Result {
        let pattern = #"(?s)@(interface|protocol)\s+([A-Za-z_]\w*)(?:\s*:\s*[^\n{]+)?\s*(.*?)@end"#
        let regex = makeRegex(pattern)
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        var entries: [SymbolEntry] = []

        for match in matches {
            guard match.numberOfRanges >= 4,
                  let kindRange = Range(match.range(at: 1), in: source),
                  let nameRange = Range(match.range(at: 2), in: source),
                  let bodyRange = Range(match.range(at: 3), in: source)
            else {
                continue
            }

            let kind = String(source[kindRange])
            let name = String(source[nameRange])
            let body = String(source[bodyRange])
            entries.append(
                SymbolEntry(
                    name: name,
                    file: file,
                    members: objectiveCMembers(from: body, typeName: name, isProtocol: kind == "protocol")
                )
            )
        }

        return Result(types: entries, warning: nil)
    }

    private func objectiveCMembers(from body: String, typeName: String, isProtocol: Bool) -> [String] {
        let propertyPattern = #"@property(?:\s*\([^)]+\))?\s*([^;]+?)\s*(\*+)?\s*([A-Za-z_]\w*)\s*;"#
        let methodPattern = #"[-+]\s*\(\s*([^)]+?)\s*\)\s*([A-Za-z_]\w*)(?::[^;]*)?;"#
        var pins: [String] = []

        for match in makeRegex(propertyPattern).matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard match.numberOfRanges >= 4,
                  let typeRange = Range(match.range(at: 1), in: body),
                  let starsRange = Range(match.range(at: 2), in: body),
                  let nameRange = Range(match.range(at: 3), in: body)
            else {
                continue
            }

            let stars = String(body[starsRange])
            let type = cleanupCType(String(body[typeRange]) + (stars.isEmpty ? "" : " \(stars)"))
            let name = String(body[nameRange])
            pins.append("\(name): \(type)")
        }

        for match in makeRegex(methodPattern).matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard match.numberOfRanges >= 3,
                  let returnRange = Range(match.range(at: 1), in: body),
                  let nameRange = Range(match.range(at: 2), in: body)
            else {
                continue
            }

            let returnType = normalizeType(cleanupCType(String(body[returnRange])))
            let name = String(body[nameRange])
            pins.append("\(name)() -> \(returnType)")
        }

        return pins
    }

    // MARK: JavaScript

    private func extractJavaScriptSymbols(from source: String, file: String) -> Result {
        let classPattern = #"(?m)^\s*(?:export\s+default\s+|export\s+)?class\s+([A-Za-z_$][\w$]*)[^{]*\{"#
        let regex = makeRegex(classPattern)
        var entries: [SymbolEntry] = []

        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard match.numberOfRanges >= 2,
                  let nameRange = Range(match.range(at: 1), in: source),
                  let openBraceRange = Range(match.range(at: 0), in: source)
            else {
                continue
            }

            let name = String(source[nameRange])
            guard let body = braceBody(after: source.index(before: openBraceRange.upperBound), in: source) else {
                continue
            }
            entries.append(
                SymbolEntry(
                    name: name,
                    file: file,
                    members: javaScriptMembers(from: body)
                )
            )
        }

        return Result(types: entries, warning: nil)
    }

    private func javaScriptMembers(from body: String) -> [String] {
        var pins: [String] = []
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)

        for rawLine in lines {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("static ") || trimmed.hasPrefix("async ") || trimmed.contains(" get ") || trimmed.contains(" set ") || trimmed.contains("(") {
                if let name = captureJavaScriptMemberName(from: trimmed, pattern: #"^(?:static\s+)?(?:async\s+)?(?:get\s+|set\s+)?([A-Za-z_$][\w$]*)\s*\("#) {
                    if !name.hasPrefix("#") && !name.hasPrefix("_") {
                        pins.append("\(name)() -> Void")
                    }
                }
                continue
            }

            if let name = captureJavaScriptMemberName(from: trimmed, pattern: #"^(?:static\s+)?([A-Za-z_$][\w$]*)\s*(?:=|:)"#) {
                if !name.hasPrefix("#") && !name.hasPrefix("_") {
                    pins.append("\(name): Any")
                }
            }
        }

        return pins
    }

    private func captureJavaScriptMemberName(from line: String, pattern: String) -> String? {
        let regex = makeRegex(pattern)
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[range])
    }

    // MARK: Python

    private func extractPythonSymbols(from source: String, file: String) -> Result {
        let classes = pythonClassBlocks(in: source)
        let entries = classes.map { typeName, body in
            SymbolEntry(
                name: typeName,
                file: file,
                members: pythonMembers(from: body)
            )
        }
        return Result(types: entries, warning: nil)
    }

    private func pythonClassBlocks(in source: String) -> [(String, String)] {
        let classPattern = #"(?m)^class\s+([A-Za-z_]\w*)(?:\([^\)]*\))?:\s*$"#
        let regex = makeRegex(classPattern)
        var blocks: [(String, String)] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var lineIndex = 0

        while lineIndex < lines.count {
            let line = String(lines[lineIndex])
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range),
               match.numberOfRanges >= 2,
               let nameRange = Range(match.range(at: 1), in: line) {
                let name = String(line[nameRange])
                let classIndent = leadingWhitespaceCount(in: line)
                var body: [String] = []
                lineIndex += 1
                while lineIndex < lines.count {
                    let bodyLine = String(lines[lineIndex])
                    if bodyLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        body.append(bodyLine)
                        lineIndex += 1
                        continue
                    }
                    if leadingWhitespaceCount(in: bodyLine) > classIndent {
                        body.append(bodyLine)
                        lineIndex += 1
                        continue
                    }
                    break
                }
                blocks.append((name, body.joined(separator: "\n")))
                continue
            }
            lineIndex += 1
        }

        return blocks
    }

    private func pythonMembers(from body: String) -> [String] {
        var pins: [String] = []
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)

        for rawLine in lines {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if let name = capturePythonMemberName(from: line, pattern: #"^def\s+([A-Za-z_]\w*)\s*\("#) {
                if !name.hasPrefix("_") {
                    pins.append("\(name)() -> Void")
                }
                continue
            }

            if let name = capturePythonMemberName(from: line, pattern: #"^([A-Za-z_]\w*)\s*:\s*([^=]+?)(?:\s*=.*)?$"#) {
                if !name.hasPrefix("_") {
                    let type = capturePythonMemberType(from: line) ?? "Any"
                    pins.append("\(name): \(normalizeType(type))")
                }
                continue
            }

            if let name = capturePythonMemberName(from: line, pattern: #"^([A-Za-z_]\w*)\s*=\s*.+$"#) {
                if !name.hasPrefix("_") {
                    pins.append("\(name): Any")
                }
            }
        }

        return pins
    }

    private func capturePythonMemberName(from line: String, pattern: String) -> String? {
        let regex = makeRegex(pattern)
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[range])
    }

    private func capturePythonMemberType(from line: String) -> String? {
        let regex = makeRegex(#"^([A-Za-z_]\w*)\s*:\s*([^=]+?)(?:\s*=.*)?$"#)
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 3,
              let range = Range(match.range(at: 2), in: line)
        else {
            return nil
        }
        return cleanupType(String(line[range]))
    }

    // MARK: GDScript

    private func extractGDScriptSymbols(from source: String, file: String) -> Result {
        let typeName = gdscriptTypeName(in: source, file: file)
        let members = gdscriptMembers(from: source)
        return Result(types: [SymbolEntry(name: typeName, file: file, members: members)], warning: nil)
    }

    private func gdscriptTypeName(in source: String, file: String) -> String {
        let pattern = #"(?m)^\s*class_name\s+([A-Za-z_]\w*)"#
        let regex = makeRegex(pattern)
        if let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
           match.numberOfRanges >= 2,
           let range = Range(match.range(at: 1), in: source) {
            return String(source[range])
        }
        return URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
    }

    private func gdscriptMembers(from source: String) -> [String] {
        var pins: [String] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)

        for rawLine in lines {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if let name = captureGDScriptMemberName(from: line, pattern: #"^func\s+([A-Za-z_]\w*)\s*\("#) {
                if !name.hasPrefix("_") {
                    pins.append("\(name)() -> Void")
                }
                continue
            }

            if let name = captureGDScriptMemberName(from: line, pattern: #"^var\s+([A-Za-z_]\w*)\s*(?::\s*([^=]+))?(?:\s*=.*)?$"#) {
                if !name.hasPrefix("_") {
                    let type = captureGDScriptMemberType(from: line) ?? "Variant"
                    pins.append("\(name): \(normalizeType(type))")
                }
            }
        }

        return pins
    }

    private func captureGDScriptMemberName(from line: String, pattern: String) -> String? {
        let regex = makeRegex(pattern)
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[range])
    }

    private func captureGDScriptMemberType(from line: String) -> String? {
        let regex = makeRegex(#"^var\s+([A-Za-z_]\w*)\s*(?::\s*([^=]+))?(?:\s*=.*)?$"#)
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 3,
              let range = Range(match.range(at: 2), in: line)
        else {
            return nil
        }
        return cleanupType(String(line[range]))
    }

    // MARK: Shared helpers

    private func cleanupType(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Any" }
        let cleaned = trimmed
            .replacingOccurrences(of: "nullable ", with: "")
            .replacingOccurrences(of: "nonnull ", with: "")
            .replacingOccurrences(of: "__kindof ", with: "")
            .replacingOccurrences(of: "__autoreleasing ", with: "")
            .replacingOccurrences(of: "inout ", with: "")
        return cleaned
    }

    private func cleanupCType(_ value: String) -> String {
        cleanupType(value)
            .replacingOccurrences(of: " _Nullable", with: "")
            .replacingOccurrences(of: " _Nonnull", with: "")
            .replacingOccurrences(of: " const", with: "")
    }

    private func normalizeType(_ value: String) -> String {
        let cleaned = cleanupType(value)
        if cleaned == "void" || cleaned == "Void" {
            return "Void"
        }
        return cleaned
    }

    private func makeRegex(_ pattern: String) -> NSRegularExpression {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.anchorsMatchLines, .dotMatchesLineSeparators]
        ) else {
            preconditionFailure("Invalid regular expression: \(pattern)")
        }
        return regex
    }

    private func braceBody(after openBraceIndex: String.Index, in source: String) -> String? {
        guard openBraceIndex < source.endIndex, source[openBraceIndex] == "{" else {
            return nil
        }

        var depth = 1
        var index = source.index(after: openBraceIndex)
        let start = index

        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[start..<index])
                }
            }
            index = source.index(after: index)
        }

        return nil
    }

    private func leadingWhitespaceCount(in string: String) -> Int {
        string.prefix { $0 == " " || $0 == "\t" }.count
    }
}

private enum SymbolIndexTomlRenderer {
    static func render(_ types: [SymbolExtractor.SymbolEntry]) -> String {
        types.map { entry in
            [
                "[[types]]",
                "name = \(tomlString(entry.name))",
                "file = \(tomlString(entry.file))",
                "members = \(tomlArray(entry.members))",
            ].joined(separator: "\n")
        }.joined(separator: "\n\n")
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
