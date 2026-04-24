import SwiftUI

struct FirstRunSkillsModal: View {
    var skillsDirectory: URL
    var onInstall: () -> Void
    var onSkip: () -> Void
    var onDontShowAgain: () -> Void

    private var abbreviatedPath: String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return skillsDirectory.path.replacingOccurrences(of: homePath, with: "~")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Install Required Skills")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Text("AgentWorkflows needs six skill files in **\(abbreviatedPath)/** to run the Ralph Loop. They are bundled with this app and can be installed with one click.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(PresenceChecker.requiredSkills, id: \.self) { name in
                    Label(name, systemImage: "doc.text")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 4)

            Divider()

            HStack(spacing: 12) {
                Button("Don't Show Again", action: onDontShowAgain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Skip", action: onSkip)
                Button("Install", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    /// Returns true when the modal should be presented.
    static func shouldPresent(hasMissingSkills: Bool, dontShowAgain: Bool) -> Bool {
        hasMissingSkills && !dontShowAgain
    }
}
