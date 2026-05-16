import AppKit
import SwiftUI

struct CanvasBeachBlanketDraft: Equatable {
    var name: String
    var memberNames: [String]
}

enum CanvasBeachBlanketGeometry {
    static let padding = CGSize(width: 24, height: 18)

    static func memberNames(
        in selection: CGRect,
        placements: [CanvasNodePlacement],
        zoom: Double,
        pan: CGSize,
        canvasSize: CGSize
    ) -> [String] {
        placements.compactMap { placement in
            guard let frame = nodeFrame(
                for: placement,
                zoom: zoom,
                pan: pan,
                canvasSize: canvasSize
            ) else { return nil }
            return selection.intersects(frame) ? placement.presentation.name : nil
        }
    }

    static func frame(
        for blanket: BeachBlanket,
        excluding excludedNode: String? = nil,
        placements: [CanvasNodePlacement],
        zoom: Double,
        pan: CGSize,
        canvasSize: CGSize
    ) -> CGRect? {
        frame(
            for: blanket.nodes.filter { $0 != excludedNode },
            placements: placements,
            zoom: zoom,
            pan: pan,
            canvasSize: canvasSize
        )
    }

    static func frame(
        for memberNames: [String],
        placements: [CanvasNodePlacement],
        zoom: Double,
        pan: CGSize,
        canvasSize: CGSize
    ) -> CGRect? {
        let frames = placements.compactMap { placement -> CGRect? in
            guard memberNames.contains(placement.presentation.name) else { return nil }
            return nodeFrame(
                for: placement,
                zoom: zoom,
                pan: pan,
                canvasSize: canvasSize
            )
        }

        guard !frames.isEmpty else { return nil }

        let bounds = frames.reduce(CGRect.null) { partialResult, frame in
            partialResult.union(frame)
        }
        return bounds.insetBy(dx: -padding.width, dy: -padding.height)
    }

    static func nodeFrame(
        for placement: CanvasNodePlacement,
        zoom: Double,
        pan: CGSize,
        canvasSize: CGSize
    ) -> CGRect? {
        return CanvasPinGeometry.frame(
            for: placement,
            zoom: zoom,
            pan: pan,
            canvasSize: canvasSize
        )
    }

    static func selectionRect(start: CGPoint, current: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    static func uniqueName(for desiredName: String, usedNames: Set<String>) -> String {
        var candidate = desiredName
        var suffix = 2
        while usedNames.contains(candidate) {
            candidate = "\(desiredName) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    static func syncMembership(
        for nodeName: String,
        in model: inout WorkbenchModel,
        placements: [CanvasNodePlacement],
        zoom: Double,
        pan: CGSize,
        canvasSize: CGSize
    ) {
        guard let nodePlacement = placements.first(where: { $0.presentation.name == nodeName }) else {
            return
        }
        let nodeFrame = CanvasPinGeometry.frame(
            for: nodePlacement,
            zoom: zoom,
            pan: pan,
            canvasSize: canvasSize
        )

        let blanketNames = model.beachBlankets.map(\.name)
        for blanketName in blanketNames {
            let frame = frame(
                for: model.beachBlankets.first(where: { $0.name == blanketName }) ?? BeachBlanket(name: blanketName),
                excluding: nodeName,
                placements: placements,
                zoom: zoom,
                pan: pan,
                canvasSize: canvasSize
            )

            let containsNode = frame?.intersects(nodeFrame) ?? false
            let isMember = model.beachBlankets.first(where: { $0.name == blanketName })?.nodes.contains(nodeName) == true

            if containsNode {
                if !isMember {
                    model.addNode(nodeName, toBeachBlanketNamed: blanketName)
                }
            } else if isMember {
                model.removeNode(nodeName, fromBeachBlanketNamed: blanketName)
            }
        }
    }
}

struct CanvasBeachBlanketLayer: View {
    let model: WorkbenchModel
    let placements: [CanvasNodePlacement]
    let zoom: Double
    let pan: CGSize
    let canvasSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.beachBlankets, id: \.name) { blanket in
                if let frame = CanvasBeachBlanketGeometry.frame(
                    for: blanket,
                    placements: placements,
                    zoom: zoom,
                    pan: pan,
                    canvasSize: canvasSize
                ) {
                    CanvasBeachBlanketCard(name: blanket.name, frame: frame)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct CanvasBeachBlanketCard: View {
    let name: String
    let frame: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(nsColor: NSColor(calibratedWhite: 0.14, alpha: 0.7)))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            )
            .overlay(alignment: .topLeading) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))
                    )
                    .padding(10)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
}

struct CanvasBeachBlanketDraftField: View {
    let name: String
    let frame: CGRect
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    @State private var draftName: String
    @FocusState private var isFocused: Bool

    init(
        name: String,
        frame: CGRect,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.name = name
        self.frame = frame
        self.onCommit = onCommit
        self.onCancel = onCancel
        _draftName = State(initialValue: name)
    }

    var body: some View {
        TextField("Beach Blanket", text: $draftName)
            .font(.callout.weight(.semibold))
            .textFieldStyle(.roundedBorder)
            .frame(width: min(max(frame.width * 0.55, 180), 320))
            .position(x: frame.minX + 24, y: max(frame.minY + 22, 24))
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commit()
                }
            }
            .onSubmit { commit() }
            .onExitCommand {
                onCancel()
            }
    }

    private func commit() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onCancel()
            return
        }
        onCommit(trimmed)
    }
}
