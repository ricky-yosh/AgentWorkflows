import SwiftUI

struct NewSessionView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: SidebarItem?

    let defaultWorkingDirectory: String?

    @State private var workingDirectory = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                PathControlView(path: $workingDirectory)
            }
            .formStyle(.grouped)
            .padding(.bottom, 8)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    createSession()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(workingDirectory.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 420)
        .onAppear {
            if let dir = defaultWorkingDirectory {
                workingDirectory = dir
            }
        }
    }

    private func createSession() {
        guard !workingDirectory.isEmpty else { return }

        if let session = try? sessionStore.createSession(
            workingDirectory: workingDirectory,
            workflowName: Workflow.ralph.name
        ) {
            selection = .session(session.id)
        }

        dismiss()
    }
}
