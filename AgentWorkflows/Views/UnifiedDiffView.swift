import SwiftUI
import AppKit

struct UnifiedDiffView: View {
    let fileDiffs: [FileDiff]
    var scrollToFile: String? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(fileDiffs, id: \.filePath) { file in
                        UnifiedDiffFileView(file: file)
                            .id(file.filePath)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .onChange(of: scrollToFile) { _, newValue in
                if let file = newValue {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(file, anchor: .top)
                    }
                }
            }
        }
    }
}

// MARK: - File view

struct UnifiedDiffFileView: View {
    let file: FileDiff

    private var additions: Int {
        file.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count }
    }

    private var removals: Int {
        file.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .underPageBackgroundColor))

            ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
                VStack(alignment: .leading, spacing: 0) {
                    if !hunk.contextLine.isEmpty {
                        Text(hunk.contextLine)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .systemBlue))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.blue.opacity(0.08))
                    }
                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                        DiffLineRow(line: line)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

// MARK: - Line row

struct DiffLineRow: View {
    let line: DiffLine

    private var rowColor: Color {
        switch line.kind {
        case .context: return .clear
        case .added: return .green.opacity(0.12)
        case .removed: return .red.opacity(0.12)
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .context: return .primary
        case .added: return .green
        case .removed: return .red
        }
    }

    private var marker: String {
        switch line.kind {
        case .context: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .context: return .clear
        case .added: return .green
        case .removed: return .red
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(line.oldLineNumber.map { "\($0)" } ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
                .allowsHitTesting(false)

            Text(line.newLineNumber.map { "\($0)" } ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
                .allowsHitTesting(false)

            Text(marker)
                .font(.system(size: 11, design: .monospaced).weight(.semibold))
                .foregroundStyle(markerColor)
                .frame(width: 16, alignment: .center)

            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .contextMenu {
                    Button("Copy Line") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(line.text, forType: .string)
                    }
                    let lineNum = line.newLineNumber ?? line.oldLineNumber
                    if let num = lineNum {
                        Button("Copy with Line Number") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("\(num): \(line.text)", forType: .string)
                        }
                    }
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(rowColor)
    }
}

// MARK: - Preview

#Preview("Unified Diff") {
    let sampleDiff = FileDiff(
        filePath: "AgentWorkflows/Views/StatusBadgeView.swift",
        hunks: [
            DiffHunk(
                contextLine: "@@ -1,10 +1,15 @@",
                lines: [
                    DiffLine(kind: .context, text: "import SwiftUI", oldLineNumber: 1, newLineNumber: 1),
                    DiffLine(kind: .context, text: "", oldLineNumber: 2, newLineNumber: 2),
                    DiffLine(kind: .removed, text: "struct StatusBadgeView: View {", oldLineNumber: 3, newLineNumber: nil),
                    DiffLine(kind: .added, text: "struct StatusBadgeView: View {", oldLineNumber: nil, newLineNumber: 3),
                    DiffLine(kind: .removed, text: "    let sessionState: SessionState", oldLineNumber: 4, newLineNumber: nil),
                    DiffLine(kind: .added, text: "    let sessionState: SessionState", oldLineNumber: nil, newLineNumber: 4),
                    DiffLine(kind: .context, text: "", oldLineNumber: 5, newLineNumber: 5),
                    DiffLine(kind: .context, text: "    var body: some View {", oldLineNumber: 6, newLineNumber: 6),
                    DiffLine(kind: .context, text: "        switch sessionState {", oldLineNumber: 7, newLineNumber: 7),
                ]
            )
        ]
    )

    UnifiedDiffView(fileDiffs: [sampleDiff])
}
