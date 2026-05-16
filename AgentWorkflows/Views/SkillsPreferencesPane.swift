import SwiftUI

struct SkillsPreferencesPane: View {
    @Environment(SettingsStore.self) private var settingsStore
    @State private var sections: [DirectorySection] = []
    @State private var currentConsent: PendingConsent?
    @State private var remainingConsents: [PendingConsent] = []
    @State private var approvedConsentOps: [SkillInstaller.Op] = []
    @State private var pendingNonConsentOps: [SkillInstaller.Op] = []
    @State private var activeConsentDirectory: URL?
    @State private var activeConsentTarget: SkillTarget?
    @State private var installResults: [SkillInstallExecutor.OpResult] = []
    @State private var installBlocked: [SkillInstaller.BlockedOp] = []
    @State private var showInstallResults = false
    @State private var retryPlan: RetryPlan?

    struct DirectorySection: Identifiable {
        let target: SkillTarget
        let directory: URL
        var rows: [SkillRow]
        var id: String { target.rawValue }
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
        let target: SkillTarget
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
        .onChange(of: settingsStore.settings) { _, _ in
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
                        DispatchQueue.main.async {
                            executeAndRefresh(plan: retry.plan, target: retry.target, directory: retry.directory)
                        }
                    }
                } : nil
            )
        }
    }

    // MARK: - Layout variants

    @ViewBuilder
    private func singleDirectoryContent(_ section: DirectorySection) -> some View {
        Section {
                Button("Update All Clean") { performBulkAction(.updateAllClean, target: section.target, directory: section.directory) }
                    .disabled(!hasSomeUpdatable(in: section))
                Button("Update All") { performBulkAction(.updateAll, target: section.target, directory: section.directory) }
                    .disabled(!hasSomeUpdatable(in: section))
                Button("Remove All Unmodified") { performBulkAction(.removeAllUnmodified, target: section.target, directory: section.directory) }
                    .disabled(!hasSomeRemovable(in: section))
            } header: {
                directoryHeader(section)
            }
            Section("Skills") {
                ForEach(section.rows, id: \.name) { row in
                    skillRow(row, target: section.target, directory: section.directory)
                }
            }
        }

    @ViewBuilder
    private var multiDirectoryContent: some View {
        ForEach(sections) { section in
            Section {
                Button("Update All Clean") { performBulkAction(.updateAllClean, target: section.target, directory: section.directory) }
                    .disabled(!hasSomeUpdatable(in: section))
                Button("Update All") { performBulkAction(.updateAll, target: section.target, directory: section.directory) }
                    .disabled(!hasSomeUpdatable(in: section))
                Button("Remove All Unmodified") { performBulkAction(.removeAllUnmodified, target: section.target, directory: section.directory) }
                    .disabled(!hasSomeRemovable(in: section))
                ForEach(section.rows, id: \.name) { row in
                    skillRow(row, target: section.target, directory: section.directory)
                }
            } header: {
                directoryHeader(section)
            }
        }
    }

    @ViewBuilder
    private func directoryHeader(_ section: DirectorySection) -> some View {
        HStack {
            Text("\(section.target.displayName): \(abbreviatedPath(section.directory))")
            Spacer()
            Button {
                NSWorkspace.shared.open(section.directory)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Per-skill row

    @ViewBuilder
    private func skillRow(_ row: SkillRow, target: SkillTarget, directory: URL) -> some View {
        HStack {
            Text(row.name)
                .font(.body)
            Spacer()
            classificationChip(row.classification)
            Button(Self.updateButtonLabel(for: row.classification)) { performUpdate(skillName: row.name, target: target, directory: directory) }
            Button("Remove") { performRemove(skillName: row.name, target: target, directory: directory) }
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

    static func updateButtonLabel(for state: SkillClassifier.State) -> String {
        state == .missing ? "Install" : "Update"
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

    private func performUpdate(skillName: String, target: SkillTarget, directory: URL) {
        guard let inputs = buildInputs(for: directory) else { return }
        let plan = SkillInstaller.plan(skills: inputs, intent: .updateSpecific(name: skillName))
        startConsentFlow(for: plan, target: target, directory: directory)
    }

    private func performRemove(skillName: String, target: SkillTarget, directory: URL) {
        guard let inputs = buildInputs(for: directory) else { return }
        let plan = SkillInstaller.plan(skills: inputs, intent: .removeSpecific(name: skillName))
        executeAndRefresh(plan: plan, target: target, directory: directory)
    }

    private func performBulkAction(_ intent: SkillInstaller.UserIntent, target: SkillTarget, directory: URL) {
        guard let inputs = buildInputs(for: directory) else { return }
        let plan = SkillInstaller.plan(skills: inputs, intent: intent)
        startConsentFlow(for: plan, target: target, directory: directory)
    }

    private func startConsentFlow(for plan: SkillInstaller.Plan, target: SkillTarget, directory: URL) {
        let consentOps = Self.opsRequiringConsent(in: plan)
        let nonConsent = plan.ops.filter {
            guard case .update(_, _, let requiresConsent) = $0 else { return true }
            return !requiresConsent
        }

        guard !consentOps.isEmpty else {
            executeAndRefresh(plan: plan, target: target, directory: directory)
            return
        }

        activeConsentDirectory = directory
        activeConsentTarget = target
        pendingNonConsentOps = nonConsent
        approvedConsentOps = []

        var consents: [PendingConsent] = []
        for op in consentOps {
            guard case .update(let name, let sourceURL, _) = op else { continue }
            let bundledContent = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
            let onDiskFile = SkillClassifier.installedSkillFileURL(
                skillsDirectory: directory,
                skillName: name,
                target: target
            )
            let onDiskContent = (try? String(contentsOf: onDiskFile, encoding: .utf8)) ?? ""
            consents.append(PendingConsent(
                op: op,
                skillName: name,
                bundledContent: bundledContent,
                onDiskContent: onDiskContent
            ))
        }

        guard !consents.isEmpty else {
            executeAndRefresh(plan: plan, target: target, directory: directory)
            return
        }

        remainingConsents = Array(consents.dropFirst())
        currentConsent = consents.first
    }

    private func advanceConsent() {
        if remainingConsents.isEmpty {
            let resolvedPlan = SkillInstaller.Plan(ops: pendingNonConsentOps + approvedConsentOps, blocked: [])
            let dir = activeConsentDirectory
            let target = activeConsentTarget
            currentConsent = nil
            pendingNonConsentOps = []
            approvedConsentOps = []
            activeConsentDirectory = nil
            activeConsentTarget = nil
            if let dir, let target {
                DispatchQueue.main.async {
                    executeAndRefresh(plan: resolvedPlan, target: target, directory: dir)
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

    private func executeAndRefresh(plan: SkillInstaller.Plan, target: SkillTarget, directory: URL) {
        let results = SkillInstallExecutor.execute(plan: plan, skillsDirectory: directory, target: target)
        loadClassifications()
        if SkillInstallResultSheet.shouldPresent(results: results, blocked: plan.blocked) {
            retryPlan = RetryPlan(plan: plan, directory: directory, target: target)
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

        sections = Self.makeSections(manifestByName: manifestByName, bundledByName: bundledByName)
    }

    static func makeSections(
        manifestByName: [String: SkillManifestEntry],
        bundledByName: [String: SkillBundleReader.BundledSkill]
    ) -> [DirectorySection] {
        SkillTarget.allCases.map { target in
            let dir = target.directory
            let rows = PresenceChecker.requiredSkills.compactMap { name -> SkillRow? in
                guard let entry = manifestByName[name], let bundled = bundledByName[name] else { return nil }
                let skillFile = SkillClassifier.installedSkillFileURL(
                    skillsDirectory: dir,
                    skillName: name,
                    target: target
                )
                let bytesOnDisk = try? Data(contentsOf: skillFile)
                let state = SkillClassifier.classify(
                    bytesOnDisk: bytesOnDisk,
                    currentHash: entry.sha256,
                    priorHashes: entry.priorSha256s
                )
                return SkillRow(name: name, classification: state, sourceURL: bundled.fileURL)
            }
            return DirectorySection(target: target, directory: dir, rows: rows)
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

private extension SkillTarget {
    var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .pi:
            return "Pi"
        case .openCode:
            return "OpenCode"
        }
    }
}
