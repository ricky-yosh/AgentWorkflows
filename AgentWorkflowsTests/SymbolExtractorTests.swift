import Foundation
import Testing
@testable import AgentWorkflows

@Suite("SymbolExtractor")
struct SymbolExtractorTests {
    private let fileManager = FileManager.default
    private let baseURL: URL

    init() throws {
        baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("AW-SymbolExtractor-\(UUID().uuidString)")
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    private func cleanup() {
        try? fileManager.removeItem(at: baseURL)
    }

    @Test func extractsSwiftTypesAndFiltersPrivateMembers() throws {
        defer { cleanup() }

        let root = baseURL.appendingPathComponent("Repo")
        let sourceURL = root.appendingPathComponent("Sources/FeatureViewModel.swift")
        try makeFile(
            at: sourceURL,
            contents: """
            public final class FeatureViewModel {
                public var title: String
                private var cache: Int

                public func load() -> Bool {
                    true
                }

                private func helper() {}
            }
            """
        )

        let extractor = SymbolExtractor()
        let result = extractor.extractSymbols(in: root)

        #expect(result.types.count == 1)
        #expect(result.types.first?.name == "FeatureViewModel")
        #expect(result.types.first?.file == "Sources/FeatureViewModel.swift")
        #expect(result.types.first?.members == ["title: String", "load() -> Bool"])
        #expect(result.toml.contains("[[types]]"))
        #expect(result.toml.contains(#"file = "Sources/FeatureViewModel.swift""#))
    }

    @Test func skipsIgnoredDirectoriesDuringRepositoryScan() throws {
        defer { cleanup() }

        let root = baseURL.appendingPathComponent("Repo")
        try makeFile(
            at: root.appendingPathComponent("Sources/Visible.swift"),
            contents: """
            public class Visible {
                public func run() {}
            }
            """
        )
        try makeFile(
            at: root.appendingPathComponent(".build/Ignored.swift"),
            contents: """
            public class Ignored {
                public func run() {}
            }
            """
        )
        try makeFile(
            at: root.appendingPathComponent("node_modules/Ignored.js"),
            contents: """
            class Ignored {
              run() {}
            }
            """
        )
        try makeFile(
            at: root.appendingPathComponent("DerivedData/Ignored.py"),
            contents: """
            class Ignored:
                def run(self):
                    pass
            """
        )

        let extractor = SymbolExtractor()
        let result = extractor.extractSymbols(in: root)

        #expect(result.types.count == 1)
        #expect(result.types.first?.name == "Visible")
        #expect(result.types.first?.file == "Sources/Visible.swift")
    }

    @Test func unsupportedLanguagesReturnWarningAndNoTypes() throws {
        defer { cleanup() }

        let fileURL = baseURL.appendingPathComponent("Repo/README.txt")
        try makeFile(at: fileURL, contents: "Not source code")

        let extractor = SymbolExtractor()
        let result = extractor.extractSymbols(at: fileURL)

        #expect(result.types.isEmpty)
        #expect(result.warning?.contains("Unsupported language") == true)
    }

    @Test func extractsObjectiveCMembers() throws {
        defer { cleanup() }

        let root = baseURL.appendingPathComponent("Repo")
        let fileURL = root.appendingPathComponent("Sources/Widget.h")
        try makeFile(
            at: fileURL,
            contents: """
            @interface Widget : NSObject
            @property(nonatomic, copy) NSString *title;
            - (void)reload;
            @end
            """
        )

        let result = SymbolExtractor().extractSymbols(at: fileURL, repositoryRoot: root)
        #expect(result.types.count == 1)
        #expect(result.types.first?.name == "Widget")
        #expect(result.types.first?.file == "Sources/Widget.h")
        #expect(result.types.first?.members == ["title: NSString *", "reload() -> Void"])
    }

    @Test func extractsJavaScriptMembers() throws {
        defer { cleanup() }

        let root = baseURL.appendingPathComponent("Repo")
        let fileURL = root.appendingPathComponent("Sources/Widget.js")
        try makeFile(
            at: fileURL,
            contents: """
            class Widget {
              title = "value";
              reload() {}
            }
            """
        )

        let result = SymbolExtractor().extractSymbols(at: fileURL, repositoryRoot: root)
        #expect(result.types.count == 1)
        #expect(result.types.first?.name == "Widget")
        #expect(result.types.first?.file == "Sources/Widget.js")
        #expect(result.types.first?.members == ["title: Any", "reload() -> Void"])
    }

    @Test func extractsPythonMembers() throws {
        defer { cleanup() }

        let root = baseURL.appendingPathComponent("Repo")
        let fileURL = root.appendingPathComponent("Sources/Widget.py")
        try makeFile(
            at: fileURL,
            contents: """
            class Widget:
                title: str

                def reload(self):
                    pass

                def _private(self):
                    pass
            """
        )

        let result = SymbolExtractor().extractSymbols(at: fileURL, repositoryRoot: root)
        #expect(result.types.count == 1)
        #expect(result.types.first?.name == "Widget")
        #expect(result.types.first?.file == "Sources/Widget.py")
        #expect(result.types.first?.members == ["title: str", "reload() -> Void"])
    }

    @Test func extractsGDScriptMembers() throws {
        defer { cleanup() }

        let root = baseURL.appendingPathComponent("Repo")
        let fileURL = root.appendingPathComponent("Sources/Widget.gd")
        try makeFile(
            at: fileURL,
            contents: """
            class_name Widget

            var title: String

            func reload():
                pass

            func _private():
                pass
            """
        )

        let result = SymbolExtractor().extractSymbols(at: fileURL, repositoryRoot: root)
        #expect(result.types.count == 1)
        #expect(result.types.first?.name == "Widget")
        #expect(result.types.first?.file == "Sources/Widget.gd")
        #expect(result.types.first?.members == ["title: String", "reload() -> Void"])
    }

    private func makeFile(at fileURL: URL, contents: String) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
