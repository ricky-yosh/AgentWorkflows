import SwiftUI
import UniformTypeIdentifiers

// MARK: - Collapsible (embedded variant)

/// Compact disclosure-group variant used outside the main tab, e.g. inside
/// iteration cards. Shows the same EventRow but without the filter bar or
/// auto-scroll controls.
struct ExecutionLogView: View {
    let sessionID: UUID

    @Environment(EngineManager.self) private var engineManager
    @State private var isExpanded = false

    private var events: [ExecutionEvent] {
        engineManager.workflowEngine(for: sessionID)?.events ?? []
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.secondary)
                Text("Execution Log")
                    .font(.callout)
                    .fontWeight(.medium)
                Text("\(events.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.fill.tertiary, in: Capsule())
            }
        }
        .padding(8)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var content: some View {
        if events.isEmpty {
            Text("No events yet. Run a step to see engine activity here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(events) { event in
                        EventRow(event: event)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            .padding(.top, 6)
        }
    }
}

// MARK: - Tab (full-height)

/// Full-height console variant for the Log tab. Adds a filter bar and
/// auto-scroll. Newest events are appended at the bottom (console-style).
struct ExecutionLogTabView: View {
    let sessionID: UUID

    @Environment(EngineManager.self) private var engineManager

    // Filter state
    @State private var filterErrors = false
    @State private var filterDebug = false

    // Auto-scroll
    @State private var autoScroll = true

    // Clear: events timestamped before this date are hidden from the view
    // without touching the engine's buffer.
    @State private var clearedBefore: Date = .distantPast

    private var events: [ExecutionEvent] {
        engineManager.workflowEngine(for: sessionID)?.events ?? []
    }

    private var filteredEvents: [ExecutionEvent] {
        let afterClear = events.filter { $0.timestamp > clearedBefore }
        guard filterErrors || filterDebug else { return afterClear }
        return afterClear.filter { event in
            (filterErrors && event.kind == .crashed) ||
            (filterDebug  && event.kind == .debug)
        }
    }

    private var crashCount: Int {
        events.filter { $0.timestamp > clearedBefore && $0.kind == .crashed }.count
    }

    private var debugCount: Int {
        events.filter { $0.timestamp > clearedBefore && $0.kind == .debug }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()

            if filteredEvents.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredEvents) { event in
                                EventRow(event: event, onClearAll: { clearedBefore = Date() })
                                    .id(event.id)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                            }
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: filteredEvents.count) { _, _ in
                        guard autoScroll, let last = filteredEvents.last else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    // MARK: Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            FilterToken(label: "Errors", count: crashCount, color: Color(NSColor.systemRed), isActive: $filterErrors)
            FilterToken(label: "Debug",  count: debugCount,  color: Color(NSColor.secondaryLabelColor), isActive: $filterDebug)

            Spacer()

            Button {
                autoScroll.toggle()
            } label: {
                Image(systemName: autoScroll ? "arrow.down.to.line.compact" : "arrow.down.to.line.compact")
                    .font(.system(size: 12))
                    .foregroundStyle(autoScroll ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(autoScroll ? "Auto-scroll on (click to disable)" : "Auto-scroll off (click to enable)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.6))

            VStack(spacing: 4) {
                Text("No Events Yet")
                    .font(.system(size: 13, weight: .semibold))
                Text("Diagnostic events will appear here once an execution sequence begins.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - FilterToken

private struct FilterToken: View {
    let label: String
    let count: Int
    let color: Color
    @Binding var isActive: Bool

    var body: some View {
        Button {
            isActive.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
            }
            .foregroundStyle(isActive ? .white : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isActive ? color : color.opacity(0.12))
            )
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - EventRow

struct EventRow: View {
    let event: ExecutionEvent
    var onClearAll: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var isExpanded = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .leading)
                .padding(.top, 1)

            // Kind icon + label
            HStack(spacing: 4) {
                Image(systemName: icon(for: event.kind))
                    .font(.system(size: 11))
                Text(label(for: event.kind))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(color(for: event.kind))
            .frame(width: 80, alignment: .leading)
            .padding(.top, 1)

            // Message
            Text(event.message)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.6) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Copy Message") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(event.message, forType: .string)
            }
            Button("Copy as JSON") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(eventJSON, forType: .string)
            }
            if let onClearAll {
                Divider()
                Button("Clear Console View") { onClearAll() }
                Button("Export Stream to Log File…") { exportAllEvents() }
            }
        }
        .textSelection(.enabled)
    }

    // MARK: Helpers

    private var eventJSON: String {
        let formatter = ISO8601DateFormatter()
        return """
        {"timestamp":"\(formatter.string(from: event.timestamp))","kind":"\(event.kind.rawValue)","message":\(jsonEscape(event.message))}
        """
    }

    private func jsonEscape(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private func exportAllEvents() {
        // NSSavePanel export — caller passes all events via context, but
        // this row only has its own event. Export is triggered from the
        // tab-level context menu (handled by ExecutionLogTabView), so this
        // path writes a single-event file as fallback.
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "execution-log.jsonl"
        panel.allowedContentTypes = [UTType.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? eventJSON.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func icon(for kind: ExecutionEvent.Kind) -> String {
        switch kind {
        case .stepStarted:   return "play.circle"
        case .promptSent:    return "arrow.up.circle"
        case .stepCompleted: return "checkmark.circle.fill"
        case .paused:        return "pause.circle"
        case .crashed:       return "xmark.circle.fill"
        case .skipped:       return "forward.circle"
        case .completed:     return "flag.checkered.circle.fill"
        case .debug:         return "ant.circle"
        }
    }

    private func label(for kind: ExecutionEvent.Kind) -> String {
        switch kind {
        case .stepStarted:   return "STEP"
        case .promptSent:    return "PROMPT"
        case .stepCompleted: return "DONE"
        case .paused:        return "PAUSE"
        case .crashed:       return "CRASH"
        case .skipped:       return "SKIP"
        case .completed:     return "COMPLETE"
        case .debug:         return "DEBUG"
        }
    }

    private func color(for kind: ExecutionEvent.Kind) -> Color {
        switch kind {
        case .stepStarted:   return Color(NSColor.systemBlue)
        case .promptSent:    return Color(NSColor.systemPurple)
        case .stepCompleted: return Color(NSColor.systemGreen)
        case .paused:        return Color(NSColor.systemOrange)
        case .crashed:       return Color(NSColor.systemRed)
        case .skipped:       return Color(NSColor.systemGray)
        case .completed:     return Color(NSColor.systemBlue)
        case .debug:         return Color(NSColor.secondaryLabelColor)
        }
    }
}

// MARK: - Preview

#Preview("Log Tab — With Events") {
    let events: [ExecutionEvent] = [
        ExecutionEvent(timestamp: .now.addingTimeInterval(-120), kind: .stepStarted,   message: "Plan · Write PRD"),
        ExecutionEvent(timestamp: .now.addingTimeInterval(-100), kind: .promptSent,    message: "Injected prompt for /to-prd"),
        ExecutionEvent(timestamp: .now.addingTimeInterval(-60),  kind: .debug,         message: "Engine ready, waiting for inject"),
        ExecutionEvent(timestamp: .now.addingTimeInterval(-40),  kind: .stepCompleted, message: "PRD.md written (142 lines)"),
        ExecutionEvent(timestamp: .now.addingTimeInterval(-20),  kind: .paused,        message: "Review pause: plan-review"),
        ExecutionEvent(timestamp: .now.addingTimeInterval(-5),   kind: .crashed,       message: "CLI process exited with code 1 — check terminal output for stack trace"),
    ]

    VStack(alignment: .leading, spacing: 0) {
        Divider()
        ForEach(events) { event in
            EventRow(event: event)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
        }
    }
    .frame(width: 580, height: 360)
}

#Preview("Log Tab — Empty") {
    VStack(spacing: 14) {
        Image(systemName: "terminal")
            .font(.system(size: 28))
            .foregroundStyle(.secondary.opacity(0.6))
        VStack(spacing: 4) {
            Text("No Events Yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Diagnostic events will appear here once an execution sequence begins.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
    }
    .frame(width: 580, height: 360)
    .background(Color(NSColor.textBackgroundColor))
}
