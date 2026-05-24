import Foundation

/// Parses one line of OpenCode JSONL stdout into zero or more `IterationEvent`s.
/// Malformed JSON lines increment `malformedCount`; unknown event types and
/// frames with missing optional fields are silently dropped.
final class OpenCodeEventDecoder {

    private(set) var malformedCount: Int = 0

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
        case "step_start":
            guard let sessionId = sessionID(from: json) else { return [] }
            return [.sessionStarted(sessionId: sessionId)]
        case "text":
            guard let text = textValue(from: json) else { return [] }
            return [.assistantText(text)]
        case "tool_use":
            return decodeToolUse(json)
        case "step_finish":
            guard reason(from: json) == "stop" else { return [] }
            return [.iterationFinished(result: iterationResult(from: json))]
        case "error":
            return [.iterationFinished(result: errorMessage(from: json))]
        default:
            return []
        }
    }

    // MARK: - Frame decoders

    private func decodeToolUse(_ json: [String: Any]) -> [IterationEvent] {
        let status = toolStatus(from: json)
        // OpenCode emits a single frame per tool call with the final status
        // (no separate "running" frame), so emit both events for completed calls.
        if status == "completed" || status == "failed" || status == "error" {
            return [
                .toolUse(
                    name: toolName(from: json),
                    inputSummary: inputSummary(from: toolInput(from: json))
                ),
                .toolResult(
                    summary: toolResultSummary(from: json),
                    failed: status == "failed" || status == "error"
                )
            ]
        }
        if status == "running" {
            return [.toolUse(
                name: toolName(from: json),
                inputSummary: inputSummary(from: toolInput(from: json))
            )]
        }
        return []
    }

    // MARK: - Helpers

    private func sessionID(from json: [String: Any]) -> String? {
        if let id = stringField("session_id", in: json) {
            return id
        }
        return stringField("sessionID", in: json)
    }

    private func textValue(from json: [String: Any]) -> String? {
        if let text = json["text"] as? String {
            return text
        }
        if let part = part(from: json),
           let text = part["text"] as? String {
            return text
        }
        if let message = json["message"] as? [String: Any],
           let text = message["text"] as? String {
            return text
        }
        return nil
    }

    private func toolStatus(from json: [String: Any]) -> String {
        if let state = json["state"] as? [String: Any],
           let status = state["status"] as? String {
            return status
        }
        if let state = toolState(from: json),
           let status = state["status"] as? String {
            return status
        }
        return json["status"] as? String ?? ""
    }

    private func toolName(from json: [String: Any]) -> String {
        if let name = json["name"] as? String, !name.isEmpty {
            return name
        }
        if let name = json["tool"] as? String, !name.isEmpty {
            return name
        }
        if let part = part(from: json) {
            if let name = part["name"] as? String, !name.isEmpty {
                return name
            }
            if let name = part["tool"] as? String, !name.isEmpty {
                return name
            }
        }
        return "tool"
    }

    private func toolInput(from json: [String: Any]) -> Any? {
        if let input = json["input"] {
            return input
        }
        return toolState(from: json)?["input"]
    }

    private func inputSummary(from input: Any?) -> String {
        guard let input else { return "" }
        if let text = input as? String {
            return String(text.prefix(140))
        }
        guard JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return String(str.prefix(140))
    }

    private func toolResultSummary(from json: [String: Any]) -> String {
        if let output = json["output"] {
            return summarize(output)
        }
        if let result = json["result"] {
            return summarize(result)
        }
        if let state = toolState(from: json) {
            if let output = state["output"] {
                return summarize(output)
            }
            if let error = state["error"] {
                return summarize(error)
            }
            if let result = state["result"] {
                return summarize(result)
            }
        }
        return ""
    }

    private func summarize(_ value: Any) -> String {
        let raw: String
        if let text = value as? String {
            raw = text
        } else if JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let text = String(data: data, encoding: .utf8) {
            raw = text
        } else {
            return ""
        }
        return String(raw.replacingOccurrences(of: "\n", with: " ").prefix(200))
    }

    private func reason(from json: [String: Any]) -> String {
        if let reason = json["reason"] as? String {
            return reason
        }
        if let part = part(from: json),
           let reason = part["reason"] as? String {
            return reason
        }
        if let state = json["state"] as? [String: Any],
           let reason = state["reason"] as? String {
            return reason
        }
        return ""
    }

    private func iterationResult(from json: [String: Any]) -> String {
        if let result = json["result"] as? String {
            return result
        }
        if let part = part(from: json),
           let result = part["result"] as? String {
            return result
        }
        if let state = json["state"] as? [String: Any],
           let result = state["result"] as? String {
            return result
        }
        return ""
    }

    private func errorMessage(from json: [String: Any]) -> String {
        if let message = json["message"] as? String {
            return message
        }
        if let error = json["error"] as? String {
            return error
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return ""
    }

    private func stringField(_ key: String, in json: [String: Any]) -> String? {
        if let direct = json[key] as? String, !direct.isEmpty {
            return direct
        }
        if let nested = json["session"] as? [String: Any],
           let value = nested[key] as? String,
           !value.isEmpty {
            return value
        }
        if let nested = json["step"] as? [String: Any],
           let value = nested[key] as? String,
           !value.isEmpty {
            return value
        }
        if let nested = part(from: json),
           let value = nested[key] as? String,
           !value.isEmpty {
            return value
        }
        return nil
    }

    private func part(from json: [String: Any]) -> [String: Any]? {
        json["part"] as? [String: Any]
    }

    private func toolState(from json: [String: Any]) -> [String: Any]? {
        if let state = json["state"] as? [String: Any] {
            return state
        }
        return part(from: json)?["state"] as? [String: Any]
    }
}
