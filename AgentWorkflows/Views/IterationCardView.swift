import SwiftUI

/// Renders one Iteration. The current Iteration is expanded by default;
/// prior Iterations start collapsed to a one-line summary header. Tap the
/// header to toggle. When expanded, shows the Task band, optional Live
/// Tool-Call Line, and a scrollable event transcript.
struct IterationCardView: View {
    let record: IterationRecord
    let liveToolCall: (name: String, inputSummary: String)?
    let isCurrent: Bool

    /// nil = use default (expanded when current, collapsed otherwise).
    @State private var userExpanded: Bool? = nil

    private var isExpanded: Bool { userExpanded ?? isCurrent }

    private var toolCallCount: Int {
        record.events.filter { if case .toolUse = $0 { return true }; return false }.count
    }

    private var durationLabel: String? {
        guard let end = record.endDate else { return nil }
        let secs = max(0, end.timeIntervalSince(record.startDate))
        return SessionRunStatus.formatElapsed(secs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                if let tool = liveToolCall, isCurrent {
                    Divider()
                    liveToolCallLine(name: tool.name, inputSummary: tool.inputSummary)
                }
                Divider()
                transcript
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    // MARK: - Header (always visible)

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Text("Iter \(record.id)")
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.fill.secondary, in: Capsule())

            if let taskID = record.taskID {
                Text("#\(taskID)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            if let desc = record.taskDescription {
                Text(desc)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? 2 : 1)
            } else {
                Text("Reading tasks…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .italic()
            }

            Spacer()

            // Collapsed summary: tool count + duration
            if !isExpanded {
                HStack(spacing: 6) {
                    if toolCallCount > 0 {
                        Text("\(toolCallCount) tools")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let dur = durationLabel {
                        Text(dur)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Session id: always visible, copyable
            if let sessionId = record.sessionId {
                Text(sessionId.prefix(8))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .help("Anthropic session id: \(sessionId)")
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { userExpanded = !isExpanded }
    }

    // MARK: - Live Tool-Call Line

    @ViewBuilder
    private func liveToolCallLine(name: String, inputSummary: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.adjustable")
                .font(.callout)
                .foregroundStyle(.orange)
            Text(name)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
            Text(inputSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.orange.opacity(0.12))
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcript: some View {
        let visibleEvents = record.events.filter {
            if case .sessionStarted = $0 { return false }
            if case .modelIdentified = $0 { return false }
            if case .iterationFinished = $0 { return false }
            return true
        }

        if visibleEvents.isEmpty {
            Text("Waiting for output…")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .italic()
                .padding(10)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(0..<visibleEvents.count, id: \.self) { i in
                            EventLineView(event: visibleEvents[i])
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                }
                .frame(maxHeight: 280)
                .onChange(of: visibleEvents.count) {
                    scrollTranscriptToBottom(using: proxy, animated: true)
                }
                .onChange(of: isExpanded) { _, expanded in
                    if expanded {
                        scrollTranscriptToBottom(using: proxy, animated: false)
                    }
                }
            }
        }
    }

    private func scrollTranscriptToBottom(
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

// MARK: - EventLineView

private struct EventLineView: View {
    let event: IterationEvent

    var body: some View {
        switch event {
        case .assistantText(let text):
            HStack(spacing: 8) {
                EventTypeBadge(label: "assistant", bg: Color(hex: "#e8f5e9"), fg: Color(hex: "#2e7d32"))
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .toolUse(let name, let summary):
            HStack(spacing: 8) {
                EventTypeBadge(label: "tool", bg: Color(hex: "#e3f2fd"), fg: Color(hex: "#1565c0"))
                HStack(spacing: 4) {
                    Text("▶ \(name)")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

        case .toolResult(let summary, _):
            HStack(spacing: 8) {
                EventTypeBadge(label: "result", bg: Color(hex: "#f3e5f5"), fg: Color(hex: "#7b1fa2"))
                HStack(spacing: 4) {
                    Text("◀")
                        .font(.callout)
                        .foregroundStyle(.green)
                    Text(summary)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

        case .sessionStarted, .modelIdentified, .iterationFinished:
            EmptyView()
        }
    }
}

private struct EventTypeBadge: View {
    let label: String
    let bg: Color
    let fg: Color

    var body: some View {
        Text(label)
            .font(.system(size: 10))
            .fontWeight(.medium)
            .foregroundStyle(fg)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(bg, in: RoundedRectangle(cornerRadius: 2))
    }
}

// MARK: - IterationsView

/// Full "Iterations" tab content: tasks grouped with their iterations nested
/// beneath each task header. Falls back to a flat list when tasks.json is absent.
struct IterationsView: View {
    let sessionID: UUID
    var tasksFileURL: URL? = nil

    @Environment(EngineManager.self) private var engineManager
    @State private var tasks: [TaskEntry] = []

    private var status: SessionRunStatus {
        engineManager.runStatus(for: sessionID)
    }

    var body: some View {
        let hasContent = !tasks.isEmpty || !status.iterationRecords.isEmpty
        Group {
            if !hasContent {
                emptyState
            } else if tasks.isEmpty {
                flatScrollView
            } else {
                groupedScrollView
            }
        }
        .task(id: tasksFileURL) { loadTasks() }
        .onChange(of: status.tasksPassed) { loadTasks() }
        .onChange(of: status.tasksTotal) { loadTasks() }
    }

    // MARK: Flat fallback (no tasks.json)

    private var flatScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(status.iterationRecords.reversed()) { record in
                    let isCurrent = record.id == status.iterationRecords.last?.id
                    IterationCardView(
                        record: record,
                        liveToolCall: isCurrent ? status.liveToolCall : nil,
                        isCurrent: isCurrent
                    )
                }
            }
            .padding(12)
        }
    }

    // MARK: Grouped by task

    private var groupedScrollView: some View {
        let currentIterationID = status.iterationRecords.last?.id
        return ScrollView {
            LazyVStack(spacing: 16) {
                // Iterations that fired before tasks.json was readable
                let ungrouped = status.iterationRecords.filter { $0.taskID == nil }
                ForEach(ungrouped) { record in
                    IterationCardView(record: record, liveToolCall: nil, isCurrent: false)
                }

                ForEach(tasks) { task in
                    let iters = status.iterationRecords.filter { $0.taskID == task.id }
                    let isActive = iters.last?.id == currentIterationID && currentIterationID != nil
                    TaskGroupView(
                        task: task,
                        iterations: iters,
                        liveToolCall: isActive ? status.liveToolCall : nil,
                        currentIterationID: currentIterationID
                    )
                }
            }
            .padding(12)
        }
    }

    // MARK: Helpers

    private func loadTasks() {
        guard let url = tasksFileURL,
              let data = FileManager.default.contents(atPath: url.path),
              let decoded = try? JSONDecoder().decode([TaskEntry].self, from: data) else {
            tasks = []
            return
        }
        tasks = decoded
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "repeat")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No iterations yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Press Play to begin.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - TaskGroupView

/// One task with its iteration cards nested beneath. The task header shows
/// completion status and is tappable to expand/collapse the nested cards.
private struct TaskGroupView: View {
    let task: TaskEntry
    let iterations: [IterationRecord]
    let liveToolCall: (name: String, inputSummary: String)?
    let currentIterationID: Int?

    @State private var isExpanded: Bool

    init(
        task: TaskEntry,
        iterations: [IterationRecord],
        liveToolCall: (name: String, inputSummary: String)?,
        currentIterationID: Int?
    ) {
        self.task = task
        self.iterations = iterations
        self.liveToolCall = liveToolCall
        self.currentIterationID = currentIterationID
        let isActiveGroup = !iterations.isEmpty && iterations.last?.id == currentIterationID
        _isExpanded = State(initialValue: isActiveGroup)
    }

    private var criteria: [String] { task.acceptance_criteria ?? [] }
    private var isExpandable: Bool { !iterations.isEmpty || !criteria.isEmpty }

    private var isActiveGroup: Bool {
        guard let id = currentIterationID else { return false }
        return iterations.contains { $0.id == id }
    }

    private var statusText: String {
        if task.passes { return "Completed" }
        return iterations.isEmpty ? "Pending" : "In Progress"
    }

    private var statusColors: (bg: Color, fg: Color) {
        if task.passes {
            return (Color(hex: "#e8f5e9"), Color(hex: "#2e7d32"))
        } else if iterations.isEmpty {
            return (Color(hex: "#f5f5f5"), Color(hex: "#757575"))
        } else {
            return (Color(hex: "#e3f2fd"), Color(hex: "#1565c0"))
        }
    }

    private var isPending: Bool { !task.passes && iterations.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            taskHeader
            if isExpanded {
                if !criteria.isEmpty {
                    acceptanceCriteria
                        .padding(.leading, 16)
                }
                if !iterations.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(iterations) { record in
                            let isCurrent = record.id == currentIterationID
                            IterationCardView(
                                record: record,
                                liveToolCall: isCurrent ? liveToolCall : nil,
                                isCurrent: isCurrent
                            )
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }
        .opacity(isPending ? 0.6 : 1.0)
        .onChange(of: isActiveGroup) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded = true }
            }
        }
    }

    private var taskHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: task.passes ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(task.passes ? Color.green : Color.secondary)

            Text("#\(task.id)")
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(task.description)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer()

            Text(statusText)
                .font(.system(size: 10))
                .fontWeight(.medium)
                .foregroundStyle(statusColors.fg)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(statusColors.bg, in: RoundedRectangle(cornerRadius: 4))

            if let effort = task.effort {
                Text(effort)
                    .font(.system(size: 10))
                    .fontWeight(.medium)
                    .foregroundStyle(Color(hex: "#7b1fa2"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color(hex: "#f3e5f5"), in: RoundedRectangle(cornerRadius: 4))
            }

            if !iterations.isEmpty {
                if isActiveGroup {
                    LiveIndicator(count: iterations.count)
                } else {
                    Text("\(iterations.count) iter\(iterations.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            if isExpandable {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            Group {
                if task.passes {
                    RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.08))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard isExpandable else { return }
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
        }
    }

    private var acceptanceCriteria: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Acceptance Criteria")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            ForEach(Array(criteria.enumerated()), id: \.offset) { _, criterion in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: task.passes ? "checkmark.circle.fill" : "circle")
                        .font(.caption2)
                        .foregroundStyle(task.passes ? Color.green : Color.secondary)
                        .padding(.top, 1)

                    Text(criterion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - LiveIndicator

/// Pulsing green dot + "N iteration(s) (live)" shown on the active task group header.
private struct LiveIndicator: View {
    let count: Int
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: "#34c759"))
                .frame(width: 6, height: 6)
                .opacity(isPulsing ? 0.4 : 1.0)
            Text("\(count) iteration\(count == 1 ? "" : "s") (live)")
                .font(.system(size: 10))
                .fontWeight(.medium)
                .foregroundStyle(Color(hex: "#34c759"))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - TaskEntry

private struct TaskEntry: Decodable, Identifiable {
    var id: Int
    var description: String
    var passes: Bool
    var effort: String?
    var acceptance_criteria: [String]?
}
