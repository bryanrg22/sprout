import Foundation
import XCTest
@testable import Sprout

/// One model configuration under evaluation.
struct EvalCandidate: Hashable, Sendable {
    let provider: AIProvider
    let model: String
    /// OpenAI reasoning effort to force, or nil for the client's built-in choice.
    let effort: String?

    /// `anthropic:claude-haiku-4-5`, `openai:gpt-5.6-terra@medium`.
    var id: String { "\(provider.rawValue):\(model)" + (effort.map { "@\($0)" } ?? "") }

    static func parse(_ spec: String) -> EvalCandidate? {
        let trimmed = spec.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":"),
              let provider = AIProvider(rawValue: String(trimmed[..<colon])) else { return nil }
        var model = String(trimmed[trimmed.index(after: colon)...])
        var effort: String?
        if let at = model.lastIndex(of: "@") {
            effort = String(model[model.index(after: at)...])
            model = String(model[..<at])
        }
        return model.isEmpty ? nil : EvalCandidate(provider: provider, model: model, effort: effort)
    }
}

/// How a run is configured. Everything arrives through the environment
/// (`TEST_RUNNER_<NAME>` on the xcodebuild command line; see `Evals/run.sh`), so an
/// eval never runs, and never spends money, unless it was asked for by name.
enum EvalEnv {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Comma-separated candidate specs. Empty means "no live run".
    static var candidates: [EvalCandidate] {
        (env["SPROUT_EVAL_MODELS"] ?? "").split(separator: ",").compactMap { EvalCandidate.parse(String($0)) }
    }
    static var repeats: Int { max(1, Int(env["SPROUT_EVAL_REPEATS"] ?? "") ?? 1) }
    /// Run only the first N cases of each dataset (a pilot), or all of them.
    static var limit: Int? { Int(env["SPROUT_EVAL_LIMIT"] ?? "") }
    /// Run only the cases with these ids (comma-separated), for chasing one failure.
    static var onlyCases: Set<String> {
        Set((env["SPROUT_EVAL_CASES"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }
    static var concurrency: Int { max(1, Int(env["SPROUT_EVAL_CONCURRENCY"] ?? "") ?? 4) }
    /// The repository's `Evals/` directory on the host (the simulator reads host paths).
    static var root: URL? { env["SPROUT_EVAL_ROOT"].map { URL(fileURLWithPath: $0) } }
    /// Where this run's records are written.
    static var out: URL? { env["SPROUT_EVAL_OUT"].map { URL(fileURLWithPath: $0) } }

    /// A past run's directory whose saved characters are to be graded again (no model call).
    static var regradeRun: URL? {
        guard let path = env["SPROUT_EVAL_REGRADE"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Past runs whose recorded text is to be graded again (`Evals/regrade-text.sh`), separated by ":".
    static var regradeTextRuns: [URL] {
        (env["SPROUT_EVAL_REGRADE_TEXT"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
    }

    static func key(for provider: AIProvider) -> String? {
        let name = provider == .anthropic ? "ANTHROPIC_API_KEY" : "OPENAI_API_KEY"
        guard let value = env[name], !value.isEmpty else { return nil }
        return value
    }

    /// Skips the test unless a live run was fully configured.
    static func requireLive() throws {
        guard !candidates.isEmpty, root != nil, out != nil else {
            throw XCTSkip("live eval not requested (run through Evals/run.sh)")
        }
        for candidate in candidates where key(for: candidate.provider) == nil {
            throw XCTSkip("no key in the environment for \(candidate.provider.rawValue)")
        }
    }
}

/// A labelled dataset: one JSON object per line.
enum EvalDataset {
    static func load<T: Decodable>(_ relativePath: String, as type: T.Type) throws -> [T] {
        guard let root = EvalEnv.root else { throw XCTSkip("SPROUT_EVAL_ROOT not set") }
        return try decode(contentsOf: root.appendingPathComponent("datasets/\(relativePath)"), as: type)
    }

    static func decode<T: Decodable>(contentsOf url: URL, as type: T.Type) throws -> [T] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = try text.split(separator: "\n").map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("//") }
            .map { try JSONDecoder().decode(T.self, from: Data($0.utf8)) }
        if let limit = EvalEnv.limit { return Array(rows.prefix(limit)) }
        return rows
    }
}

/// One (case, candidate, repeat) result. Keys never appear here: a record holds the
/// case id, the candidate, the scores, the usage and the model's output, nothing else.
struct EvalRecord: Encodable {
    var task: String
    var dataset: String
    var caseID: String
    var candidate: String
    var provider: String
    var model: String
    var effort: String?
    var repeatIndex: Int
    /// The call returned something the app could parse.
    var ok: Bool
    var error: String?
    /// Named scores in 0...1 unless the name says otherwise (`*_pct_error`, `*_abs_error`).
    var scores: [String: Double]
    /// The task's own pass rule (documented beside its grader).
    var pass: Bool
    var latencyMs: Int
    var modelAnswered: String?
    var uncachedInputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int
    var outputTokens: Int
    /// Output tokens spent thinking, summed over the calls that reported it; nil when none did.
    var thinkingTokens: Int?
    /// The last call's stop reason in the provider's word, when it gave one.
    var stopReason: String?
    var calls: Int
    /// The parsed output, compact JSON or text, for reading failures by hand.
    var output: String
    /// What the app gave the model: the last user message of the attempt's first request, as
    /// the app built it (the data, not the system prompt). This is what a judge reads beside
    /// the output (`Evals/judge.py`). Nil for an attempt that sent no request.
    var given: String?
}

/// Appends records to `<out>/records-<task>.jsonl`, safely from concurrent cases.
final class EvalWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    private(set) var count = 0

    init(task: String) throws {
        guard let out = EvalEnv.out else { throw XCTSkip("SPROUT_EVAL_OUT not set") }
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let url = out.appendingPathComponent("records-\(task).jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    func append(_ record: EvalRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(record) else { return }
        data.append(0x0A)
        lock.lock(); defer { lock.unlock() }
        try? handle.write(contentsOf: data)
        count += 1
    }

    deinit { try? handle.close() }
}

/// What one graded attempt produced, before the harness adds usage and timing.
struct EvalOutcome {
    var ok: Bool
    var error: String?
    var scores: [String: Double]
    var pass: Bool
    var output: String

    static func failed(_ error: Error) -> EvalOutcome { failed(error, output: "") }

    /// A failure that still has the model's reply in hand (a reply the app could not decode).
    static func failed(_ error: Error, output: String) -> EvalOutcome {
        EvalOutcome(ok: false, error: String(describing: error).prefix(300).description,
                    scores: [:], pass: false, output: String(output.prefix(EvalRunner.outputLimit)))
    }

    /// The app showed its template or its fallback instead of the model's reply: the call
    /// failed (`raw` is nil), or the feature's own guardrail threw the reply away. Both
    /// count as "not used"; the record says which, and keeps the reply.
    static func notUsed(raw: String?, failure: String?, discardedBy guardrail: String) -> EvalOutcome {
        let error = raw == nil ? "the call failed" + (failure.map { ": \($0)" } ?? "")
                               : "\(guardrail) discarded the reply"
        return EvalOutcome(ok: false, error: String(error.prefix(300)), scores: ["used": 0], pass: false,
                           output: String((raw ?? "").prefix(EvalRunner.outputLimit)))
    }
}

/// A transport that hands every request to the one in force and keeps each response body.
/// This is how an evaluation calls the app's own function (which returns nil, or throws,
/// when its guardrail or its decoder rejects a reply) and still records what the model wrote.
final class ResponseRecorder: AITransport, @unchecked Sendable {
    private let inner: any AITransport
    private let lock = NSLock()
    private var bodies: [Data] = []

    init(around inner: any AITransport) { self.inner = inner }

    private var requests: [Data] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let body = request.httpBody { lock.withLock { requests.append(body) } }
        let (data, response) = try await inner.data(for: request)
        lock.withLock { bodies.append(data) }
        return (data, response)
    }

    var last: Data? { lock.withLock { bodies.last } }
    var firstRequest: Data? { lock.withLock { requests.first } }
}

/// What a recorded call produced: the app's own result, and the model's reply behind it.
struct Recorded<T> {
    let result: Result<T, Error>
    /// The model's reply in the last response (text, or the JSON of a tool call's input);
    /// nil when no response carried one.
    let raw: String?
    /// The provider's error message in the last response, if it was an error.
    let failure: String?

    var value: T? { try? result.get() }
}

enum EvalRunner {

    /// Runs `attempt` for every (case, candidate, repeat) under a scoped runtime that
    /// pins the provider, key and model, and records usage and wall-clock time.
    /// `attempt` calls the app's real code path; it must not catch-and-hide a failure.
    static func run<Case: Sendable>(task: AITask,
                                    dataset: String,
                                    cases: [Case],
                                    caseID: @escaping @Sendable (Case) -> String,
                                    attempt: @escaping @Sendable (Case) async -> EvalOutcome) async throws {
        try await run(taskName: task.rawValue, dataset: dataset, cases: cases, caseID: caseID, attempt: attempt)
    }

    /// The same, for a task that is not a text-model `AITask` (image generation). The
    /// candidate's `@effort` suffix reaches `attempt` as `AIRuntime.current?.reasoningEffort`.
    static func run<Case: Sendable>(taskName: String,
                                    dataset: String,
                                    cases: [Case],
                                    caseID: @escaping @Sendable (Case) -> String,
                                    attempt: @escaping @Sendable (Case) async -> EvalOutcome) async throws {
        try EvalEnv.requireLive()
        let only = EvalEnv.onlyCases
        let cases = only.isEmpty ? cases : cases.filter { only.contains(caseID($0)) }
        let writer = try EvalWriter(task: taskName)
        let repeats = EvalEnv.repeats

        var jobs: [(item: Case, candidate: EvalCandidate, repeatIndex: Int)] = []
        for candidate in EvalEnv.candidates {
            for item in cases {
                for repeatIndex in 0..<repeats { jobs.append((item, candidate, repeatIndex)) }
            }
        }

        var iterator = jobs.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            func addNext() {
                guard let job = iterator.next() else { return }
                group.addTask {
                    let usage = UsageRecorder()
                    // Every request of the attempt passes through this, so the record can say
                    // what the model was given; `recording` wraps it in turn.
                    let requests = ResponseRecorder(around: AIDefaultTransport())
                    let runtime = AIRuntime(provider: job.candidate.provider,
                                            apiKey: EvalEnv.key(for: job.candidate.provider),
                                            model: job.candidate.model,
                                            reasoningEffort: job.candidate.effort,
                                            transport: requests,
                                            onUsage: { usage.record($0) })
                    let started = Date()
                    let outcome = await AIRuntime.$current.withValue(runtime) { await attempt(job.item) }
                    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                    let calls = usage.all
                    writer.append(EvalRecord(
                        task: taskName, dataset: dataset, caseID: caseID(job.item),
                        candidate: job.candidate.id, provider: job.candidate.provider.rawValue,
                        model: job.candidate.model, effort: job.candidate.effort,
                        repeatIndex: job.repeatIndex, ok: outcome.ok, error: outcome.error,
                        scores: outcome.scores, pass: outcome.pass, latencyMs: elapsed,
                        modelAnswered: calls.last?.model,
                        uncachedInputTokens: calls.reduce(0) { $0 + $1.uncachedInputTokens },
                        cacheReadTokens: calls.reduce(0) { $0 + $1.cacheReadTokens },
                        cacheWriteTokens: calls.reduce(0) { $0 + $1.cacheWriteTokens },
                        outputTokens: calls.reduce(0) { $0 + $1.outputTokens },
                        thinkingTokens: calls.contains { $0.thinkingTokens != nil }
                            ? calls.reduce(0) { $0 + ($1.thinkingTokens ?? 0) } : nil,
                        stopReason: calls.last?.stopReason,
                        calls: calls.count, output: outcome.output,
                        given: requests.firstRequest.flatMap(givenText(inRequest:))
                            .map { String($0.prefix(givenLimit)) }))
                }
            }
            for _ in 0..<EvalEnv.concurrency { addNext() }
            while await group.next() != nil { addNext() }
        }
        XCTAssertEqual(writer.count, jobs.count, "every job must leave a record")
    }

    /// Longest reply kept in a record (the memory fold's two blocks can reach 2,500 characters).
    static let outputLimit = 4000
    /// Longest input kept in a record (a memory-fold batch of messages is the longest).
    static let givenLimit = 8000

    /// The last user message of a request body, whichever wire format it is in: Anthropic
    /// Messages and OpenAI Chat Completions (`messages`), OpenAI Responses (`input`). Text
    /// parts only; an image is shown as "[image]". Nil for a body that is not JSON (an image
    /// edit is multipart) or has no user message.
    static func givenText(inRequest body: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        let turns = (json["messages"] as? [[String: Any]]) ?? (json["input"] as? [[String: Any]]) ?? []
        guard let user = turns.last(where: { ($0["role"] as? String) == "user" }) else {
            return json["input"] as? String
        }
        if let text = user["content"] as? String { return text }
        let parts = ((user["content"] as? [[String: Any]]) ?? []).compactMap { block -> String? in
            switch block["type"] as? String {
            case "text", "input_text": return block["text"] as? String
            case "image", "input_image", "image_url": return "[image]"
            default: return nil
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// Runs `body`, which calls the app's real code path, with every provider response
    /// recorded. The runtime in force is kept as it is (provider, key, model, usage
    /// reporting); only its transport is wrapped.
    static func recording<T>(isolation: isolated (any Actor)? = #isolation,
                             _ body: () async throws -> T) async -> Recorded<T> {
        let recorder = ResponseRecorder(around: AIRuntime.transport)
        var runtime = AIRuntime.current ?? AIRuntime()
        runtime.transport = recorder
        let result: Result<T, Error>
        do {
            result = .success(try await AIRuntime.$current.withValue(runtime) { try await body() })
        } catch {
            result = .failure(error)
        }
        let reply = recorder.last.map(modelOutput(inResponse:))
        return Recorded(result: result, raw: reply?.text, failure: reply?.failure)
    }

    /// What the model wrote in one provider response, whichever wire format it is in:
    /// Anthropic Messages (`content` blocks), OpenAI Responses (`output` items) or OpenAI
    /// Chat Completions (`choices`). Text is returned as it is; a tool call is returned as
    /// the JSON of its input. `failure` is the provider's error message, if there is one.
    static func modelOutput(inResponse data: Data) -> (text: String?, failure: String?) {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (nil, nil) }
        let failure = (json["error"] as? [String: Any])?["message"] as? String
        var parts: [String] = []
        // Only what the app itself reads: a reasoning or thinking block is not the reply.
        for block in (json["content"] as? [[String: Any]]) ?? [] {                   // Anthropic
            switch block["type"] as? String {
            case "text": if let text = block["text"] as? String { parts.append(text) }
            case "tool_use": if let input = block["input"] as? [String: Any] { parts.append(compactJSON(input)) }
            default: break
            }
        }
        for item in (json["output"] as? [[String: Any]]) ?? [] {                     // OpenAI Responses
            switch item["type"] as? String {
            case "message":
                for block in (item["content"] as? [[String: Any]]) ?? [] where (block["type"] as? String) == "output_text" {
                    if let text = block["text"] as? String { parts.append(text) }
                }
            case "function_call": if let arguments = item["arguments"] as? String { parts.append(arguments) }
            default: break
            }
        }
        if let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any] {  // Chat Completions
            if let text = message["content"] as? String { parts.append(text) }
            for call in (message["tool_calls"] as? [[String: Any]]) ?? [] {
                if let arguments = (call["function"] as? [String: Any])?["arguments"] as? String { parts.append(arguments) }
            }
        }
        if parts.isEmpty, let text = json["output_text"] as? String { parts.append(text) }
        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (text.isEmpty ? nil : text, failure)
    }

    /// A reply that should be a JSON object (a tool call's input), or nil.
    static func jsonObject(_ text: String?) -> [String: Any]? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func compactJSON(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return String(describing: object)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
