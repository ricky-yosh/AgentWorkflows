import SwiftUI

/// Pre-Play seed prompt. Collects the one- or two-sentence intent that
/// Ralph's opening `/grill-with-docs` needs as its target. The sheet is shown by
/// `SessionDetailView` on the first Play of a session lifetime; cancel
/// aborts Play, confirm hands the text back through `onConfirm`.
struct SessionSeedSheet: View {
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @FocusState private var editorFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What do you want to build or change?")
                .font(.title2)
                .fontWeight(.semibold)
            Text("One or two sentences is enough — you'll refine it during grill-with-docs.")
                .font(.body)
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 180)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .focused($editorFocused)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Start") {
                    onConfirm(trimmed)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(trimmed.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { editorFocused = true }
    }
}
