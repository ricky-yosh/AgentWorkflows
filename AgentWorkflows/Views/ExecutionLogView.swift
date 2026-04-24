import SwiftUI

/// Collapsible log of events emitted by the active workflow engine —
/// prompt sent, step completed, crash, etc. Provides transparency into
/// what the engine is doing so users don't have to guess why a step is
/// stuck.
///
/// Newest events render at the top. Limited to the engine's bounded
/// event buffer (currently 200 entries).
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
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(events.reversed()) { event in
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

// MARK: - Tab

/// Full-height, non-collapsible variant suitable for embedding as a tab.
/// Reads from the engine's in-memory buffer (which is hydrated from
/// `events.jsonl` on engine init), so history survives relaunches as
/// long as the session is re-opened.
struct ExecutionLogTabView: View {
    let sessionID: UUID

    @Environment(EngineManager.self) private var engineManager

    private var events: [ExecutionEvent] {
        engineManager.workflowEngine(for: sessionID)?.events ?? []
    }

    var body: some View {
        if events.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("No events yet. Press Play to begin.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(events.reversed()) { event in
                        EventRow(event: event)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Row

fileprivate struct EventRow: View {
    let event: ExecutionEvent

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 68, alignment: .leading)

            Text(label(for: event.kind))
                .font(.callout)
                .foregroundStyle(color(for: event.kind))
                .frame(width: 74, alignment: .leading)

            Text(event.message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 4)
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
        }
    }

    private func color(for kind: ExecutionEvent.Kind) -> Color {
        switch kind {
        case .stepStarted:   return .blue
        case .promptSent:    return .purple
        case .stepCompleted: return .green
        case .paused:        return .orange
        case .crashed:       return .red
        case .skipped:       return .gray
        case .completed:     return .blue
        }
    }
}
