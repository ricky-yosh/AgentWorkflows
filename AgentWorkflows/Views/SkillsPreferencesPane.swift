import SwiftUI

struct SkillsPreferencesPane: View {
    @Environment(SettingsStore.self) private var settingsStore
    @State private var sections: [DirectorySection] = []
    @State private var currentConsent: PendingConsent?
    @State private var remainingConsents: [PendingConsent] = []
    @State private var approvedConsentOps: [SkillInstaller.Op] = []
    @State private var pendingNonConsentOps: [SkillInstaller.Op] = []
    @State private var activeConsentDirectory: URL?
    @State private var installResults: [SkillInstallExecutor.OpResult] = []
    @State private var installBlocked: [SkillInstaller.BlockedOp] = []
    @State private var showInstallResults = false
    @State private var retryPlan: RetryPlan?

    struct DirectorySection: Identifiable {
        let directory: URL
        var rows: [SkillRow]
        var id: String { directory.path }
    }

    struct SkillRow: Equatable {
        let name: String
        let classification: SkillClassifier.State
        let sourceURL: URL
    }

    struct PendingConsent: Identifiable {
        let id = UUID()
        let op: SkillInstaller.Op
        let skillName: String
        let bundledContent: String
        let onDiskContent: String
    }

    struct RetryPlan {
        let plan: SkillInstaller.Plan
        let directory: URL
    }

    var body: some View {
        Form {
            if sections.count == 1, let section = sections.first {
                singleDirectoryContent(section)
            } else {
                multiDirectoryContent
            }
        }
        .formStyle(.grouped)
        .onAppear { loadClassifications() }
        .onChange(of: settingsStore.settings.allSkillsDirectories) { _, _ in
            loadClassifications()
        }
        .sheet(item: $currentConsent) { consent in
            SkillUpdateConfirmationSheet(
                skillName: consent.skillName,
                bundledContent: consent.bundledContent,
                onDiskContent: consent.onDiskContent,
                onConfirm: {
                    approvedConsentOps.append(consent.op)
                    advanceConsent()
                },
                onCancel: {
                    advanceConsent()
                }
            )
        }
        .sheet(isPresented: $showInstallResults) {
            SkillInstallResultSheet(
                results: installResults,
                blocked: installBlocked,
                onDismiss: { showInstallResults = false },
                onRetry: SkillInstallResultSheet.hasFailures(in: installResults) ? {
                    showInstallResults = false
                    if let retry = retryPlan {
                        DispatchQueue.main.async { executeAndRefresh(plan: retry.plan, directory: retry.directory) }
                    }
                } : nil
            )
        }
    }

    // MARK: - Layout variants

    @ViewBuilder
    private func singleDirectoryContent(_ section: DirectorySection) -> some View {
        Section {
            Button("Update All Clean") { performBulkAction(.updateAllClean, directory: section.directory) }
                .disabled(!hasSomeUpdatable(in: section))
            Button("Update All") { performBulkAction(.updateAll, directory: section.directory) }
                .disabled(!hasSomeUpdatable(in: section))
            Button("Remove All Unmodified") { performBulkAction(.removeAllUnmodified, directory: section.directory) }
                .disabled(!hasSomeRemovable(in: section))
        } header: {
            directoryHeader(section.directory)
        }
        Section("Skills") {
            ForEach(section.rows, id: \.name) { row in
                skillRow(row, directory: section.directory)
            }
        }
    }

    @ViewBuilder
    private var multiDirectoryContent: some View {
        ForEach(sections) { section in
            Section {
                Button("Update All Clean") { performBulkAction(.updateAllClean, directory: section.directory) }
                    .disabled(!hasSomeUpdatable(in: section))
                Button("Update All") { performBulkAction(.updateAll, directory: section.directory) }
                    .disabled(!hasSomeUpdatable(in: section))
                Button("Remove All Unmodified") { performBulkAction(.removeAllUnmodified, directory: section.directory) }
                    .disabled(!hasSomeRemovable(in: section))
                ForEach(section.rows, id: \.name) { row in
                    skillRow(row, directory: section.directory)
                }
            } header: {
                directoryHeader(section.directory)
            }
        }
    }

    @ViewBuilder
    private func directoryHeader(_ directory: URL) -> some View {
        HStack {
            Text(abbreviatedPath(directory))
            Spacer()
            Button {
                NSWorkspace.shared.open(directory)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Per-skill row

    @ViewBuilder
    private func skillRow(_ row: SkillRow, directory: URL) -> some View {
        HStack {
            Text(row.name)
                .font(.body)
            Spacer()
            classificationChip(row.classification)
            Button("Update") { performUpdate(skillName: row.name, directory: directory) }
                .disabled(Self.isUpdateDisabled(for: row.classification))
            Button("Remove") { performRemove(skillName: row.name, directory: directory) }
                .disabled(Self.isRemoveDisabled(for: row.classification))
                .help(Self.removeDisabledReason(for: row.classification) ?? "")
        }
    }

    @ViewBuilder
    private func classificationChip(_ state: SkillClassifier.State) -> some View {
        Text(state.displayLabel)
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(state.chipColor, in: Capsule())
    }

    // MARK: - Static helpers (testable)

    static func isUpdateDisabled(for state: SkillClassifier.State) -> Bool {
        state == .missing
    }

    static func isRemoveDisabled(for state: SkillClassifier.State) -> Bool {
        state == .missing || state == .modified
    }

    static func removeDisabledReason(for state: SkillClassifier.State) -> String? {
        guard state == .modified else { return nil }
        return "Skill has been locally modified and cannot be removed without explicit confirmation."
    }

    static func opsRequiringConsent(in plan: SkillInstaller.Plan) -> [SkillInstaller.Op] {
        plan.ops.filter {
            guard case .update(_, _, let requiresConsent) = $0 else { return false }
            return requiresConsent
        }
    }

    // MARK: - Per-section state helpers

    private func hasSomeUpdatable(in section: DirectorySection) -> Bool {
        section.rows.contains { $0.classification == .clean || $0.classification == .stale }
    }

    private func hasSomeRemovable(in section: DirectorySection) -> Bool {
        section.rows.contains { $0.classification == .clean || $0.classification == .stale }
    }

    private func abbreviatedPath(_ url: URL) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: homePath, with: "~")
    }

    // MARK: - Actions

    private func performUpdate(skillName: String, directory: URL) {
        guard let inputs = buildInputs(for: directory) else { return }
        let plan = SkillInstaller.plan(skills: inputs, intent: .updateSpecific(name: skillName))
        startConsentFlow(for: plan, directory: directory)
    }

    private func performRemove(skillName: String, directory: URL) {
        guard let inputs = buildInputs(for: directory) else { return }
        let plan = SkillInstaller.plan(skills: inputs, intent: .removeSpecific(name: skillName))
        executeAndRefresh(plan: plan, directory: directory)
    }

    private func performBulkAction(_ intent: SkillInstaller.UserIntent, directory: URL) {
        guard let inputs = buildInputs(for: directory) else { return }
        let plan = SkillInstaller.plan(skills: inputs, intent: intent)
        startConsentFlow(for: plan, directory: directory)
    }

    private func startConsentFlow(for plan: SkillInstaller.Plan, directory: URL) {
        let consentOps = Self.opsRequiringConsent(in: plan)
        let nonConsent = plan.ops.filter {
            guard case .update(_, _, let requiresConsent) = $0 else { return true }
            return !requiresConsent
        }

        guard !consentOps.isEmpty else {
            executeAndRefresh(plan: plan, directory: directory)
            return
        }

        activeConsentDirectory = directory
        pendingNonConsentOps = nonConsent
        approvedConsentOps = []

        var consents: [PendingConsent] = []
        for op in consentOps {
            guard case .update(let name, let sourceURL, _) = op else { continue }
            let bundledContent = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
            let onDiskFile = directory.appendingPathComponent(name).appendingPathComponent("SKILL.md")
            let onDiskContent = (try? String(contentsOf: onDiskFile, encoding: .utf8)) ?? ""
            consents.append(PendingConsent(
                op: op,
                skillName: name,
                bundledContent: bundledContent,
                onDiskContent: onDiskContent
            ))
        }

        guard !consents.isEmpty else {
            executeAndRefresh(plan: plan, directory: directory)
            return
        }

        remainingConsents = Array(consents.dropFirst())
        currentConsent = consents.first
    }

    private func advanceConsent() {
        if remainingConsents.isEmpty {
            let resolvedPlan = SkillInstaller.Plan(ops: pendingNonConsentOps + approvedConsentOps, blocked: [])
            let dir = activeConsentDirectory
            currentConsent = nil
            pendingNonConsentOps = []
            approvedConsentOps = []
            activeConsentDirectory = nil
            if let dir {
                DispatchQueue.main.async {
                    executeAndRefresh(plan: resolvedPlan, directory: dir)
                }
            }
        } else {
            currentConsent = remainingConsents.removeFirst()
        }
    }

    private func buildInputs(for directory: URL) -> [SkillInstaller.SkillInput]? {
        sections.first(where: { $0.directory == directory })?.rows
            .map { SkillInstaller.SkillInput(name: $0.name, classification: $0.classification, sourceURL: $0.sourceURL) }
    }

    private func executeAndRefresh(plan: SkillInstaller.Plan, directory: URL) {
        let results = SkillInstallExecutor.execute(plan: plan, skillsDirectory: directory)
        loadClassifications()
        if SkillInstallResultSheet.shouldPresent(results: results, blocked: plan.blocked) {
            retryPlan = RetryPlan(plan: plan, directory: directory)
            installResults = results
            installBlocked = plan.blocked
            showInstallResults = true
        }
    }

    // MARK: - Classification loading

    private func loadClassifications() {
        guard let bundle = try? SkillBundleReader.read() else { return }
        let manifestByName = Dictionary(uniqueKeysWithValues: bundle.manifest.map { ($0.name, $0) })
        let bundledByName = Dictionary(uniqueKeysWithValues: bundle.skills.map { ($0.name, $0) })

        sections = settingsStore.settings.allSkillsDirectories.map { dir in
            let rows = PresenceChecker.requiredSkills.compactMap { name -> SkillRow? in
                guard let entry = manifestByName[name], let bundled = bundledByName[name] else { return nil }
                let skillFile = dir.appendingPathComponent(name).appendingPathComponent("SKILL.md")
                let bytesOnDisk = try? Data(contentsOf: skillFile)
                let state = SkillClassifier.classify(
                    bytesOnDisk: bytesOnDisk,
                    currentHash: entry.sha256,
                    priorHashes: entry.priorSha256s
                )
                return SkillRow(name: name, classification: state, sourceURL: bundled.fileURL)
            }
            return DirectorySection(directory: dir, rows: rows)
        }
    }
}

// MARK: - SkillClassifier.State display helpers

private extension SkillClassifier.State {
    var displayLabel: String {
        switch self {
        case .missing: return "Missing"
        case .clean: return "Clean"
        case .modified: return "Modified"
        case .stale: return "Stale"
        }
    }

    var chipColor: Color {
        switch self {
        case .missing: return .gray
        case .clean: return .green
        case .modified: return .orange
        case .stale: return .blue
        }
    }
}
