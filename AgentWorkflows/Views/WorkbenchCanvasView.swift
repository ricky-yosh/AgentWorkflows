import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkbenchCanvasView: View {
    let session: Session
    let canvasFileStore: CanvasFileStore
    let canvasLayoutStore: CanvasLayoutStore
    var isDrawerPresented: Bool = false
    let isExcavationRunning: Bool
    let onRunExcavate: () -> Void

    @AppStorage("workbenchCanvasShowsGrid") private var showsGrid: Bool = false
    @State private var zoom: Double = 1
    @State private var pan: CGSize = .zero
    @State private var hasSeededViewport = false
    @State private var armedDraft: CanvasConnectionDraft?
    @State private var hoveredPin: CanvasPinReference?
    @State private var selectedNodeName: String?
    @State private var selectedConnection: Connection?
    @State private var pendingPrompt: CanvasConnectionTypePrompt?
    @State private var nodePositions: [String: CGPoint] = [:]
    @State private var blanketDraft: CanvasBeachBlanketDraft?

    private var notices: [WorkbenchNotice] {
        WorkbenchNoticeResolver.notices(
            for: canvasFileStore.model,
            warningPayload: canvasFileStore.warningPayload
        )
    }

    private var nodePresentations: [CanvasNodePresentation] {
        CanvasNodePresentationFactory.presentations(for: canvasFileStore.model)
    }

    private var placements: [CanvasNodePlacement] {
        CanvasNodeLayoutPlanner.placements(for: nodePresentations, overrides: nodePositions)
    }

    private var inspectorVisible: Bool {
        selectedNodeName != nil || selectedConnection != nil
    }

    private let inspectorWidth: CGFloat = 340

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { proxy in
                let viewportSize = proxy.size

                VStack(spacing: 0) {
                    canvasToolbar(in: viewportSize)
                    Divider()
                    ZStack(alignment: .topLeading) {
                        canvasBackground
                        if showsGrid {
                            CanvasGridOverlay(zoom: zoom, pan: pan)
                        }

                        CanvasBeachBlanketLayer(
                            model: canvasFileStore.model,
                            placements: placements,
                            zoom: zoom,
                            pan: pan,
                            canvasSize: viewportSize
                        )

                        CanvasSceneView(
                            placements: placements,
                            model: canvasFileStore.model,
                            zoom: zoom,
                            pan: pan,
                            canvasSize: viewportSize,
                            armedDraft: armedDraft,
                            hoveredPin: hoveredPin,
                            selectedNodeName: selectedNodeName,
                            selectedConnection: selectedConnection
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        CanvasConnectionInteractionSurface(
                            placements: placements,
                            model: canvasFileStore.model,
                            layout: canvasLayoutStore.layout,
                            zoom: zoom,
                            pan: pan,
                            canvasSize: viewportSize,
                            armedDraft: $armedDraft,
                            hoveredPin: $hoveredPin,
                            selectedNodeName: $selectedNodeName,
                            selectedConnection: $selectedConnection,
                            pendingPrompt: $pendingPrompt,
                            nodePositions: $nodePositions,
                            onCreateBlanket: createBlanket,
                            onCommitConnection: commitConnection,
                            onDeleteConnection: deleteConnection,
                            onAddReroute: addRerouteWaypoint
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if let blanketDraft,
                           let frame = CanvasBeachBlanketGeometry.frame(
                            for: blanketDraft.memberNames,
                            placements: placements,
                            zoom: zoom,
                            pan: pan,
                            canvasSize: viewportSize
                           ) {
                            CanvasBeachBlanketDraftField(
                                name: blanketDraft.name,
                                frame: frame,
                                onCommit: finalizeBlanketName,
                                onCancel: cancelBlanketDraft
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }

                        if !notices.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(notices) { notice in
                                    WorkbenchNoticeCard(notice: notice)
                                }
                            }
                            .padding(16)
                        }

                        if let prompt = pendingPrompt {
                            CanvasConnectionTypeChooser(
                                prompt: prompt,
                                onSelect: commitPendingConnection,
                                onCancel: cancelPendingConnection
                            )
                            .position(
                                x: min(max(prompt.location.x + 120, 180), viewportSize.width - 180),
                                y: min(max(prompt.location.y - 80, 120), viewportSize.height - 120)
                            )
                        }
                    }
                    .onDrop(
                        of: [UTType.plainText.identifier],
                        delegate: PatternPaletteDropDelegate { template in
                            applyPaletteTemplate(template)
                        }
                    )
                    .overlay(alignment: .bottomTrailing) {
                        CanvasMiniMapPill(
                            model: canvasFileStore.model,
                            zoom: zoom,
                            isDrawerPresented: isDrawerPresented
                        )
                        .padding(.trailing, 16)
                        .padding(.bottom, isDrawerPresented ? 240 : 16)
                    }
                }
                .task(id: canvasFileStore.model) {
                    seedViewportIfNeeded(in: viewportSize)
                    seedNodePositionsIfNeeded()
                    pruneStaleSelection()
                }
                .onChange(of: canvasFileStore.model) { _, _ in
                    if canvasFileStore.model.outskirts.isEmpty && canvasFileStore.model.inskirts.isEmpty {
                        return
                    }
                    if !hasSeededViewport {
                        seedViewportIfNeeded(in: viewportSize)
                    }
                    seedNodePositionsIfNeeded()
                    pruneStaleSelection()
                }
                .onChange(of: nodePositions) { _, _ in
                    syncBlanketMemberships(in: viewportSize)
                }
            }

            if inspectorVisible {
                Divider()
                WorkbenchInspectorPanel(
                    session: session,
                    canvasFileStore: canvasFileStore,
                    selectedNodeName: $selectedNodeName,
                    selectedConnection: $selectedConnection
                )
                .frame(width: inspectorWidth)
            }
        }
    }

    private func canvasToolbar(in viewportSize: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workbench")
                        .font(.headline)
                    Text(session.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button("Finalize Canvas") {
                    finalizeCanvas()
                }
                .help("Write ARCHITECTURE.toml")

                Button("Run") {
                    onRunExcavate()
                }
                .disabled(isExcavationRunning)
                .help("Re-run excavate")

                Button {
                    adjustZoom(by: 1.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom In")

                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 52)

                Button {
                    adjustZoom(by: 0.8)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom Out")

                Button {
                    fitToContent(in: viewportSize)
                } label: {
                    Image(systemName: "scope")
                }
                .help("Fit Content (⌘0)")
                .keyboardShortcut("0", modifiers: .command)

                Toggle(isOn: $showsGrid) {
                    Image(systemName: showsGrid ? "grid" : "grid.circle")
                }
                .toggleStyle(.button)
                .help("Toggle Grid")
            }

            if let warning = WorkbenchCanvasFinalizationState.warning(for: canvasFileStore.model) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(warning)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var canvasBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: NSColor(calibratedWhite: 0.11, alpha: 1)),
                Color(nsColor: NSColor(calibratedWhite: 0.09, alpha: 1))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            Rectangle()
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    private func seedViewportIfNeeded(in size: CGSize) {
        guard !hasSeededViewport else { return }
        hasSeededViewport = true
        fitToContent(in: size)
    }

    private func fitToContent(in size: CGSize) {
        let transform = CanvasNodeLayoutPlanner.fitTransform(
            for: placements,
            in: size
        )
        zoom = transform.zoom
        pan = transform.pan
    }

    private func adjustZoom(by factor: Double) {
        zoom = CanvasNodeLayoutPlanner.clampedZoom(zoom * factor)
    }

    private func applyZoomAdjustment(_ delta: CGFloat) {
        guard delta != 0 else { return }
        let factor = 1 + Double(delta) * 0.008
        let nextZoom = CanvasNodeLayoutPlanner.clampedZoom(zoom * factor)
        if nextZoom != zoom {
            zoom = nextZoom
        }
    }

    private func commitConnection(_ connection: Connection) {
        var model = canvasFileStore.model
        model.addConnection(connection)
        try? canvasFileStore.save(model)
        selectedConnection = connection
        selectedNodeName = nil
    }

    private func deleteConnection(_ connection: Connection) {
        var model = canvasFileStore.model
        model.removeConnection(from: connection.from, to: connection.to, type: connection.type)
        try? canvasFileStore.save(model)
        if selectedConnection == connection {
            selectedConnection = nil
        }
        if selectedNodeName != nil {
            selectedNodeName = nil
        }
    }

    private func addRerouteWaypoint(_ reroute: CanvasRerouteWaypoint) {
        var layout = canvasLayoutStore.layout
        layout.reroutes.append(reroute)
        try? canvasLayoutStore.save(layout)
    }

    private func finalizeCanvas() {
        let url = SessionDirectoryLayout.architectureFileURL(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: session.id
        )

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try ArchitectureSerializer.render(canvasFileStore.model).write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            return
        }
    }

    private func commitPendingConnection(type: CanvasConnectionType) {
        guard let prompt = pendingPrompt else { return }
        commitConnection(Connection(from: prompt.from, to: prompt.to, type: type.rawValue))
        pendingPrompt = nil
        armedDraft = nil
        hoveredPin = nil
        selectedNodeName = nil
    }

    private func cancelPendingConnection() {
        pendingPrompt = nil
    }

    private func applyPaletteTemplate(_ template: PatternPaletteTemplate) {
        var model = canvasFileStore.model
        PatternPaletteInsertion.apply(template, to: &model)
        try? canvasFileStore.save(model)
    }

    private func seedNodePositionsIfNeeded() {
        for placement in placements where nodePositions[placement.presentation.name] == nil {
            nodePositions[placement.presentation.name] = placement.worldPosition
        }
    }

    private func createBlanket(memberNames: [String]) {
        guard !memberNames.isEmpty else { return }

        var model = canvasFileStore.model
        let usedNames = Set(model.beachBlankets.map(\.name))
            .union(model.outskirts.map(\.name))
            .union(model.inskirts.map(\.name))
        let blanketName = CanvasBeachBlanketGeometry.uniqueName(
            for: "Beach Blanket",
            usedNames: usedNames
        )
        model.addBeachBlanket(BeachBlanket(name: blanketName, nodes: memberNames))
        try? canvasFileStore.save(model)
        blanketDraft = CanvasBeachBlanketDraft(name: blanketName, memberNames: memberNames)
    }

    private func finalizeBlanketName(_ newName: String) {
        guard let draft = blanketDraft else { return }

        var model = canvasFileStore.model
        let usedNames = Set(model.beachBlankets.map(\.name))
            .subtracting([draft.name])
            .union(model.outskirts.map(\.name))
            .union(model.inskirts.map(\.name))
        let uniqueName = CanvasBeachBlanketGeometry.uniqueName(for: newName, usedNames: usedNames)

        guard model.renameBeachBlanket(from: draft.name, to: uniqueName) else {
            blanketDraft = nil
            return
        }

        try? canvasFileStore.save(model)
        blanketDraft = nil
    }

    private func cancelBlanketDraft() {
        blanketDraft = nil
    }

    private func syncBlanketMemberships(in viewportSize: CGSize) {
        guard !canvasFileStore.model.beachBlankets.isEmpty else { return }

        var model = canvasFileStore.model
        for placement in placements {
            CanvasBeachBlanketGeometry.syncMembership(
                for: placement.presentation.name,
                in: &model,
                placements: placements,
                zoom: zoom,
                pan: pan,
                canvasSize: viewportSize
            )
        }
        guard model != canvasFileStore.model else { return }
        try? canvasFileStore.save(model)
    }

    private func pruneStaleSelection() {
        if let selectedConnection,
           !canvasFileStore.model.connections.contains(selectedConnection) {
            self.selectedConnection = nil
        }
        if let selectedNodeName,
           !canvasFileStore.model.containsNode(named: selectedNodeName) {
            self.selectedNodeName = nil
        }
        if let armedDraft,
           !canvasFileStore.model.containsNode(named: armedDraft.source.nodeName) {
            self.armedDraft = nil
        }
        nodePositions = nodePositions.filter { canvasFileStore.model.containsNode(named: $0.key) }
        if let blanketDraft,
           !canvasFileStore.model.beachBlankets.contains(where: { $0.name == blanketDraft.name }) {
            self.blanketDraft = nil
        }
    }
}

enum WorkbenchCanvasFinalizationState {
    static func warning(for model: WorkbenchModel) -> String? {
        guard model.connections.isEmpty else { return nil }
        return "Canvas has no connections - ARCHITECTURE.toml will be nearly empty"
    }
}

private struct PatternPaletteDropDelegate: DropDelegate {
    let onDropTemplate: (PatternPaletteTemplate) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText.identifier])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.plainText.identifier]).first else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let rawValue = object as? String,
                  let template = PatternPaletteTemplate(rawValue: rawValue) else {
                return
            }
            Task { @MainActor in
                onDropTemplate(template)
            }
        }
        return true
    }
}

private struct CanvasSceneView: View {
    let placements: [CanvasNodePlacement]
    let model: WorkbenchModel
    let zoom: Double
    let pan: CGSize
    let canvasSize: CGSize
    let armedDraft: CanvasConnectionDraft?
    let hoveredPin: CanvasPinReference?
    let selectedNodeName: String?
    let selectedConnection: Connection?

    var body: some View {
        ZStack {
            ForEach(placements) { placement in
                CanvasNodeCardView(
                    model: model,
                    presentation: placement.presentation,
                    width: placement.size.width,
                    height: placement.size.height,
                    accent: CanvasNodePresentationFactory.accentColor(for: placement.presentation),
                    armedDraft: armedDraft,
                    hoveredPin: hoveredPin,
                    isSelected: selectedNodeName == placement.presentation.name,
                    selectedConnection: selectedConnection
                )
                .position(
                    x: canvasSize.width / 2 + placement.worldPosition.x * zoom + pan.width,
                    y: canvasSize.height / 2 + placement.worldPosition.y * zoom + pan.height
                )
                .scaleEffect(zoom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CanvasMiniMapPill: View {
    let model: WorkbenchModel
    let zoom: Double
    let isDrawerPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Mini Map")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(model.outskirts.count + model.inskirts.count) nodes")
                    .font(.caption)
            }

            Spacer(minLength: 0)

            Text("\(Int((zoom * 100).rounded()))%")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: 172)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 6)
        .offset(y: isDrawerPresented ? -8 : 0)
    }
}

private struct CanvasGridOverlay: View {
    let zoom: Double
    let pan: CGSize

    var body: some View {
        Canvas { context, size in
            let spacing = 40.0 * zoom
            guard spacing >= 8 else { return }

            let centerX = size.width / 2 + pan.width
            let centerY = size.height / 2 + pan.height

            let startX = centerX.truncatingRemainder(dividingBy: spacing)
            let startY = centerY.truncatingRemainder(dividingBy: spacing)

            var path = Path()

            var x = startX
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }

            var y = startY
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }

            context.stroke(path, with: .color(Color.white.opacity(0.045)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct CanvasInteractionSurface: NSViewRepresentable {
    let onPan: (CGSize) -> Void
    let onZoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.onPan = onPan
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        nsView.onPan = onPan
        nsView.onZoom = onZoom
    }

    final class InteractionView: NSView {
        var onPan: ((CGSize) -> Void)?
        var onZoom: ((CGFloat) -> Void)?
        private var lastMousePoint: CGPoint?

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            self
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            lastMousePoint = convert(event.locationInWindow, from: nil)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let lastMousePoint else { return }
            let point = convert(event.locationInWindow, from: nil)
            onPan?(CGSize(width: point.x - lastMousePoint.x, height: point.y - lastMousePoint.y))
            self.lastMousePoint = point
        }

        override func mouseUp(with event: NSEvent) {
            lastMousePoint = nil
        }

        override func scrollWheel(with event: NSEvent) {
            onZoom?(event.scrollingDeltaY)
        }

        override func magnify(with event: NSEvent) {
            onZoom?(event.magnification * 120)
        }
    }
}

private struct CanvasNodeCardView: View {
    let model: WorkbenchModel
    let presentation: CanvasNodePresentation
    let width: CGFloat
    let height: CGFloat
    let accent: Color
    let armedDraft: CanvasConnectionDraft?
    let hoveredPin: CanvasPinReference?
    let isSelected: Bool
    let selectedConnection: Connection?

    private var tooltip: String {
        presentation.role
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.kindLabel.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
                .tracking(0.8)
                .textCase(.uppercase)

            Text(presentation.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let filePath = presentation.filePath {
                Text(filePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !presentation.properties.isEmpty {
                CanvasPinColumn(
                    title: "Properties",
                    pins: presentation.properties,
                    alignment: .leading,
                    accent: accent,
                    stateProvider: { pin in
                        pinVisualState(for: pin, role: .input)
                    }
                )
            }

            if !presentation.methods.isEmpty {
                CanvasPinColumn(
                    title: "Methods",
                    pins: presentation.methods,
                    alignment: .trailing,
                    accent: accent,
                    stateProvider: { pin in
                        pinVisualState(for: pin, role: .output)
                    }
                )
            }
        }
        .padding(16)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: NSColor(calibratedWhite: 0.17, alpha: 1)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.95), lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.18), radius: 18, x: 0, y: 10)
        .shadow(color: isSelected ? accent.opacity(0.35) : .clear, radius: isSelected ? 10 : 0, x: 0, y: 0)
        .help(tooltip)
    }

    private func pinVisualState(for pin: String, role: CanvasPinRole) -> CanvasPinVisualState {
        if armedDraft?.source.nodeName == presentation.name,
           armedDraft?.source.pin == pin,
           armedDraft?.source.role == role {
            return .armed
        }
        if hoveredPin?.nodeName == presentation.name,
           hoveredPin?.pin == pin,
           hoveredPin?.role == role {
            return .hovered
        }
        if isSelected {
            return .selected
        }
        if let selectedConnection,
           (selectedConnection.from == presentation.name || selectedConnection.to == presentation.name) {
            return .selected
        }
        return .normal
    }
}

private struct CanvasPinColumn: View {
    let title: String
    let pins: [String]
    let alignment: HorizontalAlignment
    let accent: Color
    let stateProvider: (String) -> CanvasPinVisualState

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.7)

            ForEach(pins, id: \.self) { pin in
                CanvasPinRow(
                    pin: pin,
                    alignment: alignment,
                    accent: accent,
                    state: stateProvider(pin)
                )
            }
        }
    }
}

private struct CanvasPinRow: View {
    let pin: String
    let alignment: HorizontalAlignment
    let accent: Color
    let state: CanvasPinVisualState

    var body: some View {
        HStack(spacing: 8) {
            if alignment == .leading {
                CanvasPinDot(accent: accent, state: state)
            }

            Text(pin)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if alignment == .trailing {
                CanvasPinDot(accent: accent, state: state)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

private struct CanvasPinDot: View {
    let accent: Color
    let state: CanvasPinVisualState

    var body: some View {
        Circle()
            .fill(fillColor)
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle()
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 0)
            .scaleEffect(scale)
    }

    private var fillColor: Color {
        switch state {
        case .normal:
            return Color.white.opacity(0.65)
        case .hovered, .armed, .selected:
            return accent
        }
    }

    private var borderColor: Color {
        switch state {
        case .normal:
            return Color.black.opacity(0.3)
        case .hovered, .armed, .selected:
            return Color.white.opacity(0.6)
        }
    }

    private var diameter: CGFloat {
        switch state {
        case .normal: return 8
        case .hovered: return 11
        case .armed: return 11
        case .selected: return 9
        }
    }

    private var scale: CGFloat {
        switch state {
        case .normal: return 1
        case .hovered: return 1.1
        case .armed: return 1.15
        case .selected: return 1
        }
    }

    private var shadowColor: Color {
        switch state {
        case .normal:
            return .clear
        case .hovered, .armed:
            return accent.opacity(0.7)
        case .selected:
            return accent.opacity(0.35)
        }
    }

    private var shadowRadius: CGFloat {
        switch state {
        case .normal:
            return 0
        case .hovered, .armed:
            return 6
        case .selected:
            return 3
        }
    }
}

private enum CanvasPinVisualState {
    case normal
    case hovered
    case armed
    case selected
}

struct CanvasNodePresentation: Identifiable, Equatable {
    enum Kind: Equatable {
        case outskirts
        case inskirts
    }

    var id: String
    var kind: Kind
    var kindLabel: String
    var name: String
    var filePath: String?
    var role: String
    var pattern: String
    var properties: [String]
    var methods: [String]
}

struct CanvasNodePlacement: Identifiable, Equatable {
    var id: String
    var presentation: CanvasNodePresentation
    var worldPosition: CGPoint
    var size: CGSize
}

struct CanvasViewportTransform: Equatable {
    var zoom: Double
    var pan: CGSize
}

enum CanvasNodePresentationFactory {
    static func presentations(for model: WorkbenchModel) -> [CanvasNodePresentation] {
        model.inskirts.map {
            makeInskirtsPresentation($0)
        } + model.outskirts.map {
            makeOutskirtsPresentation($0)
        }
    }

    static func accentColor(for presentation: CanvasNodePresentation) -> Color {
        accentColor(forPattern: presentation.pattern)
    }

    static func accentNSColor(for presentation: CanvasNodePresentation) -> NSColor {
        nsColor(for: accentToken(forPattern: presentation.pattern))
    }

    static func accentColor(forPattern pattern: String?) -> Color {
        color(for: accentToken(forPattern: pattern))
    }

    static func accentToken(forPattern pattern: String?) -> CanvasAccentToken {
        let normalized = pattern?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalized {
        case "observer":
            return .observer
        case "repository":
            return .repository
        case "adapter":
            return .adapter
        case "factory":
            return .factory
        case "service":
            return .service
        case "coordinator":
            return .coordinator
        case "delegate":
            return .delegate
        default:
            return .unknown
        }
    }

    static func classifyPins(_ pins: [String]) -> (properties: [String], methods: [String]) {
        var properties: [String] = []
        var methods: [String] = []
        for pin in pins {
            if pin.contains("(") {
                methods.append(pin)
            } else {
                properties.append(pin)
            }
        }
        return (properties, methods)
    }

    static func estimatedSize(for presentation: CanvasNodePresentation) -> CGSize {
        let longestLine = [
            presentation.kindLabel,
            presentation.name,
            presentation.filePath ?? "",
            presentation.properties.max(by: { $0.count < $1.count }) ?? "",
            presentation.methods.max(by: { $0.count < $1.count }) ?? ""
        ].map(\.count).max() ?? 0

        let width = clampedCardWidth(Double(longestLine) * 7 + 112)
        let lineCount = 3 + max(1, presentation.properties.count) + max(1, presentation.methods.count)
        let height = max(180, CGFloat(lineCount) * 24 + 52)
        return CGSize(width: width, height: height)
    }

    private static func makeOutskirtsPresentation(_ node: OutskirtsNode) -> CanvasNodePresentation {
        let pins = classifyPins(node.pins)
        return CanvasNodePresentation(
            id: "outskirts:\(node.name)",
            kind: .outskirts,
            kindLabel: "Outskirts",
            name: node.name,
            filePath: node.file,
            role: node.role,
            pattern: "Outskirts",
            properties: pins.properties,
            methods: pins.methods
        )
    }

    private static func makeInskirtsPresentation(_ node: InskirtsNode) -> CanvasNodePresentation {
        let pins = classifyPins(node.pins)
        return CanvasNodePresentation(
            id: "inskirts:\(node.name)",
            kind: .inskirts,
            kindLabel: node.pattern.isEmpty ? "Generic" : node.pattern,
            name: node.name,
            filePath: nil,
            role: node.role,
            pattern: node.pattern,
            properties: pins.properties,
            methods: pins.methods
        )
    }

    private static func color(hue: CGFloat) -> Color {
        Color(nsColor: NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.75, alpha: 1))
    }

    private static func color(for token: CanvasAccentToken) -> Color {
        switch token {
        case .observer:
            return color(hue: 0.50)
        case .repository:
            return color(hue: 0.77)
        case .adapter:
            return color(hue: 0.24)
        case .factory:
            return color(hue: 0.95)
        case .service:
            return color(hue: 0.58)
        case .coordinator:
            return color(hue: 0.32)
        case .delegate:
            return color(hue: 0.09)
        case .unknown:
            return Color(nsColor: NSColor(calibratedWhite: 0.52, alpha: 1))
        }
    }

    private static func nsColor(for token: CanvasAccentToken) -> NSColor {
        switch token {
        case .observer:
            return NSColor(calibratedHue: 0.50, saturation: 0.55, brightness: 0.75, alpha: 1)
        case .repository:
            return NSColor(calibratedHue: 0.77, saturation: 0.55, brightness: 0.75, alpha: 1)
        case .adapter:
            return NSColor(calibratedHue: 0.24, saturation: 0.55, brightness: 0.75, alpha: 1)
        case .factory:
            return NSColor(calibratedHue: 0.95, saturation: 0.55, brightness: 0.75, alpha: 1)
        case .service:
            return NSColor(calibratedHue: 0.58, saturation: 0.55, brightness: 0.75, alpha: 1)
        case .coordinator:
            return NSColor(calibratedHue: 0.32, saturation: 0.55, brightness: 0.75, alpha: 1)
        case .delegate:
            return NSColor(calibratedHue: 0.09, saturation: 0.55, brightness: 0.75, alpha: 1)
        case .unknown:
            return NSColor(calibratedWhite: 0.52, alpha: 1)
        }
    }

    private static func clampedCardWidth(_ width: Double) -> CGFloat {
        CGFloat(min(max(width, 120), 300))
    }
}

enum CanvasAccentToken: Equatable {
    case observer
    case repository
    case adapter
    case factory
    case service
    case coordinator
    case delegate
    case unknown
}

enum CanvasNodeLayoutPlanner {
    static func placements(for presentations: [CanvasNodePresentation]) -> [CanvasNodePlacement] {
        placements(for: presentations, overrides: [:])
    }

    static func placements(
        for presentations: [CanvasNodePresentation],
        overrides: [String: CGPoint]
    ) -> [CanvasNodePlacement] {
        let outskirts = presentations.filter { $0.kind == .outskirts }
        let inskirts = presentations.filter { $0.kind == .inskirts }

        let outskirtsPlacements = layoutOutskirts(outskirts, overrides: overrides)
        let inskirtsPlacements = layoutInskirts(inskirts, overrides: overrides)
        return inskirtsPlacements + outskirtsPlacements
    }

    static func fitTransform(
        for placements: [CanvasNodePlacement],
        in availableSize: CGSize,
        zoom: Double? = nil,
        pan: CGSize? = nil
    ) -> CanvasViewportTransform {
        guard !placements.isEmpty, availableSize != .zero else {
            return CanvasViewportTransform(zoom: zoom ?? 1, pan: pan ?? .zero)
        }

        let bounds = placements.reduce(into: CGRect.null) { partialResult, placement in
            partialResult = partialResult.union(
                CGRect(
                    x: placement.worldPosition.x - placement.size.width / 2,
                    y: placement.worldPosition.y - placement.size.height / 2,
                    width: placement.size.width,
                    height: placement.size.height
                )
            )
        }

        guard bounds.width > 0, bounds.height > 0 else {
            return CanvasViewportTransform(zoom: zoom ?? 1, pan: pan ?? .zero)
        }

        let desiredZoom = zoom ?? clampedZoom(
            min(
                (availableSize.width - 160) / bounds.width,
                (availableSize.height - 160) / bounds.height
            )
        )
        let nextZoom = clampedZoom(desiredZoom)
        let nextPan = pan ?? CGSize(
            width: -bounds.midX * nextZoom,
            height: -bounds.midY * nextZoom
        )
        return CanvasViewportTransform(zoom: nextZoom, pan: nextPan)
    }

    static func clampedZoom(_ zoom: Double) -> Double {
        min(max(zoom, 0.25), 4)
    }

    private static func layoutOutskirts(
        _ presentations: [CanvasNodePresentation],
        overrides: [String: CGPoint]
    ) -> [CanvasNodePlacement] {
        guard !presentations.isEmpty else { return [] }

        let radius = 430 + Double(max(0, presentations.count - 1)) * 22
        return presentations.enumerated().map { index, presentation in
            let angle = (Double(index) / Double(presentations.count)) * (2 * Double.pi) - (.pi / 2)
            let point = overrides[presentation.name] ?? CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            return CanvasNodePlacement(
                id: presentation.id,
                presentation: presentation,
                worldPosition: point,
                size: CanvasNodePresentationFactory.estimatedSize(for: presentation)
            )
        }
    }

    private static func layoutInskirts(
        _ presentations: [CanvasNodePresentation],
        overrides: [String: CGPoint]
    ) -> [CanvasNodePlacement] {
        guard !presentations.isEmpty else { return [] }

        let sorted = presentations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let width = sorted.map { CanvasNodePresentationFactory.estimatedSize(for: $0).width }.max() ?? 220
        let spacing = max(width + 72, 240)
        let columns = max(1, Int(ceil(sqrt(Double(sorted.count)))))
        let rows = Int(ceil(Double(sorted.count) / Double(columns)))
        let totalWidth = Double(columns - 1) * spacing
        let totalHeight = Double(rows - 1) * spacing

        return sorted.enumerated().map { index, presentation in
            let row = index / columns
            let column = index % columns
            let point = overrides[presentation.name] ?? CGPoint(
                x: Double(column) * spacing - totalWidth / 2,
                y: Double(row) * spacing - totalHeight / 2
            )
            return CanvasNodePlacement(
                id: presentation.id,
                presentation: presentation,
                worldPosition: point,
                size: CanvasNodePresentationFactory.estimatedSize(for: presentation)
            )
        }
    }
}
