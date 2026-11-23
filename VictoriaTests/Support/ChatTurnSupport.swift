import Foundation
import SwiftData
import XCTest
@testable import Victoria

// Support for tests that drive the coach's turn engine through the real provider clients.

/// Holds a scripted response back until the test opens it, so a test can look at the app's
/// state while a request is in flight.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        lock.lock()
        isOpen = true
        let resumed = waiters
        waiters = []
        lock.unlock()
        resumed.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

/// A transport that plays a script of provider responses and transport failures in order,
/// records every request, and can hold a step at a `Gate`. Unlike `ScriptedTransport` it can
/// throw a `URLError`, send response headers, and pause.
final class TurnTransport: AITransport, @unchecked Sendable {

    enum Step {
        /// An HTTP response with a JSON body.
        case reply(Int, [String: Any], headers: [String: String] = [:])
        /// The connection failing before any response (offline, timeout, …).
        case fail(URLError.Code)
        /// Wait at the gate, then behave as the wrapped step.
        indirect case held(Gate, Step)

        static func ok(_ json: [String: Any]) -> Step { .reply(200, json) }
    }

    enum Failure: Error { case scriptExhausted }

    private let lock = NSLock()
    private var queue: [Step]
    private var recorded: [URLRequest] = []

    init(_ steps: [Step]) { queue = steps }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    var requestCount: Int { requests.count }

    /// How many scripted steps were never asked for.
    var remaining: Int {
        lock.lock(); defer { lock.unlock() }
        return queue.count
    }

    /// The JSON body of the n-th request.
    func body(_ index: Int) -> [String: Any] {
        let all = requests
        guard index < all.count, let data = all[index].httpBody,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return object
    }

    /// The n-th request body as text, for "does it mention X anywhere" assertions.
    func bodyText(_ index: Int) -> String {
        let all = requests
        guard index < all.count, let data = all[index].httpBody else { return "" }
        // JSONSerialization writes "/" as "\/"; undo that so base64 and paths can be searched for.
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var step: Step = try {
            lock.lock(); defer { lock.unlock() }
            recorded.append(request)
            guard !queue.isEmpty else { throw Failure.scriptExhausted }
            return queue.removeFirst()
        }()
        while case .held(let gate, let inner) = step {
            await gate.wait()
            step = inner
        }
        switch step {
        case .reply(let status, let json, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: headers)!
            return (try JSONSerialization.data(withJSONObject: json), response)
        case .fail(let code):
            throw URLError(code)
        case .held:
            throw Failure.scriptExhausted   // unreachable: unwrapped above
        }
    }
}

/// One tool call as a test writes it; each wire format spells it differently.
struct ScriptedToolCall {
    var id: String
    var name: String
    var input: [String: Any]

    init(_ id: String, _ name: String, _ input: [String: Any]) {
        self.id = id
        self.name = name
        self.input = input
    }

    var argumentsJSON: String {
        // swiftlint:disable:next force_try
        String(decoding: try! JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]), as: UTF8.self)
    }
}

/// The three wire formats the coach's tool turn speaks: Anthropic Messages, OpenAI Chat
/// Completions and OpenAI Responses. A scenario written once against this type runs the
/// shipped request-build and parse code of each.
enum ChatWire: String, CaseIterable {
    case anthropic
    case openAIChat
    case openAIResponses

    var provider: AIProvider { self == .anthropic ? .anthropic : .openai }

    /// A model the provider's profile routes to this wire.
    var model: String {
        switch self {
        case .anthropic: return "claude-test"
        case .openAIChat: return "gpt-4.1"
        case .openAIResponses: return "gpt-5.6-terra"
        }
    }

    var path: String {
        switch self {
        case .anthropic: return "/v1/messages"
        case .openAIChat: return "/v1/chat/completions"
        case .openAIResponses: return "/v1/responses"
        }
    }

    func runtime(_ transport: any AITransport, key: String = "test-key-not-real") -> AIRuntime {
        AIRuntime(provider: provider, apiKey: key, model: model, transport: transport)
    }

    /// Why the model stopped, in the test's vocabulary.
    enum Stop { case end, tool, cutOff, refusal, contextOverflow }

    /// A successful (HTTP 200) model turn: optional prose, any number of tool calls.
    func turn(_ text: String? = nil, tools: [ScriptedToolCall] = [], stop: Stop? = nil,
              refusal: String? = nil) -> [String: Any] {
        let stop = stop ?? (tools.isEmpty ? .end : .tool)
        switch self {
        case .anthropic:
            var content: [[String: Any]] = []
            if let text { content.append(["type": "text", "text": text]) }
            for call in tools {
                content.append(["type": "tool_use", "id": call.id, "name": call.name, "input": call.input])
            }
            let reason: String
            switch stop {
            case .end: reason = "end_turn"
            case .tool: reason = "tool_use"
            case .cutOff: reason = "max_tokens"
            case .refusal: reason = "refusal"
            case .contextOverflow: reason = "model_context_window_exceeded"
            }
            return ["model": model, "role": "assistant", "content": content, "stop_reason": reason,
                    "usage": ["input_tokens": 100, "output_tokens": 20]]

        case .openAIChat:
            var message: [String: Any] = ["role": "assistant", "content": text ?? NSNull()]
            if !tools.isEmpty {
                message["tool_calls"] = tools.map {
                    ["id": $0.id, "type": "function",
                     "function": ["name": $0.name, "arguments": $0.argumentsJSON]] as [String: Any]
                }
            }
            if let refusal { message["refusal"] = refusal }
            let reason: String
            switch stop {
            case .end: reason = "stop"
            case .tool: reason = "tool_calls"
            case .cutOff: reason = "length"
            case .refusal: reason = refusal == nil ? "content_filter" : "stop"
            case .contextOverflow: reason = "length"
            }
            return ["model": model, "choices": [["index": 0, "finish_reason": reason, "message": message]],
                    "usage": ["prompt_tokens": 100, "completion_tokens": 20]]

        case .openAIResponses:
            var output: [[String: Any]] = []
            var parts: [[String: Any]] = []
            if let text { parts.append(["type": "output_text", "text": text]) }
            if let refusal { parts.append(["type": "refusal", "refusal": refusal]) }
            if !parts.isEmpty { output.append(["type": "message", "role": "assistant", "content": parts]) }
            for call in tools {
                output.append(["type": "function_call", "call_id": call.id, "name": call.name,
                               "arguments": call.argumentsJSON])
            }
            var json: [String: Any] = ["model": model, "status": "completed", "output": output,
                                       "usage": ["input_tokens": 100, "output_tokens": 20]]
            switch stop {
            case .cutOff, .contextOverflow:
                json["status"] = "incomplete"
                json["incomplete_details"] = ["reason": "max_output_tokens"]
            case .refusal where refusal == nil:
                json["status"] = "incomplete"
                json["incomplete_details"] = ["reason": "content_filter"]
            default:
                break
            }
            return json
        }
    }

    /// A provider error body, in the provider's shape.
    func errorBody(type: String, message: String, code: String? = nil) -> [String: Any] {
        switch self {
        case .anthropic:
            return ["type": "error", "error": ["type": type, "message": message], "request_id": "req_test_1"]
        case .openAIChat, .openAIResponses:
            var error: [String: Any] = ["type": type, "message": message]
            if let code { error["code"] = code }
            return ["error": error]
        }
    }

    // MARK: Reading a request the client built

    /// The messages (Messages / Chat Completions) or input items (Responses) of a request.
    func items(_ body: [String: Any]) -> [[String: Any]] {
        ((self == .openAIResponses ? body["input"] : body["messages"]) as? [[String: Any]]) ?? []
    }

    /// Whether the request forbids tool use (the depth cap).
    func forbidsTools(_ body: [String: Any]) -> Bool {
        if self == .anthropic { return (body["tool_choice"] as? [String: Any])?["type"] as? String == "none" }
        return body["tool_choice"] as? String == "none"
    }

    /// The tool results a request carries back to the model: `(call id, text, is_error)`.
    /// OpenAI has no error flag on a tool result, so `isError` is nil there.
    func toolResults(_ body: [String: Any]) -> [(id: String, text: String, isError: Bool?)] {
        switch self {
        case .anthropic:
            return items(body).flatMap { message -> [(String, String, Bool?)] in
                guard let blocks = message["content"] as? [[String: Any]] else { return [] }
                return blocks.filter { $0["type"] as? String == "tool_result" }.map {
                    ($0["tool_use_id"] as? String ?? "", $0["content"] as? String ?? "",
                     ($0["is_error"] as? Bool) ?? false)
                }
            }
        case .openAIChat:
            return items(body).filter { $0["role"] as? String == "tool" }.map {
                ($0["tool_call_id"] as? String ?? "", $0["content"] as? String ?? "", nil)
            }
        case .openAIResponses:
            return items(body).filter { $0["type"] as? String == "function_call_output" }.map {
                ($0["call_id"] as? String ?? "", $0["output"] as? String ?? "", nil)
            }
        }
    }

    /// The ids of the tool calls a request echoes back as the assistant's.
    func echoedToolCallIDs(_ body: [String: Any]) -> [String] {
        switch self {
        case .anthropic:
            return items(body).flatMap { message -> [String] in
                guard let blocks = message["content"] as? [[String: Any]] else { return [] }
                return blocks.filter { $0["type"] as? String == "tool_use" }.compactMap { $0["id"] as? String }
            }
        case .openAIChat:
            return items(body).flatMap { ($0["tool_calls"] as? [[String: Any]]) ?? [] }
                .compactMap { $0["id"] as? String }
        case .openAIResponses:
            return items(body).filter { $0["type"] as? String == "function_call" }
                .compactMap { $0["call_id"] as? String }
        }
    }
}

/// Records background-task begins and ends instead of calling UIKit.
@MainActor
final class RecordingBackgroundTasks: CoachBackgroundTasking {
    private(set) var begun: [Int] = []
    private(set) var ended: [Int] = []
    private var next = 1

    nonisolated init() {}

    func begin(_ name: String) -> Int {
        defer { next += 1 }
        begun.append(next)
        return next
    }

    func end(_ token: Int) { ended.append(token) }

    var isBalanced: Bool { begun.sorted() == ended.sorted() }
}

/// A clock that moves one second each time it is read, so every message a test creates has
/// a distinct, increasing `createdAt` without touching the wall clock.
@MainActor
final class TickingClock {
    private(set) var current: Date
    init(start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }

    func now() -> Date {
        current = current.addingTimeInterval(1)
        return current
    }
}
