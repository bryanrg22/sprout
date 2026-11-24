#if DEBUG
import Foundation

/// The built-in model scripts a UI smoke flow can select with
/// `--ui-test-scripted-ai=<name>`. Each answers in Anthropic's wire format, the
/// vocabulary the AI layer speaks internally, so the real client parses the reply.
///
/// Only the coach's turn is scripted. Every other model call a screen makes on its own
/// (the daily brief, the checklist, the quick prompts, the progress recap) is refused
/// with a 400, so those features show their template fallback and a flow sees the same
/// screen on every run.
enum UITestAIScript: String, CaseIterable, Sendable {
    /// The coach's first reply to a message is a `log_water` tool call for two
    /// containers; the follow-up (after the tool result) is a short prose reply.
    case coachLogWater = "coach-log-water"
    /// The coach replies in plain prose.
    case coachProse = "coach-prose"
    /// As `coach-prose`, but the reply takes a few seconds, so a flow can leave the app
    /// in the middle of a turn.
    case coachSlow = "coach-slow"
    /// The provider is down: every call gets HTTP 500.
    case fail500 = "fail-500"

    /// Stands in for a key so `AIConfig.hasActiveKey` is true. Never sent anywhere.
    static let placeholderKey = "ui-test-scripted-key-not-real"

    static let proseReply = "Scripted reply: you are doing fine today."
    static let afterToolReply = "Scripted reply: logged it."
    static let waterContainers = 2
    static let slowReplySeconds = 4.0

    struct Reply: Equatable, Sendable {
        var status: Int
        var json: Data
        var delaySeconds: Double = 0
    }

    /// The reply to one request body. Pure, so the scripts are unit-tested without a
    /// transport.
    func reply(to body: [String: Any]) -> Reply {
        if self == .fail500 {
            return Self.error(500, "api_error", "Scripted outage (fail-500).")
        }
        guard Self.isCoachTurn(body) else {
            return Self.error(400, "invalid_request_error", "No scripted reply for this call.")
        }
        let model = body["model"] as? String ?? "scripted"
        switch self {
        case .coachLogWater:
            if Self.endsWithToolResult(body) {
                return Self.message(model: model, content: [["type": "text", "text": Self.afterToolReply]],
                                    stopReason: "end_turn")
            }
            return Self.message(model: model, content: [[
                "type": "tool_use", "id": "toolu_uitest_log_water", "name": "log_water",
                "input": ["containers": Self.waterContainers],
            ]], stopReason: "tool_use")
        case .coachProse, .fail500:
            return Self.message(model: model, content: [["type": "text", "text": Self.proseReply]],
                                stopReason: "end_turn")
        case .coachSlow:
            var reply = Self.message(model: model, content: [["type": "text", "text": Self.proseReply]],
                                     stopReason: "end_turn")
            reply.delaySeconds = Self.slowReplySeconds
            return reply
        }
    }

    /// A coach turn is the one call that offers the coach's tools without forcing one.
    static func isCoachTurn(_ body: [String: Any]) -> Bool {
        guard let tools = body["tools"] as? [[String: Any]],
              tools.contains(where: { ($0["name"] as? String) == "log_water" }) else { return false }
        let choice = (body["tool_choice"] as? [String: Any])?["type"] as? String
        return choice == nil || choice == "auto" || choice == "none"
    }

    /// True when the last message carries a `tool_result`: the follow-up half of a tool turn.
    static func endsWithToolResult(_ body: [String: Any]) -> Bool {
        guard let last = (body["messages"] as? [[String: Any]])?.last,
              let blocks = last["content"] as? [[String: Any]] else { return false }
        return blocks.contains { ($0["type"] as? String) == "tool_result" }
    }

    private static func message(model: String, content: [[String: Any]], stopReason: String) -> Reply {
        encode(200, [
            "id": "msg_uitest", "type": "message", "role": "assistant", "model": model,
            "content": content, "stop_reason": stopReason,
            "usage": ["input_tokens": 0, "output_tokens": 0],
        ])
    }

    private static func error(_ status: Int, _ type: String, _ message: String) -> Reply {
        encode(status, ["type": "error", "error": ["type": type, "message": message]])
    }

    private static func encode(_ status: Int, _ object: [String: Any]) -> Reply {
        Reply(status: status, json: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }
}

/// Answers every model call from one `UITestAIScript`. No network.
struct UITestScriptedTransport: AITransport {
    let script: UITestAIScript

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let body = request.httpBody
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
        let reply = script.reply(to: body)
        if reply.delaySeconds > 0 {
            try? await Task.sleep(for: .seconds(reply.delaySeconds))
        }
        let response = HTTPURLResponse(url: request.url ?? URL(string: "https://scripted.invalid")!,
                                       statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: nil)!
        return (reply.json, response)
    }
}

/// The transport of a `--ui-testing` launch that named no script. Nothing should reach
/// it (the runtime it rides on has an empty key, so the clients refuse to be built); if
/// something does, it fails instead of touching the network.
struct UITestOfflineTransport: AITransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}
#endif
