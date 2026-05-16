import Foundation

/// Parses one line of Pi JSONL stdout into zero or more `IterationEvent`s.
/// Malformed JSON lines increment `malformedCount`; unknown event types and
/// frames with missing optional fields are silently dropped.
final class PiEventDecoder {

    private(set) var malformedCount: Int = 0
    private var emittedModelIdentity = false

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
        case "message_start":
            return decodeMessageStart(json)
        case "message_update":
            return decodeMessageUpdate(json)
        case "tool_execution_start":
            return [.toolUse(
                name: toolName(from: json),
                inputSummary: inputSummary(from: json["input"])
            )]
        case "tool_execution_end":
            return [.toolResult(
                summary: toolResultSummary(from: json),
                failed: toolExecutionFailed(from: json)
            )]
        case "agent_end":
            return [.iterationFinished(result: json["result"] as? String ?? "")]
        default:
            return []
        }
    }

    // MARK: - Frame decoders

    private func decodeMessageStart(_ json: [String: Any]) -> [IterationEvent] {
        guard !emittedModelIdentity else { return [] }
        guard let provider = stringField("provider", in: json),
              let model = stringField("model", in: json) else { return [] }
        emittedModelIdentity = true
        return [.modelIdentified(provider: provider, model: model)]
    }

    private func decodeMessageUpdate(_ json: [String: Any]) -> [IterationEvent] {
        guard let event = json["assistantMessageEvent"] as? [String: Any],
              let subtype = event["type"] as? String,
              subtype == "text_delta",
              let delta = event["delta"] as? String else { return [] }
        return [.assistantText(delta)]
    }

    // MARK: - Helpers

    /// Resolve a string field from top-level first, then from the nested
    /// `message` object used in Pi frames.
    private func stringField(_ key: String, in json: [String: Any]) -> String? {
        if let direct = json[key] as? String {
            return direct
        }
        if let message = json["message"] as? [String: Any],
           let nested = message[key] as? String {
            return nested
        }
        return nil
    }

    private func toolName(from json: [String: Any]) -> String {
        if let name = json["tool"] as? String, !name.isEmpty {
            return name
        }
        if let name = json["name"] as? String, !name.isEmpty {
            return name
        }
        if let toolExecution = json["toolExecution"] as? [String: Any],
           let name = toolExecution["name"] as? String,
           !name.isEmpty {
            return name
        }
        return "tool"
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
        if let output = json["output"] as? String {
            return truncateToolSummary(output)
        }
        if let result = json["result"] as? String {
            return truncateToolSummary(result)
        }
        if let toolExecution = json["toolExecution"] as? [String: Any] {
            if let output = toolExecution["output"] as? String {
                return truncateToolSummary(output)
            }
            if let result = toolExecution["result"] as? String {
                return truncateToolSummary(result)
            }
        }
        return ""
    }

    private func truncateToolSummary(_ value: String) -> String {
        String(value.replacingOccurrences(of: "\n", with: " ").prefix(200))
    }

    private func toolExecutionFailed(from json: [String: Any]) -> Bool {
        if let isError = json["isError"] as? Bool {
            return isError
        }
        if let success = json["success"] as? Bool {
            return success == false
        }
        if let status = json["status"] as? String {
            return status == "error" || status == "failed"
        }
        if let toolExecution = json["toolExecution"] as? [String: Any] {
            if let isError = toolExecution["isError"] as? Bool {
                return isError
            }
            if let success = toolExecution["success"] as? Bool {
                return success == false
            }
            if let status = toolExecution["status"] as? String {
                return status == "error" || status == "failed"
            }
        }
        return false
    }
}
