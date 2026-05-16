import AppKit
import Foundation
import SwiftUI

enum CanvasConnectionType: String, CaseIterable, Identifiable, Equatable {
    case owns = "owns"
    case delegatesTo = "delegates to"
    case observes = "observes"
    case calls = "calls"
    case implements = "implements"
    case adapts = "adapts"

    var id: String { rawValue }
}

enum CanvasPinRole: Equatable {
    case input
    case output
}

struct CanvasPinReference: Hashable, Equatable {
    var nodeName: String
    var pin: String
    var role: CanvasPinRole
}

struct CanvasConnectionDraft: Equatable {
    var source: CanvasPinReference
}

struct CanvasConnectionTypePrompt: Identifiable, Equatable {
    var from: String
    var to: String
    var location: CGPoint
    var sourcePattern: String
    var destinationPattern: String

    var id: String {
        "\(from)->\(to)@\(location.x),\(location.y)"
    }
}

struct CanvasPinHit: Equatable {
    var reference: CanvasPinReference
    var center: CGPoint
    var radius: CGFloat
}

extension CanvasNodePresentationFactory {
    static func presentation(named name: String, in model: WorkbenchModel) -> CanvasNodePresentation? {
        presentations(for: model).first { $0.name == name }
    }
}

enum CanvasConnectionSuggestionEngine {
    static func suggestedType(from source: CanvasNodePresentation, to destination: CanvasNodePresentation) -> CanvasConnectionType? {
        let sourcePattern = normalizedPattern(source.pattern)
        let destinationPattern = normalizedPattern(destination.pattern)

        if sourcePattern == "protocol" {
            return .implements
        }
        if sourcePattern == "adapter" {
            return .adapts
        }
        if sourcePattern == "observer" && destinationPattern == "service" {
            return .observes
        }
        if sourcePattern == "coordinator" && (destinationPattern == "service" || destinationPattern == "delegate") {
            return .delegatesTo
        }
        if sourcePattern == "repository" && destinationPattern == "service" {
            return .calls
        }
        if sourcePattern == "factory" {
            return .owns
        }
        return nil
    }

    private static func normalizedPattern(_ pattern: String) -> String {
        pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum CanvasPinGeometry {
    static let snapRadius: CGFloat = 20
    static let wireHitTolerance: CGFloat = 10

    static func hits(
        for placement: CanvasNodePlacement,
        presentation: CanvasNodePresentation,
        zoom: Double,
        pan: CGSize,
        canvasSize: CGSize
    ) -> [CanvasPinHit] {
        let frame = frame(for: placement, zoom: zoom, pan: pan, canvasSize: canvasSize)
        let propertiesOffset = sectionOffset(for: presentation)
        let properties = pinHits(
            nodeName: presentation.name,
            pins: presentation.properties,
            role: .input,
            sideX: frame.minX + 12,
            frame: frame,
            sectionOffset: propertiesOffset
        )
        let methods = pinHits(
            nodeName: presentation.name,
            pins: presentation.methods,
            role: .output,
            sideX: frame.maxX - 12,
            frame: frame,
            sectionOffset: propertiesOffset + sectionBlockHeight(pinCount: presentation.properties.count)
        )
        return properties + methods
    }

    static func pinCenter(
        for reference: CanvasPinReference,
        placement: CanvasNodePlacement,
        presentation: CanvasNodePresentation,
        zoom: Double,
        pan: CGSize,
        canvasSize: CGSize
    ) -> CGPoint? {
        hits(for: placement, presentation: presentation, zoom: zoom, pan: pan, canvasSize: canvasSize)
            .first(where: { $0.reference == reference })?
            .center
    }

    static func frame(
        for placement: CanvasNodePlacement,
        zoom: Double,
        pan: CGSize,
        canvasSize: CGSize
    ) -> CGRect {
        let center = CGPoint(
            x: canvasSize.width / 2 + placement.worldPosition.x * zoom + pan.width,
            y: canvasSize.height / 2 + placement.worldPosition.y * zoom + pan.height
        )
        let size = CGSize(width: placement.size.width * zoom, height: placement.size.height * zoom)
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func pinHits(
        nodeName: String,
        pins: [String],
        role: CanvasPinRole,
        sideX: CGFloat,
        frame: CGRect,
        sectionOffset: CGFloat
    ) -> [CanvasPinHit] {
        guard !pins.isEmpty else { return [] }

        let rowHeight: CGFloat = 24
        let rowSpacing: CGFloat = 6
        let firstRowCenterY = frame.minY + sectionOffset + 18

        return pins.enumerated().map { index, pin in
            let center = CGPoint(
                x: sideX,
                y: firstRowCenterY + CGFloat(index) * (rowHeight + rowSpacing)
            )
            return CanvasPinHit(
                reference: CanvasPinReference(nodeName: nodeName, pin: pin, role: role),
                center: center,
                radius: snapRadius
            )
        }
    }

    private static func sectionOffset(for presentation: CanvasNodePresentation) -> CGFloat {
        var offset: CGFloat = 16
        offset += 12
        offset += 10
        offset += 22
        if presentation.filePath != nil {
            offset += 8
            offset += 14
        }
        offset += 10
        return offset
    }

    private static func sectionBlockHeight(pinCount: Int) -> CGFloat {
        guard pinCount > 0 else { return 26 }
        let rowHeight: CGFloat = 24
        let rowSpacing: CGFloat = 6
        let titleHeight: CGFloat = 14
        return titleHeight + CGFloat(pinCount) * rowHeight + CGFloat(max(0, pinCount - 1)) * rowSpacing + 10
    }
}

enum CanvasConnectionRouting {
    static func path(
        from start: CGPoint,
        to end: CGPoint,
        reroutes: [CGPoint] = []
    ) -> NSBezierPath {
        let path = NSBezierPath()
        let points = [start] + reroutes + [end]
        guard let first = points.first else { return path }

        path.move(to: first)
        for pair in zip(points, points.dropFirst()) {
            appendSegment(from: pair.0, to: pair.1, into: path)
        }
        return path
    }

    static func hitTest(
        point: CGPoint,
        model: WorkbenchModel,
        layout: CanvasLayout,
        placements: [CanvasNodePlacement],
        zoom: Double,
        pan: CGSize,
        canvasSize: CGSize
    ) -> Connection? {
        let presentations = Dictionary(uniqueKeysWithValues: CanvasNodePresentationFactory.presentations(for: model).map { ($0.name, $0) })
        for connection in model.connections.reversed() {
            guard
                let sourcePresentation = presentations[connection.from],
                let destinationPresentation = presentations[connection.to],
                let sourcePlacement = placements.first(where: { $0.presentation.name == connection.from }),
                let destinationPlacement = placements.first(where: { $0.presentation.name == connection.to })
            else { continue }

            guard
                let start = endpoint(
                    for: connection.from,
                    pinRole: .output,
                    placement: sourcePlacement,
                    presentation: sourcePresentation,
                    zoom: zoom,
                    pan: pan,
                    canvasSize: canvasSize,
                    fallbackSide: .output
                ),
                let end = endpoint(
                    for: connection.to,
                    pinRole: .input,
                    placement: destinationPlacement,
                    presentation: destinationPresentation,
                    zoom: zoom,
                    pan: pan,
                    canvasSize: canvasSize,
                    fallbackSide: .input
                )
            else { continue }

            let waypoints = reroutePoints(
                for: connection,
                layout: layout,
                zoom: zoom,
                pan: pan,
                canvasSize: canvasSize
            )
            let path = path(from: start, to: end, reroutes: waypoints)
            if pathContainsStroke(path, point: point, tolerance: CanvasPinGeometry.wireHitTolerance) {
                return connection
            }
        }
        return nil
    }

    static func reroutePoints(
        for connection: Connection,
        layout: CanvasLayout,
        zoom: Double,
        pan: CGSize,
        canvasSize: CGSize
    ) -> [CGPoint] {
        layout.reroutes
            .filter { $0.connectionFrom == connection.from && $0.connectionTo == connection.to }
            .sorted { $0.index < $1.index }
            .map {
                CGPoint(
                    x: canvasSize.width / 2 + $0.x * zoom + pan.width,
                    y: canvasSize.height / 2 + $0.y * zoom + pan.height
                )
            }
    }

    static func controlOffset(from start: CGPoint, to end: CGPoint) -> CGSize {
        let dx = end.x - start.x
        let dy = abs(end.y - start.y)
        if dx >= 0 {
            return CGSize(width: max(dx * 0.5, 90), height: 0)
        }
        let offset = max(dy * 0.5, 90)
        return CGSize(width: 0, height: start.y <= end.y ? offset : -offset)
    }

    private static func appendSegment(from start: CGPoint, to end: CGPoint, into path: NSBezierPath) {
        let offset = controlOffset(from: start, to: end)
        let firstControl: CGPoint
        let secondControl: CGPoint
        if offset.width != 0 {
            firstControl = CGPoint(x: start.x + offset.width, y: start.y)
            secondControl = CGPoint(x: end.x - offset.width, y: end.y)
        } else {
            firstControl = CGPoint(x: start.x, y: start.y + offset.height)
            secondControl = CGPoint(x: end.x, y: end.y - offset.height)
        }
        path.curve(to: end, controlPoint1: firstControl, controlPoint2: secondControl)
    }

    static func endpoint(
        for nodeName: String,
        pinRole: CanvasPinRole,
        placement: CanvasNodePlacement,
        presentation: CanvasNodePresentation,
        zoom: Double,
        pan: CGSize,
        canvasSize: CGSize,
        fallbackSide: CanvasPinRole
    ) -> CGPoint? {
        let hits = CanvasPinGeometry.hits(
            for: placement,
            presentation: presentation,
            zoom: zoom,
            pan: pan,
            canvasSize: canvasSize
        )
        let role = pinRole == .input ? CanvasPinRole.input : CanvasPinRole.output
        if let exact = hits.first(where: { $0.reference.role == role }) {
            return exact.center
        }
        return hits.first(where: { $0.reference.role == fallbackSide })?.center
    }

    private static func pathContainsStroke(_ path: NSBezierPath, point: CGPoint, tolerance: CGFloat) -> Bool {
        let cgPath = path.cgPath
        let stroked = cgPath.copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 4)
        return stroked.contains(point)
    }
}

struct CanvasConnectionChooserState: Equatable {
    var from: String
    var to: String
    var location: CGPoint
    var sourcePattern: String
    var destinationPattern: String
}

struct CanvasConnectionInteractionSurface: NSViewRepresentable {
    let placements: [CanvasNodePlacement]
    let model: WorkbenchModel
    let layout: CanvasLayout
    let zoom: Double
    let pan: CGSize
    let canvasSize: CGSize
    @Binding var armedDraft: CanvasConnectionDraft?
    @Binding var hoveredPin: CanvasPinReference?
    @Binding var selectedNodeName: String?
    @Binding var selectedConnection: Connection?
    @Binding var pendingPrompt: CanvasConnectionTypePrompt?
    @Binding var nodePositions: [String: CGPoint]
    let onCreateBlanket: ([String]) -> Void
    let onCommitConnection: (Connection) -> Void
    let onDeleteConnection: (Connection) -> Void
    let onAddReroute: (CanvasRerouteWaypoint) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.placements = placements
        view.model = model
        view.layout = layout
        view.zoom = zoom
        view.pan = pan
        view.canvasSize = canvasSize
        view.armedDraft = $armedDraft
        view.hoveredPin = $hoveredPin
        view.selectedNodeName = $selectedNodeName
        view.selectedConnection = $selectedConnection
        view.pendingPrompt = $pendingPrompt
        view.nodePositions = $nodePositions
        view.onCreateBlanket = onCreateBlanket
        view.onCommitConnection = onCommitConnection
        view.onDeleteConnection = onDeleteConnection
        view.onAddReroute = onAddReroute
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        nsView.placements = placements
        nsView.model = model
        nsView.layout = layout
        nsView.zoom = zoom
        nsView.pan = pan
        nsView.canvasSize = canvasSize
        nsView.armedDraft = $armedDraft
        nsView.hoveredPin = $hoveredPin
        nsView.selectedNodeName = $selectedNodeName
        nsView.selectedConnection = $selectedConnection
        nsView.pendingPrompt = $pendingPrompt
        nsView.nodePositions = $nodePositions
        nsView.onCreateBlanket = onCreateBlanket
        nsView.onCommitConnection = onCommitConnection
        nsView.onDeleteConnection = onDeleteConnection
        nsView.onAddReroute = onAddReroute
        nsView.needsDisplay = true
    }

    final class InteractionView: NSView {
        var placements: [CanvasNodePlacement] = []
        var model: WorkbenchModel = .init()
        var layout: CanvasLayout = .init()
        var zoom: Double = 1
        var pan: CGSize = .zero
        var canvasSize: CGSize = .zero
        var armedDraft: Binding<CanvasConnectionDraft?> = .constant(nil)
        var hoveredPin: Binding<CanvasPinReference?> = .constant(nil)
        var selectedNodeName: Binding<String?> = .constant(nil)
        var selectedConnection: Binding<Connection?> = .constant(nil)
        var pendingPrompt: Binding<CanvasConnectionTypePrompt?> = .constant(nil)
        var nodePositions: Binding<[String: CGPoint]> = .constant([:])
        var onCreateBlanket: (([String]) -> Void)?
        var onCommitConnection: ((Connection) -> Void)?
        var onDeleteConnection: ((Connection) -> Void)?
        var onAddReroute: ((CanvasRerouteWaypoint) -> Void)?
        private var trackingArea: NSTrackingArea?
        private var dragState: DragState?

        private enum DragState {
            case node(name: String, startLocation: CGPoint, startPosition: CGPoint)
            case blanketSelection(startLocation: CGPoint, currentLocation: CGPoint)
            case pan(startLocation: CGPoint, startPan: CGSize)
        }

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override var isOpaque: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.clear.setFill()
            dirtyRect.fill()

            drawConnections(in: dirtyRect)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            let location = convert(event.locationInWindow, from: nil)

            if event.modifierFlags.contains(.shift), let connection = hitConnection(at: location) {
                addReroute(for: connection, at: location)
                selectedConnection.wrappedValue = connection
                selectedNodeName.wrappedValue = nil
                return
            }

            if event.modifierFlags.contains(.option), hitNode(at: location) == nil {
                startBlanketSelection(at: location)
                return
            }

            if event.modifierFlags.contains(.option), hitNode(at: location) == nil {
                startBlanketSelection(at: location)
                return
            }

            if let pin = hitPin(at: location) {
                handlePinSelection(pin, at: location)
                return
            }

            if let nodeName = hitNode(at: location) {
                selectedNodeName.wrappedValue = nodeName
                selectedConnection.wrappedValue = nil
                armedDraft.wrappedValue = nil
                pendingPrompt.wrappedValue = nil
                hoveredPin.wrappedValue = nil
                dragState = .node(
                    name: nodeName,
                    startLocation: location,
                    startPosition: nodePosition(for: nodeName) ?? .zero
                )
                needsDisplay = true
                return
            }

            if let connection = hitConnection(at: location) {
                selectedConnection.wrappedValue = connection
                selectedNodeName.wrappedValue = nil
                armedDraft.wrappedValue = nil
                pendingPrompt.wrappedValue = nil
                hoveredPin.wrappedValue = nil
                dragState = .node(
                    name: nodeName,
                    startLocation: location,
                    startPosition: nodePosition(for: nodeName) ?? .zero
                )
                needsDisplay = true
                return
            }

            if event.modifierFlags.contains(.option) {
                return
            }

            cancelDraft()
            selectedNodeName.wrappedValue = nil
            selectedConnection.wrappedValue = nil
            dragState = .pan(startLocation: location, startPan: pan)
            needsDisplay = true
        }

        override func mouseMoved(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            updateHover(at: location)
        }

        override func mouseDragged(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)

            switch dragState {
            case .some(.node(let nodeName, let startLocation, let startPosition)):
                let delta = CGSize(
                    width: (location.x - startLocation.x) / zoom,
                    height: (location.y - startLocation.y) / zoom
                )
                nodePositions.wrappedValue[nodeName] = CGPoint(
                    x: startPosition.x + delta.width,
                    y: startPosition.y + delta.height
                )
                selectedNodeName.wrappedValue = nodeName
                needsDisplay = true
            case .some(.blanketSelection(let startLocation, _)):
                dragState = .blanketSelection(startLocation: startLocation, currentLocation: location)
                needsDisplay = true
            case .some(.pan(let startLocation, let startPan)):
                let delta = CGSize(
                    width: location.x - startLocation.x,
                    height: location.y - startLocation.y
                )
                pan = CGSize(width: startPan.width + delta.width, height: startPan.height + delta.height)
                needsDisplay = true
            case nil:
                mouseMoved(with: event)
            }
        }

        override func mouseUp(with event: NSEvent) {
            if case .some(.blanketSelection(let startLocation, let currentLocation)) = dragState {
                finalizeBlanketSelection(start: startLocation, current: currentLocation)
            }
            dragState = nil
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 51 || event.keyCode == 117 {
                deleteSelectedConnection()
                return
            }
            super.keyDown(with: event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let location = convert(event.locationInWindow, from: nil)
            guard let connection = hitConnection(at: location) else { return nil }
            selectedConnection.wrappedValue = connection

            let menu = NSMenu(title: "Connection")
            let item = NSMenuItem(
                title: "Delete Connection",
                action: #selector(deleteSelectedConnectionAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
            return menu
        }

        @objc private func deleteSelectedConnectionAction(_ sender: Any?) {
            deleteSelectedConnection()
        }

        private func startBlanketSelection(at location: CGPoint) {
            dragState = .blanketSelection(startLocation: location, currentLocation: location)
            selectedNodeName.wrappedValue = nil
            selectedConnection.wrappedValue = nil
            armedDraft.wrappedValue = nil
            pendingPrompt.wrappedValue = nil
            hoveredPin.wrappedValue = nil
            needsDisplay = true
        }

        private func finalizeBlanketSelection(start: CGPoint, current: CGPoint) {
            let selection = CanvasBeachBlanketGeometry.selectionRect(start: start, current: current)
            guard selection.width >= 8, selection.height >= 8 else { return }
            let memberNames = CanvasBeachBlanketGeometry.memberNames(
                in: selection,
                placements: placements,
                zoom: zoom,
                pan: pan,
                canvasSize: canvasSize
            )
            guard !memberNames.isEmpty else { return }
            onCreateBlanket?(memberNames)
        }

        private func handlePinSelection(_ pin: CanvasPinReference, at location: CGPoint) {
            switch pin.role {
            case .output:
                if armedDraft.wrappedValue?.source == pin {
                    cancelDraft()
                    return
                }
                armedDraft.wrappedValue = CanvasConnectionDraft(source: pin)
                hoveredPin.wrappedValue = pin
                selectedConnection.wrappedValue = nil
                selectedNodeName.wrappedValue = nil
                pendingPrompt.wrappedValue = nil
                needsDisplay = true
            case .input:
                guard let source = armedDraft.wrappedValue?.source else { return }
                completeConnection(from: source, to: pin, at: location)
            }
        }

        private func completeConnection(from source: CanvasPinReference, to destination: CanvasPinReference, at location: CGPoint) {
            guard let sourcePresentation = presentation(named: source.nodeName),
                  let destinationPresentation = presentation(named: destination.nodeName) else {
                return
            }

            let suggestion = CanvasConnectionSuggestionEngine.suggestedType(from: sourcePresentation, to: destinationPresentation)
            if let suggestion {
                let connection = Connection(
                    from: source.nodeName,
                    to: destination.nodeName,
                    type: suggestion.rawValue
                )
                commit(connection)
                return
            }

            pendingPrompt.wrappedValue = CanvasConnectionTypePrompt(
                from: source.nodeName,
                to: destination.nodeName,
                location: location,
                sourcePattern: sourcePresentation.pattern,
                destinationPattern: destinationPresentation.pattern
            )
            hoveredPin.wrappedValue = destination
            needsDisplay = true
        }

        private func commit(_ connection: Connection) {
            onCommitConnection?(connection)
            selectedConnection.wrappedValue = connection
            selectedNodeName.wrappedValue = nil
            armedDraft.wrappedValue = nil
            pendingPrompt.wrappedValue = nil
            hoveredPin.wrappedValue = nil
            needsDisplay = true
        }

        private func cancelDraftAndSelection() {
            cancelDraft()
            selectedNodeName.wrappedValue = nil
            selectedConnection.wrappedValue = nil
            dragState = nil
            needsDisplay = true
        }

        private func cancelDraft() {
            armedDraft.wrappedValue = nil
            pendingPrompt.wrappedValue = nil
            hoveredPin.wrappedValue = nil
            needsDisplay = true
        }

        private func deleteSelectedConnection() {
            guard let connection = selectedConnection.wrappedValue else { return }
            onDeleteConnection?(connection)
            selectedConnection.wrappedValue = nil
            selectedNodeName.wrappedValue = nil
            armedDraft.wrappedValue = nil
            pendingPrompt.wrappedValue = nil
            hoveredPin.wrappedValue = nil
            needsDisplay = true
        }

        private func addReroute(for connection: Connection, at location: CGPoint) {
            let world = worldPoint(fromViewPoint: location)
            let reroutes = layout.reroutes.filter { $0.connectionFrom == connection.from && $0.connectionTo == connection.to }
            let waypoint = CanvasRerouteWaypoint(
                id: UUID(),
                connectionFrom: connection.from,
                connectionTo: connection.to,
                index: reroutes.count,
                x: world.x,
                y: world.y
            )
            onAddReroute?(waypoint)
            needsDisplay = true
        }

        private func updateHover(at location: CGPoint) {
            guard let source = armedDraft.wrappedValue?.source else {
                hoveredPin.wrappedValue = nil
                needsDisplay = true
                return
            }

            let pins = allPins()
            let nearestInput = pins
                .filter { $0.reference.role == .input }
                .min(by: { distance($0.center, location) < distance($1.center, location) })

            if let nearestInput, distance(nearestInput.center, location) <= CanvasPinGeometry.snapRadius {
                hoveredPin.wrappedValue = nearestInput.reference
            } else {
                hoveredPin.wrappedValue = source
            }
            needsDisplay = true
        }

        private func hitPin(at location: CGPoint) -> CanvasPinReference? {
            allPins().first(where: { distance($0.center, location) <= $0.radius })?.reference
        }

        private func hitNode(at location: CGPoint) -> String? {
            placements.reversed().first(where: { placement in
                guard let presentation = modelPresentation(named: placement.presentation.name) else { return false }
                let frame = CanvasPinGeometry.frame(
                    for: placement,
                    zoom: zoom,
                    pan: pan,
                    canvasSize: canvasSize
                )
                return frame.contains(location) && !CanvasPinGeometry.hits(
                    for: placement,
                    presentation: presentation,
                    zoom: zoom,
                    pan: pan,
                    canvasSize: canvasSize
                ).contains(where: { distance($0.center, location) <= $0.radius })
            })?.presentation.name
        }

        private func hitConnection(at location: CGPoint) -> Connection? {
            CanvasConnectionRouting.hitTest(
                point: location,
                model: model,
                layout: layout,
                placements: placements,
                zoom: zoom,
                pan: pan,
                canvasSize: canvasSize
            )
        }

        private func allPins() -> [CanvasPinHit] {
            placements.flatMap { placement in
                guard let presentation = modelPresentation(named: placement.presentation.name) else { return [] as [CanvasPinHit] }
                return CanvasPinGeometry.hits(
                    for: placement,
                    presentation: presentation,
                    zoom: zoom,
                    pan: pan,
                    canvasSize: canvasSize
                )
            }
        }

        private func drawConnections(in dirtyRect: NSRect) {
            let presentations = Dictionary(uniqueKeysWithValues: CanvasNodePresentationFactory.presentations(for: model).map { ($0.name, $0) })
            for connection in model.connections {
                guard
                    let sourcePresentation = presentations[connection.from],
                    let destinationPresentation = presentations[connection.to],
                    let sourcePlacement = placements.first(where: { $0.presentation.name == connection.from }),
                    let destinationPlacement = placements.first(where: { $0.presentation.name == connection.to }),
                    let start = CanvasConnectionRouting.endpoint(
                        for: connection.from,
                        pinRole: .output,
                        placement: sourcePlacement,
                        presentation: sourcePresentation,
                        zoom: zoom,
                        pan: pan,
                        canvasSize: canvasSize,
                        fallbackSide: .output
                    ),
                    let end = CanvasConnectionRouting.endpoint(
                        for: connection.to,
                        pinRole: .input,
                        placement: destinationPlacement,
                        presentation: destinationPresentation,
                        zoom: zoom,
                        pan: pan,
                        canvasSize: canvasSize,
                        fallbackSide: .input
                    )
                else { continue }

                let reroutes = CanvasConnectionRouting.reroutePoints(
                    for: connection,
                    layout: layout,
                    zoom: zoom,
                    pan: pan,
                    canvasSize: canvasSize
                )
                let path = CanvasConnectionRouting.path(from: start, to: end, reroutes: reroutes)
                let accent = CanvasNodePresentationFactory.accentNSColor(for: sourcePresentation)
                accent.setStroke()
                path.lineWidth = selectedConnection.wrappedValue == connection ? 4 : 2.5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }

            if let draft = armedDraft.wrappedValue,
               let sourcePresentation = presentation(named: draft.source.nodeName),
               let sourcePlacement = placements.first(where: { $0.presentation.name == draft.source.nodeName }),
               let start = CanvasConnectionRouting.endpoint(
                   for: draft.source.nodeName,
                   pinRole: .output,
                   placement: sourcePlacement,
                   presentation: sourcePresentation,
                   zoom: zoom,
                   pan: pan,
                   canvasSize: canvasSize,
                   fallbackSide: .output
               ) {
                let end = hoveredPin.wrappedValue.flatMap { hovered in
                    pinCenter(for: hovered)
                } ?? currentMouseLocation()
                let draftPath = CanvasConnectionRouting.path(from: start, to: end)
                CanvasNodePresentationFactory.accentNSColor(for: sourcePresentation).withAlphaComponent(0.9).setStroke()
                draftPath.lineWidth = 2
                let dash: [CGFloat] = [6, 5]
                dash.withUnsafeBufferPointer { buffer in
                    draftPath.setLineDash(buffer.baseAddress, count: buffer.count, phase: 0)
                }
                draftPath.stroke()
            }
        }

        private func pinCenter(for reference: CanvasPinReference) -> CGPoint? {
            guard let placement = placements.first(where: { $0.presentation.name == reference.nodeName }),
                  let presentation = presentation(named: reference.nodeName) else { return nil }
            return CanvasPinGeometry.pinCenter(
                for: reference,
                placement: placement,
                presentation: presentation,
                zoom: zoom,
                pan: pan,
                canvasSize: canvasSize
            )
        }

        private func presentation(named name: String) -> CanvasNodePresentation? {
            modelPresentation(named: name)
        }

        private func modelPresentation(named name: String) -> CanvasNodePresentation? {
            CanvasNodePresentationFactory.presentation(named: name, in: model)
        }

        private func nodePosition(for name: String) -> CGPoint? {
            nodePositions.wrappedValue[name]
                ?? placements.first(where: { $0.presentation.name == name })?.worldPosition
        }

        private func worldPoint(fromViewPoint point: CGPoint) -> CGPoint {
            CGPoint(
                x: (point.x - canvasSize.width / 2 - pan.width) / zoom,
                y: (point.y - canvasSize.height / 2 - pan.height) / zoom
            )
        }

        private func currentMouseLocation() -> CGPoint {
            guard let window else { return .zero }
            return convert(window.mouseLocationOutsideOfEventStream, from: nil)
        }

        private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
            hypot(lhs.x - rhs.x, lhs.y - rhs.y)
        }
    }
}

struct CanvasConnectionTypeChooser: View {
    let prompt: CanvasConnectionTypePrompt
    let onSelect: (CanvasConnectionType) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Connection Type")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(prompt.from) → \(prompt.to)")
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(CanvasConnectionType.allCases) { type in
                Button {
                    onSelect(type)
                } label: {
                    Text(type.rawValue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            Button("Cancel", role: .cancel) {
                onCancel()
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 8)
    }
}

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        let elementCount = self.elementCount
        if elementCount == 0 { return path }

        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<elementCount {
            switch self.element(at: index, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addCurve(to: points[1], control1: points[0], control2: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        return path
    }
}
