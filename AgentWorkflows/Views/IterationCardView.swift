import SwiftUI

// MARK: - IterationCardView

/// Renders one Iteration. Current iteration starts expanded; prior ones start
/// collapsed to a one-line summary. Tap the header to toggle.
struct IterationCardView: View {
    let record: IterationRecord
    let liveToolCall: (name: String, inputSummary: String)?
    let isCurrent: Bool

    @State private var userExpanded: Bool? = nil
    @State private var isHovered = false

    private var isExpanded: Bool { userExpanded ?? isCurrent }
    private var isLive: Bool { isCurrent && liveToolCall != nil }

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
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isLive ? Color(NSColor.systemGreen).opacity(0.5) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .shadow(
            color: isLive
                ? Color(NSColor.systemGreen).opacity(0.12)
                : .black.opacity(isHovered ? 0.08 : 0.03),
            radius: isHovered || isLive ? 5 : 2,
            y: 1
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Copy Iteration ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("Iter \(record.id)", forType: .string)
            }
            if let sessionId = record.sessionId {
                Button("Copy Session ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(sessionId, forType: .string)
                }
            }
            Button("Copy Transcript") {
                let text = record.events.compactMap { event -> String? in
                    switch event {
                    case .assistantText(let t): return "assistant: \(t)"
                    case .toolUse(let name, let summary): return "tool: \(name) \(summary)"
                    case .toolResult(let summary, _): return "result: \(summary)"
                    default: return nil
                    }
                }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            // Leading chevron (macOS convention)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isExpanded)
                .frame(width: 12)

            Text("Iter \(record.id)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.1), in: Capsule())

            if let taskID = record.taskID {
                Text("\(taskID)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
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

            if !isExpanded {
                HStack(spacing: 6) {
                    if toolCallCount > 0 {
                        Text("\(toolCallCount) tools")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    if let dur = durationLabel {
                        Text(dur)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let sessionId = record.sessionId {
                Text(sessionId.prefix(8))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .textSelection(.enabled)
                    .help("Session: \(sessionId)")
            }
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
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(visibleEvents.enumerated()), id: \.offset) { _, event in
                            EventLineView(event: event)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                }
                .frame(maxHeight: 280)
                // Distinct terminal-zone background so users know they can scroll here
                .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                .onChange(of: visibleEvents.count) {
                    scrollTranscriptToBottom(using: proxy, animated: true)
                }
                .onChange(of: isExpanded) { _, expanded in
                    if expanded { scrollTranscriptToBottom(using: proxy, animated: false) }
                }
            }
        }
    }

    private func scrollTranscriptToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
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
            AccentRow(color: Color(NSColor.systemGreen)) {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .toolUse(let name, let summary):
            AccentRow(color: Color(NSColor.systemBlue)) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(NSColor.systemBlue))
                    if !summary.isEmpty {
                        // Input paths and commands stay monospaced; tool name does not
                        Text(summary)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .toolResult(let summary, _):
            AccentRow(color: Color(NSColor.systemPurple)) {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .sessionStarted, .modelIdentified, .iterationFinished:
            EmptyView()
        }
    }
}

private struct AccentRow<Content: View>: View {
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 2)
            content
                .padding(.leading, 8)
                .padding(.vertical, 2)
        }
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

    private var groupedScrollView: some View {
        let currentIterationID = status.iterationRecords.last?.id
        return ScrollView {
            LazyVStack(spacing: 16) {
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
/// completion status and is tappable to expand/collapse.
private struct TaskGroupView: View {
    let task: TaskEntry
    let iterations: [IterationRecord]
    let liveToolCall: (name: String, inputSummary: String)?
    let currentIterationID: Int?

    @State private var isExpanded: Bool
    @State private var isHovered = false

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

    private var statusForeground: Color {
        if task.passes { return Color(NSColor.systemGreen) }
        if iterations.isEmpty { return Color(NSColor.secondaryLabelColor) }
        return Color(NSColor.systemBlue)
    }

    private var isPending: Bool { !task.passes && iterations.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            taskHeader
            if isExpanded {
                Divider()
                expandedContent
            }
        }
        .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .shadow(
            color: .black.opacity(isHovered ? 0.08 : 0.03),
            radius: isHovered ? 5 : 2,
            y: isHovered ? 2 : 1
        )
        .opacity(isPending ? 0.6 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Copy Task ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(task.id)", forType: .string)
            }
            Button("Copy Description") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(task.description, forType: .string)
            }
            if let ac = task.acceptance_criteria, !ac.isEmpty {
                Button("Copy Acceptance Criteria") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ac.joined(separator: "\n"), forType: .string)
                }
            }
        }
        .onChange(of: isActiveGroup) { _, active in
            if active {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded = true }
            }
        }
    }

    private var taskHeader: some View {
        HStack(spacing: 8) {
            // Leading chevron (macOS convention: Finder/Xcode tree style)
            Group {
                if isExpandable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isExpanded)
                } else {
                    Color.clear
                }
            }
            .frame(width: 12, height: 12)

            Image(systemName: task.passes ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(task.passes ? Color(NSColor.systemGreen) : Color.secondary)

            // Task ID capsule without # prefix
            Text("\(task.id)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(NSColor.quaternaryLabelColor).opacity(0.5), in: Capsule())

            Text(task.description)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer()

            // Status badge: colored text, neutral background
            Text(statusText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(statusForeground)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.quaternaryLabelColor).opacity(0.4), in: Capsule())

            if let effort = task.effort {
                Text(effort)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.quaternaryLabelColor).opacity(0.4), in: Capsule())
            }

            if !iterations.isEmpty {
                if isActiveGroup {
                    LiveIndicator(count: iterations.count)
                } else {
                    Text("\(iterations.count) iter\(iterations.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isExpandable else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded.toggle() }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        // Vertical hierarchy track: aligned under the circle icon center.
        // Header layout: 10pt hPad + 12pt chevron + 8pt gap + 7pt (half 14pt circle) = 37pt
        VStack(alignment: .leading, spacing: 8) {
            if !criteria.isEmpty {
                acceptanceCriteria
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
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .padding(.leading, 52)  // 37pt track position + 15pt gap
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 0) {
                Spacer().frame(width: 37)
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var acceptanceCriteria: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Acceptance Criteria")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            ForEach(Array(criteria.enumerated()), id: \.offset) { _, criterion in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: task.passes ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(task.passes ? Color(NSColor.systemGreen) : Color.secondary)
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
        .background(Color(NSColor.quaternaryLabelColor).opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - LiveIndicator

/// Pulsing dot shown on the active task group. The live border glow on
/// IterationCardView carries the real-time signal; this just shows iteration count.
private struct LiveIndicator: View {
    let count: Int
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(NSColor.systemGreen))
                .frame(width: 6, height: 6)
                .opacity(isPulsing ? 0.3 : 1.0)
            Text("\(count) iter\(count == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color(NSColor.systemGreen))
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

// MARK: - Previews

private struct IterationCardPreviewWrapper: View {
    var body: some View {
        let sampleEvents: [IterationEvent] = [
            .assistantText("I'll add the preview macro to all 10 files now."),
            .toolUse(name: "Read", inputSummary: "IterationCardView.swift"),
            .toolResult(summary: "Read 595 lines", failed: false),
            .toolUse(name: "Edit", inputSummary: "IterationCardView.swift"),
            .toolResult(summary: "Replaced 2 lines", failed: false),
            .assistantText("Done! All previews added."),
        ]

        let liveRecord = IterationRecord(
            id: 3, taskID: 2, taskDescription: "Add #Preview macros to all view files",
            sessionId: "sess_abc12345def67890", startDate: .now.addingTimeInterval(-45),
            endDate: nil, events: sampleEvents
        )

        let completedRecord = IterationRecord(
            id: 2, taskID: 1, taskDescription: "Set up session registry",
            sessionId: "sess_1111111122222222", startDate: .now.addingTimeInterval(-300),
            endDate: .now.addingTimeInterval(-120), events: [
                .assistantText("Let me read the existing code first."),
                .toolUse(name: "Glob", inputSummary: "**/*.swift"),
                .toolResult(summary: "Found 35 files", failed: false),
                .assistantText("Implementing the changes now."),
            ]
        )

        ScrollView {
            VStack(spacing: 12) {
                Text("Live (current iteration)")
                    .font(.caption).foregroundStyle(.secondary)
                IterationCardView(
                    record: liveRecord,
                    liveToolCall: (name: "Edit", inputSummary: "IterationCardView.swift"),
                    isCurrent: true
                )

                Text("Completed (collapsed)")
                    .font(.caption).foregroundStyle(.secondary)
                IterationCardView(
                    record: completedRecord,
                    liveToolCall: nil,
                    isCurrent: false
                )
            }
            .padding()
        }
    }
}

#Preview("Iteration Cards") {
    IterationCardPreviewWrapper()
}

private struct TaskGroupPreviewWrapper: View {
    var body: some View {
        let sampleEvents: [IterationEvent] = [
            .assistantText("Starting implementation."),
            .toolUse(name: "Read", inputSummary: "Models/Session.swift"),
            .toolResult(summary: "Read 120 lines", failed: false),
            .assistantText("Done."),
        ]

        let iter1 = IterationRecord(
            id: 1, taskID: 1, taskDescription: "Set up session registry",
            sessionId: "sess_aabbccdd11223344", startDate: .now.addingTimeInterval(-400),
            endDate: .now.addingTimeInterval(-300), events: sampleEvents
        )
        let iter2 = IterationRecord(
            id: 2, taskID: 2, taskDescription: "Add #Preview macros",
            sessionId: "sess_aabbccdd55667788", startDate: .now.addingTimeInterval(-60),
            endDate: nil, events: sampleEvents
        )

        let completedTask = TaskEntry(
            id: 1, description: "Set up session registry", passes: true, effort: "S",
            acceptance_criteria: ["SessionStore initialises on launch", "Sessions persist across restarts"]
        )
        let activeTask = TaskEntry(
            id: 2, description: "Add #Preview macros to all view files", passes: false, effort: "M",
            acceptance_criteria: ["Every view file has at least one #Preview", "Previews render without crashes"]
        )
        let pendingTask = TaskEntry(
            id: 3, description: "Write unit tests for EngineManager", passes: false, effort: "L",
            acceptance_criteria: nil
        )

        ScrollView {
            VStack(spacing: 16) {
                TaskGroupView(
                    task: completedTask,
                    iterations: [iter1],
                    liveToolCall: nil,
                    currentIterationID: 2
                )
                TaskGroupView(
                    task: activeTask,
                    iterations: [iter2],
                    liveToolCall: (name: "Edit", inputSummary: "SomeView.swift"),
                    currentIterationID: 2
                )
                TaskGroupView(
                    task: pendingTask,
                    iterations: [],
                    liveToolCall: nil,
                    currentIterationID: 2
                )
            }
            .padding()
        }
    }
}

#Preview("Task Groups") {
    TaskGroupPreviewWrapper()
}
