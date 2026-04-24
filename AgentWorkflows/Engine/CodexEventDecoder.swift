import Foundation

/// Parses one line of `codex exec --json` stdout into zero or more `IterationEvent`s.
/// Stateful: tracks the last agent_message text so `turn.completed` can populate
/// `iterationFinished(result:)`. Malformed JSON increments `malformedCount`; unknown
/// frame types and frames with missing optional fields are silently dropped.
final class CodexEventDecoder {

    private(set) var malformedCount: Int = 0
    private var lastAgentMessageText: String = ""

    /// Decode one stdout line into zero or more IterationEvents.
    func decode(_ line: String) -> [IterationEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            malformedCount += 1
            return []
        }

        guard let type = json["type"] as? String else { return [] }

        switch type {
        case "thread.started":  return decodeThreadStarted(json)
        case "turn.started":    return []
        case "item.started":    return decodeItemStarted(json)
        case "item.completed":  return decodeItemCompleted(json)
        case "turn.completed":  return [.iterationFinished(result: lastAgentMessageText)]
        default:                return []
        }
    }

    // MARK: - Frame decoders

    private func decodeThreadStarted(_ json: [String: Any]) -> [IterationEvent] {
        guard let threadId = json["thread_id"] as? String else { return [] }
        return [.sessionStarted(sessionId: threadId)]
    }

    private func decodeItemStarted(_ json: [String: Any]) -> [IterationEvent] {
        guard let item = json["item"] as? [String: Any],
              let itemType = item["type"] as? String else { return [] }

        switch itemType {
        case "command_execution":
            let command = item["command"] as? String ?? ""
            return [.toolUse(name: "bash", inputSummary: String(command.prefix(140)))]
        case "file_change":
            return [.toolUse(name: "Edit", inputSummary: fileChangeSummary(from: item))]
        default:
            return []
        }
    }

    private func decodeItemCompleted(_ json: [String: Any]) -> [IterationEvent] {
        guard let item = json["item"] as? [String: Any],
              let itemType = item["type"] as? String else { return [] }

        switch itemType {
        case "agent_message":
            let text = item["text"] as? String ?? ""
            lastAgentMessageText = text
            return [.assistantText(text)]
        case "command_execution":
            let output = item["aggregated_output"] as? String ?? ""
            let exitCode = item["exit_code"] as? Int ?? 0
            let status = item["status"] as? String ?? ""
            let failed = exitCode != 0 || status == "failed"
            let summary = String(output.replacingOccurrences(of: "\n", with: " ").prefix(200))
            return [.toolResult(summary: summary, failed: failed)]
        case "file_change":
            return [.toolResult(summary: "ok", failed: false)]
        default:
            return []
        }
    }

    // MARK: - Helpers

    private func fileChangeSummary(from item: [String: Any]) -> String {
        guard let changes = item["changes"] as? [[String: Any]],
              let first = changes.first,
              let kind = first["kind"] as? String,
              let path = first["path"] as? String else { return "" }
        return String("\(kind) \(path)".prefix(140))
    }
}
