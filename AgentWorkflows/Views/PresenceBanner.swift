import SwiftUI

/// Non-blocking banner surfaced on launch when any required Skill is missing.
/// Renders one row per missing prerequisite with an install hint. Dismissible
/// for the session when `onDismiss` is provided; omit the callback for
/// read-only use inside Preferences.
struct PresenceBanner: View {
    let report: PresenceChecker.Report
    var onDismiss: (() -> Void)?
    var onInstall: (() -> Void)?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.id) { row in
                    PresenceBannerRow(row: row, onInstall: row.isInstallable ? onInstall : nil)
                }
                if let onDismiss {
                    HStack {
                        Spacer()
                        Button("Dismiss", action: onDismiss)
                            .controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Prerequisites missing", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    static func hasMissing(_ report: PresenceChecker.Report) -> Bool {
        !report.allSkillsPresent
    }

    private var rows: [PresenceRow] {
        PresenceBanner.missingRows(for: report)
    }

    static func missingRows(for report: PresenceChecker.Report) -> [PresenceRow] {
        var out: [PresenceRow] = []
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        for missing in report.missingSkillsByDirectory {
            let abbreviated = missing.directory.path.replacingOccurrences(of: homePath, with: "~")
            out.append(PresenceRow(
                id: "skill.\(missing.name).\(missing.directory.path)",
                title: "Skill not installed: \(missing.name)",
                hint: "Install SKILL.md at \(abbreviated)/\(missing.name)/SKILL.md.",
                link: nil,
                isInstallable: true
            ))
        }
        return out
    }

    /// Builds SkillInstaller inputs for skills absent in a specific directory, using bundled source URLs.
    /// Non-missing skills are excluded; the caller should pass `.firstRun` intent to the planner.
    static func installInputsForMissing(
        report: PresenceChecker.Report,
        directory: URL,
        bundledSkills: [SkillBundleReader.BundledSkill]
    ) -> [SkillInstaller.SkillInput] {
        let missing = Set(
            report.missingSkillsByDirectory
                .filter { $0.directory == directory }
                .map(\.name)
        )
        return bundledSkills
            .filter { missing.contains($0.name) }
            .map { SkillInstaller.SkillInput(name: $0.name, classification: .missing, sourceURL: $0.fileURL) }
    }
}

struct PresenceRow: Equatable {
    let id: String
    let title: String
    let hint: String
    let link: URL?
    var isInstallable: Bool

    init(id: String, title: String, hint: String, link: URL?, isInstallable: Bool = false) {
        self.id = id
        self.title = title
        self.hint = hint
        self.link = link
        self.isInstallable = isInstallable
    }
}

private struct PresenceBannerRow: View {
    let row: PresenceRow
    var onInstall: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(row.title)
                    .font(.body)
                if let onInstall {
                    Spacer()
                    Button("Install", action: onInstall)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                Text(row.hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let link = row.link {
                    Link("Docs", destination: link)
                        .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
