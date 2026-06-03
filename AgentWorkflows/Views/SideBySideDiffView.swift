import SwiftUI
import AppKit

private let diffConnectorWidth: CGFloat = 20

struct SideBySideDiffView: View {
    let fileDiffs: [FileDiff]
    var scrollToFile: String? = nil

    @State private var currentHunkIndex: Int = 0

    private var allHunkIDs: [String] {
        fileDiffs.flatMap { file in
            file.hunks.indices.map { "\(file.filePath)::hunk-\($0)" }
        }
    }

    var body: some View {
        GeometryReader { outerGeo in
            if outerGeo.size.width >= 700 {
                let paneWidth = max(200, floor((outerGeo.size.width - diffConnectorWidth) / 2))

                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(fileDiffs, id: \.filePath) { file in
                                SideBySideFileView(file: file, paneWidth: paneWidth)
                                    .id(file.filePath)
                            }
                        }
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .onKeyPress(KeyEquivalent("]")) {
                        navigateHunk(by: 1, proxy: proxy)
                        return .handled
                    }
                    .onKeyPress(KeyEquivalent("[")) {
                        navigateHunk(by: -1, proxy: proxy)
                        return .handled
                    }
                    .onChange(of: scrollToFile) { _, newValue in
                        if let file = newValue {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(file, anchor: .top)
                            }
                        }
                    }
                    .onChange(of: fileDiffs) { _, _ in
                        currentHunkIndex = 0
                    }
                }
            } else {
                UnifiedDiffView(
                    fileDiffs: fileDiffs,
                    scrollToFile: scrollToFile
                )
            }
        }
    }

    private func navigateHunk(by delta: Int, proxy: ScrollViewProxy) {
        let ids = allHunkIDs
        guard !ids.isEmpty else { return }
        let newIdx = max(0, min(ids.count - 1, currentHunkIndex + delta))
        currentHunkIndex = newIdx
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(ids[newIdx], anchor: .top)
        }
    }
}

// MARK: - File view

private struct SideBySideFileView: View {
    let file: FileDiff
    let paneWidth: CGFloat

    private var additions: Int {
        file.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count }
    }

    private var removals: Int {
        file.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(file.filePath)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                Spacer()
                HStack(spacing: 8) {
                    if additions > 0 {
                        Text("+\(additions)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .systemGreen))
                    }
                    if removals > 0 {
                        Text("-\(removals)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .systemRed))
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .underPageBackgroundColor))

            ForEach(Array(file.hunks.enumerated()), id: \.offset) { idx, hunk in
                SideBySideHunkView(hunk: hunk, paneWidth: paneWidth)
                    .id("\(file.filePath)::hunk-\(idx)")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Hunk view

private struct SideBySideHunkView: View {
    let hunk: DiffHunk
    let paneWidth: CGFloat

    private static let rowHeight: CGFloat = 20

    @State private var hoveredGroupIndex: Int? = nil

    private var pairs: [LinePair] { Self.pairLines(hunk.lines) }

    private var groups: [[Int]] { changeGroups(from: pairs) }

    private var pairToGroupIndex: [Int: Int] {
        var map: [Int: Int] = [:]
        for (gi, group) in groups.enumerated() {
            for pi in group { map[pi] = gi }
        }
        return map
    }

    var body: some View {
        let allPairs = pairs
        let allGroups = changeGroups(from: allPairs)
        let groupMap = {
            var map: [Int: Int] = [:]
            for (gi, group) in allGroups.enumerated() {
                for pi in group { map[pi] = gi }
            }
            return map
        }()

        VStack(alignment: .leading, spacing: 0) {
            if !hunk.contextLine.isEmpty {
                Text(hunk.contextLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .systemBlue))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: paneWidth * 2 + diffConnectorWidth, alignment: .leading)
                    .background(Color.blue.opacity(0.08))
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(allPairs.enumerated()), id: \.offset) { i, pair in
                    let groupIdx = groupMap[i]
                    SideBySideLinePair(
                        pair: pair,
                        paneWidth: paneWidth,
                        pairIndex: i,
                        isGroupHighlighted: hoveredGroupIndex != nil && groupIdx == hoveredGroupIndex,
                        connectorHelpText: groupIdx.map { idx in
                            groupSummary(groupIndex: idx, pairs: allPairs, groups: allGroups)
                        } ?? "",
                        onConnectorHoverChanged: { pairIdx, entering in
                            hoveredGroupIndex = entering ? groupMap[pairIdx] : nil
                        }
                    )
                }
            }
            .overlay(
                mappingLinesCanvas(pairs: allPairs, groups: allGroups, hoveredGroupIndex: hoveredGroupIndex)
                    .allowsHitTesting(false)
            )
        }
    }

    // MARK: Group summary

    private func groupSummary(groupIndex: Int, pairs: [LinePair], groups: [[Int]]) -> String {
        let group = groups[groupIndex]
        let removed = group.filter { pairs[$0].leftKind == .removed }.count
        let added = group.filter { pairs[$0].rightKind == .added }.count
        if removed > 0 && added > 0 { return "\(removed) removed → \(added) added" }
        if removed > 0 { return "\(removed) removed" }
        return "\(added) added"
    }

    // MARK: Mapping lines canvas

    private func mappingLinesCanvas(pairs: [LinePair], groups: [[Int]], hoveredGroupIndex: Int?) -> some View {
        Canvas { context, _ in
            let rowHeight = Self.rowHeight
            let leftX = paneWidth
            let rightX = paneWidth + diffConnectorWidth
            let centerX = paneWidth + diffConnectorWidth / 2

            var sep = Path()
            sep.move(to: CGPoint(x: centerX, y: 0))
            sep.addLine(to: CGPoint(x: centerX, y: CGFloat(pairs.count) * rowHeight))
            context.stroke(sep, with: .color(Color(nsColor: .separatorColor)), lineWidth: 1)

            for (groupIdx, group) in groups.enumerated() {
                let leftRows = group.filter { pairs[$0].leftKind == .removed }
                let rightRows = group.filter { pairs[$0].rightKind == .added }

                let hasLeft = !leftRows.isEmpty
                let hasRight = !rightRows.isEmpty
                let isHovered = hoveredGroupIndex == groupIdx

                let leftTopY: CGFloat = hasLeft ? CGFloat(leftRows[0]) * rowHeight : CGFloat(group[0]) * rowHeight
                let leftBottomY: CGFloat = hasLeft ? CGFloat(leftRows.last! + 1) * rowHeight : leftTopY
                let rightTopY: CGFloat = hasRight ? CGFloat(rightRows[0]) * rowHeight : CGFloat(group[0]) * rowHeight
                let rightBottomY: CGFloat = hasRight ? CGFloat(rightRows.last! + 1) * rowHeight : rightTopY

                let baseOpacity: CGFloat = isHovered ? 0.45 : (hasLeft && hasRight ? 0.22 : 0.20)
                let fillColor: Color
                if hasLeft && hasRight {
                    fillColor = Color(nsColor: .systemOrange).opacity(baseOpacity)
                } else if hasLeft {
                    fillColor = Color(nsColor: .systemRed).opacity(baseOpacity)
                } else {
                    fillColor = Color(nsColor: .systemGreen).opacity(baseOpacity)
                }

                var path = Path()
                path.move(to: CGPoint(x: leftX, y: leftTopY))
                path.addCurve(
                    to: CGPoint(x: rightX, y: rightTopY),
                    control1: CGPoint(x: centerX, y: leftTopY),
                    control2: CGPoint(x: centerX, y: rightTopY)
                )
                path.addLine(to: CGPoint(x: rightX, y: rightBottomY))
                path.addCurve(
                    to: CGPoint(x: leftX, y: leftBottomY),
                    control1: CGPoint(x: centerX, y: rightBottomY),
                    control2: CGPoint(x: centerX, y: leftBottomY)
                )
                path.closeSubpath()

                context.fill(path, with: .color(fillColor))
                context.stroke(
                    path,
                    with: .color(fillColor.opacity(isHovered ? 1.0 : 0.6)),
                    lineWidth: isHovered ? 1.0 : 0.5
                )
            }
        }
    }

    // Groups consecutive changed pairs; returns arrays of absolute pair indices.
    private func changeGroups(from pairs: [LinePair]) -> [[Int]] {
        var groups: [[Int]] = []
        var current: [Int] = []
        for (i, pair) in pairs.enumerated() {
            if pair.leftKind == .removed || pair.rightKind == .added {
                current.append(i)
            } else {
                if !current.isEmpty { groups.append(current); current = [] }
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    // MARK: Line pairing

    static func pairLines(_ lines: [DiffLine]) -> [LinePair] {
        var pairs: [LinePair] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            switch line.kind {
            case .context:
                pairs.append(LinePair(
                    leftNum: line.oldLineNumber,
                    rightNum: line.newLineNumber,
                    leftText: line.text,
                    rightText: line.text,
                    leftKind: .context,
                    rightKind: .context
                ))
                i += 1

            case .removed:
                var removed: [DiffLine] = []
                while i < lines.count, lines[i].kind == .removed {
                    removed.append(lines[i])
                    i += 1
                }
                var added: [DiffLine] = []
                while i < lines.count, lines[i].kind == .added {
                    added.append(lines[i])
                    i += 1
                }

                let pairCount = min(removed.count, added.count)
                for j in 0..<pairCount {
                    pairs.append(LinePair(
                        leftNum: removed[j].oldLineNumber,
                        rightNum: added[j].newLineNumber,
                        leftText: removed[j].text,
                        rightText: added[j].text,
                        leftKind: .removed,
                        rightKind: .added
                    ))
                }
                for j in pairCount..<removed.count {
                    pairs.append(LinePair(
                        leftNum: removed[j].oldLineNumber,
                        rightNum: nil,
                        leftText: removed[j].text,
                        rightText: "",
                        leftKind: .removed,
                        rightKind: .context,
                        isRightGhost: true
                    ))
                }
                for j in pairCount..<added.count {
                    pairs.append(LinePair(
                        leftNum: nil,
                        rightNum: added[j].newLineNumber,
                        leftText: "",
                        rightText: added[j].text,
                        leftKind: .context,
                        rightKind: .added,
                        isLeftGhost: true
                    ))
                }

            case .added:
                pairs.append(LinePair(
                    leftNum: nil,
                    rightNum: line.newLineNumber,
                    leftText: "",
                    rightText: line.text,
                    leftKind: .context,
                    rightKind: .added
                ))
                i += 1
            }
        }

        return pairs
    }
}

// MARK: - Line pair model

private struct LinePair {
    let leftNum: Int?
    let rightNum: Int?
    let leftText: String
    let rightText: String
    let leftKind: DiffLine.Kind
    let rightKind: DiffLine.Kind
    var isLeftGhost: Bool = false
    var isRightGhost: Bool = false
}

// MARK: - Side-by-side line pair view

private struct SideBySideLinePair: View {
    let pair: LinePair
    let paneWidth: CGFloat
    var pairIndex: Int = 0
    var isGroupHighlighted: Bool = false
    var connectorHelpText: String = ""
    var onConnectorHoverChanged: ((Int, Bool) -> Void)? = nil

    private static let numWidth: CGFloat = 44
    private static let rowHeight: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            // Left pane (old)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(pair.leftNum.map { "\($0)" } ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: Self.numWidth, alignment: .trailing)

                Text(pair.leftText.isEmpty ? " " : pair.leftText)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(textColor(for: pair.leftKind))
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .contextMenu {
                        if !pair.leftText.isEmpty && !pair.isLeftGhost {
                            Button("Copy Line") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(pair.leftText, forType: .string)
                            }
                            if let num = pair.leftNum {
                                Button("Copy with Line Number") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString("\(num): \(pair.leftText)", forType: .string)
                                }
                            }
                        }
                    }
            }
            .padding(.horizontal, 8)
            .frame(width: paneWidth, height: Self.rowHeight, alignment: .leading)
            .background { leftBackgroundView }
            .clipped()

            // Connector zone — hover here drives the canvas highlight
            Color.clear
                .frame(width: diffConnectorWidth)
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        onConnectorHoverChanged?(pairIndex, true)
                    case .ended:
                        onConnectorHoverChanged?(pairIndex, false)
                    }
                }
                .help(isGroupHighlighted ? connectorHelpText : "")

            // Right pane (new)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(pair.rightNum.map { "\($0)" } ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: Self.numWidth, alignment: .trailing)

                Text(pair.rightText.isEmpty ? " " : pair.rightText)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(textColor(for: pair.rightKind))
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .contextMenu {
                        if !pair.rightText.isEmpty && !pair.isRightGhost {
                            Button("Copy Line") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(pair.rightText, forType: .string)
                            }
                            if let num = pair.rightNum {
                                Button("Copy with Line Number") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString("\(num): \(pair.rightText)", forType: .string)
                                }
                            }
                        }
                    }
            }
            .padding(.horizontal, 8)
            .frame(width: paneWidth, height: Self.rowHeight, alignment: .leading)
            .background { rightBackgroundView }
            .clipped()
        }
    }

    @ViewBuilder
    private var leftBackgroundView: some View {
        if pair.isLeftGhost {
            ghostHatch
        } else {
            rowColor(for: pair.leftKind)
        }
    }

    @ViewBuilder
    private var rightBackgroundView: some View {
        if pair.isRightGhost {
            ghostHatch
        } else {
            rowColor(for: pair.rightKind)
        }
    }

    private var ghostHatch: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += 5
            }
            context.stroke(path, with: .color(Color.secondary.opacity(0.09)), lineWidth: 1)
        }
    }

    private func rowColor(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .context: return .clear
        case .added: return .green.opacity(0.12)
        case .removed: return .red.opacity(0.12)
        }
    }

    private func textColor(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .context: return .primary
        case .added: return Color(nsColor: .systemGreen).opacity(0.8)
        case .removed: return Color(nsColor: .systemRed).opacity(0.8)
        }
    }
}

// MARK: - Previews

private let previewDiff = FileDiff(
    filePath: "AgentWorkflows/Views/StatusBadgeView.swift",
    hunks: [
        DiffHunk(
            contextLine: "@@ -1,12 +1,10 @@",
            lines: [
                DiffLine(kind: .context, text: "import SwiftUI", oldLineNumber: 1, newLineNumber: 1),
                DiffLine(kind: .context, text: "", oldLineNumber: 2, newLineNumber: 2),
                DiffLine(kind: .removed, text: "struct StatusBadgeView: View {", oldLineNumber: 3, newLineNumber: nil),
                DiffLine(kind: .removed, text: "    // legacy comment", oldLineNumber: 4, newLineNumber: nil),
                DiffLine(kind: .removed, text: "    // another comment", oldLineNumber: 5, newLineNumber: nil),
                DiffLine(kind: .added, text: "struct StatusBadgeView: View {", oldLineNumber: nil, newLineNumber: 3),
                DiffLine(kind: .context, text: "", oldLineNumber: 6, newLineNumber: 4),
                DiffLine(kind: .removed, text: "    let sessionState: SessionState", oldLineNumber: 7, newLineNumber: nil),
                DiffLine(kind: .added, text: "    let sessionState: SessionState", oldLineNumber: nil, newLineNumber: 5),
                DiffLine(kind: .added, text: "    let title: String", oldLineNumber: nil, newLineNumber: 6),
                DiffLine(kind: .added, text: "    let subtitle: String", oldLineNumber: nil, newLineNumber: 7),
                DiffLine(kind: .context, text: "", oldLineNumber: 8, newLineNumber: 8),
                DiffLine(kind: .context, text: "    var body: some View {", oldLineNumber: 9, newLineNumber: 9),
            ]
        )
    ]
)

#Preview("Mapping Lines — direct") {
    SideBySideFileView(file: previewDiff, paneWidth: 420)
        .frame(width: 860)
        .padding()
}

#Preview("Mapping Lines — full view") {
    SideBySideDiffView(fileDiffs: [previewDiff])
        .frame(width: 960, height: 400)
}
