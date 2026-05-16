import SwiftUI

// MARK: - Block Model

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String?, code: String)
    case list(items: [String])
    case blockquote(text: String)
    case divider
}

// MARK: - Parser

private func parseMarkdown(_ markdown: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    let lines = markdown.components(separatedBy: "\n")
    var i = 0
    var paragraphLines: [String] = []

    func flushParagraph() {
        let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { blocks.append(.paragraph(text: text)) }
        paragraphLines = []
    }

    while i < lines.count {
        let line = lines[i]

        // Fenced code block
        if line.hasPrefix("```") {
            flushParagraph()
            let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var code: [String] = []
            i += 1
            while i < lines.count && !lines[i].hasPrefix("```") {
                code.append(lines[i])
                i += 1
            }
            blocks.append(.codeBlock(language: lang.isEmpty ? nil : lang, code: code.joined(separator: "\n")))
            i += 1
            continue
        }

        // Heading
        if line.hasPrefix("#") {
            flushParagraph()
            let level = line.prefix(while: { $0 == "#" }).count
            let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
            blocks.append(.heading(level: min(level, 3), text: text))
            i += 1
            continue
        }

        // Blockquote
        if line.hasPrefix("> ") {
            flushParagraph()
            blocks.append(.blockquote(text: String(line.dropFirst(2))))
            i += 1
            continue
        }

        // List (consume consecutive items)
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            flushParagraph()
            var items: [String] = [String(line.dropFirst(2))]
            i += 1
            while i < lines.count,
                  lines[i].hasPrefix("- ") || lines[i].hasPrefix("* ") || lines[i].hasPrefix("+ ") {
                items.append(String(lines[i].dropFirst(2)))
                i += 1
            }
            blocks.append(.list(items: items))
            continue
        }

        // Divider
        if line == "---" || line == "***" || line == "___" {
            flushParagraph()
            blocks.append(.divider)
            i += 1
            continue
        }

        // Empty line = paragraph break
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            flushParagraph()
            i += 1
            continue
        }

        paragraphLines.append(line)
        i += 1
    }

    flushParagraph()
    return blocks
}

// MARK: - Inline text helper

private func inlineText(_ markdown: String) -> Text {
    var attributed = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    for run in attributed.runs {
        if let intent = run.inlinePresentationIntent, intent.contains(.code) {
            attributed[run.range].foregroundColor = Color.accentColor
        }
    }
    return Text(attributed)
}

// MARK: - View

struct MarkdownView: View {
    let content: String
    private let blocks: [MarkdownBlock]

    init(content: String) {
        self.content = content
        self.blocks = parseMarkdown(content)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level))
                .fontWeight(level == 1 ? .bold : level == 2 ? .semibold : .medium)
                .padding(.top, 8)

        case .paragraph(let text):
            inlineText(text)
                .font(.system(size: 15))
                .lineSpacing(5)

        case .codeBlock(_, let code):
            LineChunkedTextView(code)
                .font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.2), lineWidth: 1))

        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        inlineText(item).font(.system(size: 15)).lineSpacing(5)
                    }
                }
            }

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 3)
                inlineText(text)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .foregroundStyle(.secondary)
            }

        case .divider:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        default: return .title3
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MarkdownView(content: """
        # Heading 1
        ## Heading 2
        ### Heading 3

        This is a paragraph with **bold**, *italic*, and `inline code` text.

        - First item
        - Second item
        - Third item

        > This is a blockquote with some text inside it.

        ```swift
        let x = 42
        print("hello, world")
        ```

        ---

        Another paragraph after a divider.
        """)
        .padding()
    }
    .frame(width: 500)
}
