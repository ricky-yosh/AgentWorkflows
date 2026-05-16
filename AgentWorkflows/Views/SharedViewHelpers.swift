import SwiftUI

/// Renders an SF Symbol with hierarchical symbol rendering mode and a
/// caller-supplied colour. Used by inspector rows, phase section labels,
/// and the inspector status strip to keep the icon style consistent.
struct StatusSymbolImage: View {
    let symbolName: String
    let color: Color

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
    }
}

/// Splits large text surfaces into independently measured lines so SwiftUI
/// does not repeatedly typeset one huge `Text` view on the main thread.
struct LineChunkedTextView: View {
    private struct Line: Identifiable {
        let id: Int
        let text: String
    }

    private let lines: [Line]
    private let fixedHorizontalSize: Bool

    init(
        _ content: String,
        fixedHorizontalSize: Bool = false,
        maxLineLength: Int = 2_000
    ) {
        var nextID = 0
        var lines: [Line] = []
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.count <= maxLineLength {
                lines.append(Line(id: nextID, text: line.isEmpty ? " " : line))
                nextID += 1
                continue
            }

            var start = line.startIndex
            while start < line.endIndex {
                let end = line.index(start, offsetBy: maxLineLength, limitedBy: line.endIndex) ?? line.endIndex
                lines.append(Line(id: nextID, text: String(line[start..<end])))
                nextID += 1
                start = end
            }
        }

        self.lines = lines.isEmpty ? [Line(id: 0, text: " ")] : lines
        self.fixedHorizontalSize = fixedHorizontalSize
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                Text(line.text)
                    .fixedSize(horizontal: fixedHorizontalSize, vertical: false)
                    .frame(maxWidth: fixedHorizontalSize ? nil : .infinity, alignment: .leading)
            }
        }
    }
}
