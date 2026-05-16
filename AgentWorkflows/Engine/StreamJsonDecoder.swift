import Foundation

/// One event parsed from a single stream-json frame emitted by
/// `claude -p --output-format stream-json --verbose`.
enum IterationEvent: Equatable {
    case sessionStarted(sessionId: String)
    case modelIdentified(provider: String, model: String)
    case assistantText(String)
    case toolUse(name: String, inputSummary: String)
    case toolResult(summary: String, failed: Bool)
    case iterationFinished(result: String)
}

/// Parses one line of `claude -p --output-format stream-json --verbose` stdout
/// into zero or more `IterationEvent`s. Malformed JSON (any line that cannot be
/// decoded as a JSON object) increments `malformedCount`; unknown frame types
/// and frames with missing optional fields are silently dropped.
final class StreamJsonDecoder {

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
        case "system":   return decodeSystem(json)
        case "assistant": return decodeAssistant(json)
        case "user":     return decodeUser(json)
        case "result":   return decodeResult(json)
        default:         return []
        }
    }

    // MARK: - Frame decoders

    private func decodeSystem(_ json: [String: Any]) -> [IterationEvent] {
        guard let subtype = json["subtype"] as? String, subtype == "init",
              let sessionId = json["session_id"] as? String else { return [] }
        return [.sessionStarted(sessionId: sessionId)]
    }

    private func decodeAssistant(_ json: [String: Any]) -> [IterationEvent] {
        guard let message = json["message"] as? [String: Any],
              let items = message["content"] as? [[String: Any]] else { return [] }
        return items.compactMap { decodeAssistantItem($0) }
    }

    private func decodeAssistantItem(_ item: [String: Any]) -> IterationEvent? {
        guard let itemType = item["type"] as? String else { return nil }
        switch itemType {
        case "text":
            guard let text = item["text"] as? String else { return nil }
            return .assistantText(text)
        case "tool_use":
            guard let name = item["name"] as? String else { return nil }
            return .toolUse(name: name, inputSummary: inputSummary(from: item["input"]))
        default:
            return nil
        }
    }

    private func decodeUser(_ json: [String: Any]) -> [IterationEvent] {
        guard let message = json["message"] as? [String: Any],
              let items = message["content"] as? [[String: Any]] else { return [] }
        return items.compactMap { decodeUserItem($0) }
    }

    private func decodeUserItem(_ item: [String: Any]) -> IterationEvent? {
        guard let itemType = item["type"] as? String, itemType == "tool_result" else { return nil }
        return .toolResult(summary: toolResultSummary(from: item["content"]), failed: false)
    }

    private func decodeResult(_ json: [String: Any]) -> [IterationEvent] {
        let result = json["result"] as? String ?? ""
        return [.iterationFinished(result: result)]
    }

    // MARK: - Helpers

    private func inputSummary(from input: Any?) -> String {
        guard let input = input,
              JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return String(str.prefix(140))
    }

    private func toolResultSummary(from content: Any?) -> String {
        let raw: String
        if let str = content as? String {
            raw = str
        } else if let arr = content as? [[String: Any]] {
            raw = arr.compactMap { $0["text"] as? String }.joined(separator: " ")
        } else {
            return ""
        }
        return String(raw.replacingOccurrences(of: "\n", with: " ").prefix(200))
    }
}
