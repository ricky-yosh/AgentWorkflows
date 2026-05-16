import AppKit
import SwiftUI

struct PatternPaletteView: View {
    private let blueprintTemplates = PatternPaletteTemplate.allCases.filter { $0.isBlueprint }
    private let archetypeTemplates = PatternPaletteTemplate.allCases.filter { !$0.isBlueprint }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    paletteSection(title: "Blueprints", templates: blueprintTemplates)
                    paletteSection(title: "Archetypes", templates: archetypeTemplates)
                }
                .padding(12)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pattern Palette")
                .font(.headline)
            Text("Drag a template onto the canvas")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func paletteSection(title: String, templates: [PatternPaletteTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.7)

            ForEach(templates) { template in
                PatternPaletteCard(template: template)
            }
        }
    }
}

private struct PatternPaletteCard: View {
    let template: PatternPaletteTemplate

    private var accent: Color {
        CanvasNodePresentationFactory.accentColor(forPattern: template.accentPattern)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(template.displayName)
                    .font(.headline)

                Spacer(minLength: 0)

                Text(template.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(template.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: NSColor(calibratedWhite: 0.17, alpha: 1)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.9), lineWidth: 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.12), radius: 10, x: 0, y: 6)
        .onDrag {
            NSItemProvider(object: NSString(string: template.rawValue))
        }
    }
}

enum PatternPaletteTemplate: String, CaseIterable, Identifiable {
    case observer
    case repository
    case adapter
    case factory
    case service
    case coordinator
    case delegate
    case generic

    var id: String { rawValue }

    var isBlueprint: Bool {
        switch self {
        case .observer, .repository, .adapter, .factory:
            return true
        case .service, .coordinator, .delegate, .generic:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .observer:
            return "Observer"
        case .repository:
            return "Repository"
        case .adapter:
            return "Adapter"
        case .factory:
            return "Factory"
        case .service:
            return "Service"
        case .coordinator:
            return "Coordinator"
        case .delegate:
            return "Delegate"
        case .generic:
            return "Generic"
        }
    }

    var subtitle: String {
        isBlueprint ? "\(nodes.count) nodes" : "1 node"
    }

    var summary: String {
        switch self {
        case .observer:
            return "A subject, observer, and relay that fan out state changes."
        case .repository:
            return "A repository, cache, and data source for layered data access."
        case .adapter:
            return "An adapter bridging a new boundary to a legacy API."
        case .factory:
            return "A factory that creates products from a shared configuration."
        case .service:
            return "A single service node for business logic or orchestration."
        case .coordinator:
            return "A single coordinator node for flow control."
        case .delegate:
            return "A single delegate node for callbacks and handoffs."
        case .generic:
            return "A blank starter node with no preset pattern label."
        }
    }

    var accentPattern: String? {
        switch self {
        case .generic:
            return nil
        default:
            return displayName
        }
    }

    var blanketName: String? {
        guard isBlueprint else { return nil }
        return "\(displayName) Subsystem"
    }

    var nodes: [PatternPaletteNodeSpec] {
        switch self {
        case .observer:
            return [
                PatternPaletteNodeSpec(
                    name: "Subject",
                    pattern: displayName,
                    role: "Owns state and broadcasts changes",
                    pins: ["state: State", "publish() -> Void"]
                ),
                PatternPaletteNodeSpec(
                    name: "Observer",
                    pattern: displayName,
                    role: "Consumes observed updates",
                    pins: ["state: State", "update() -> Void"]
                ),
                PatternPaletteNodeSpec(
                    name: "Relay",
                    pattern: displayName,
                    role: "Relays observed changes to the rest of the feature",
                    pins: ["deliver() -> Void"]
                )
            ]
        case .repository:
            return [
                PatternPaletteNodeSpec(
                    name: "Repository",
                    pattern: displayName,
                    role: "Coordinates data access and cache lookups",
                    pins: ["fetch() -> Void", "save() -> Void"]
                ),
                PatternPaletteNodeSpec(
                    name: "Cache",
                    pattern: displayName,
                    role: "Caches fetched results",
                    pins: ["entries: [Item]", "store() -> Void"]
                ),
                PatternPaletteNodeSpec(
                    name: "Data Source",
                    pattern: displayName,
                    role: "Talks to the persistent backing store",
                    pins: ["load() -> Void", "persist() -> Void"]
                )
            ]
        case .adapter:
            return [
                PatternPaletteNodeSpec(
                    name: "Adapter",
                    pattern: displayName,
                    role: "Translates between new and legacy APIs",
                    pins: ["adapt() -> Void", "source: LegacyAPI"]
                ),
                PatternPaletteNodeSpec(
                    name: "Legacy API",
                    pattern: displayName,
                    role: "Represents the existing interface boundary",
                    pins: ["request() -> Void", "response: Data"]
                )
            ]
        case .factory:
            return [
                PatternPaletteNodeSpec(
                    name: "Factory",
                    pattern: displayName,
                    role: "Builds configured feature objects",
                    pins: ["make() -> Product", "config: Configuration"]
                ),
                PatternPaletteNodeSpec(
                    name: "Product",
                    pattern: displayName,
                    role: "Represents the created object graph",
                    pins: ["run() -> Void"]
                ),
                PatternPaletteNodeSpec(
                    name: "Catalog",
                    pattern: displayName,
                    role: "Provides product metadata and presets",
                    pins: ["lookup() -> Product"]
                )
            ]
        case .service:
            return [
                PatternPaletteNodeSpec(
                    name: "Service",
                    pattern: displayName,
                    role: "Hosts a single feature service",
                    pins: ["perform() -> Void", "state: State"]
                )
            ]
        case .coordinator:
            return [
                PatternPaletteNodeSpec(
                    name: "Coordinator",
                    pattern: displayName,
                    role: "Coordinates a feature flow",
                    pins: ["start() -> Void", "stop() -> Void"]
                )
            ]
        case .delegate:
            return [
                PatternPaletteNodeSpec(
                    name: "Delegate",
                    pattern: displayName,
                    role: "Handles callbacks for the feature",
                    pins: ["didUpdate() -> Void", "context: Context"]
                )
            ]
        case .generic:
            return [
                PatternPaletteNodeSpec(
                    name: "Component",
                    pattern: "",
                    role: "A blank starter node",
                    pins: ["value: Value"]
                )
            ]
        }
    }

    var connections: [PatternPaletteConnectionSpec] {
        switch self {
        case .observer:
            return [
                PatternPaletteConnectionSpec(fromIndex: 0, toIndex: 1, type: "observes"),
                PatternPaletteConnectionSpec(fromIndex: 1, toIndex: 2, type: "calls")
            ]
        case .repository:
            return [
                PatternPaletteConnectionSpec(fromIndex: 0, toIndex: 1, type: "owns"),
                PatternPaletteConnectionSpec(fromIndex: 0, toIndex: 2, type: "calls")
            ]
        case .adapter:
            return [
                PatternPaletteConnectionSpec(fromIndex: 0, toIndex: 1, type: "adapts")
            ]
        case .factory:
            return [
                PatternPaletteConnectionSpec(fromIndex: 0, toIndex: 1, type: "owns"),
                PatternPaletteConnectionSpec(fromIndex: 0, toIndex: 2, type: "calls")
            ]
        case .service, .coordinator, .delegate, .generic:
            return []
        }
    }
}

struct PatternPaletteNodeSpec {
    var name: String
    var pattern: String
    var role: String
    var pins: [String]
}

struct PatternPaletteConnectionSpec {
    var fromIndex: Int
    var toIndex: Int
    var type: String
}

enum PatternPaletteInsertion {
    static func apply(_ template: PatternPaletteTemplate, to model: inout WorkbenchModel) {
        var usedNames = Set(model.outskirts.map(\.name))
        usedNames.formUnion(model.inskirts.map(\.name))
        usedNames.formUnion(model.beachBlankets.map(\.name))

        var names: [String] = []

        for spec in template.nodes {
            let name = uniqueName(for: spec.name, usedNames: &usedNames)
            names.append(name)
            model.addInskirts(
                InskirtsNode(
                    name: name,
                    pattern: spec.pattern,
                    role: spec.role,
                    pins: spec.pins
                )
            )
        }

        for spec in template.connections where spec.fromIndex < names.count && spec.toIndex < names.count {
            model.addConnection(
                Connection(
                    from: names[spec.fromIndex],
                    to: names[spec.toIndex],
                    type: spec.type
                )
            )
        }

        if let blanketName = template.blanketName {
            model.addBeachBlanket(
                BeachBlanket(name: uniqueName(for: blanketName, usedNames: &usedNames), nodes: names)
            )
        }
    }

    private static func uniqueName(for base: String, usedNames: inout Set<String>) -> String {
        var candidate = base
        var suffix = 2

        while usedNames.contains(candidate) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }

        usedNames.insert(candidate)
        return candidate
    }
}
