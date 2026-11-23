import Foundation
import XCTest
@testable import Victoria

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
    static var concurrency: Int { max(1, Int(env["SPROUT_EVAL_CONCURRENCY"] ?? "") ?? 4) }
    /// The repository's `Evals/` directory on the host (the simulator reads host paths).
    static var root: URL? { env["SPROUT_EVAL_ROOT"].map { URL(fileURLWithPath: $0) } }
    /// Where this run's records are written.
    static var out: URL? { env["SPROUT_EVAL_OUT"].map { URL(fileURLWithPath: $0) } }

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
    var calls: Int
    /// The parsed output, compact JSON or text, for reading failures by hand.
    var output: String
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

    static func failed(_ error: Error) -> EvalOutcome {
        EvalOutcome(ok: false, error: String(describing: error).prefix(300).description,
                    scores: [:], pass: false, output: "")
    }
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
        try EvalEnv.requireLive()
        let writer = try EvalWriter(task: task.rawValue)
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
                    let runtime = AIRuntime(provider: job.candidate.provider,
                                            apiKey: EvalEnv.key(for: job.candidate.provider),
                                            model: job.candidate.model,
                                            reasoningEffort: job.candidate.effort,
                                            transport: nil,
                                            onUsage: { usage.record($0) })
                    let started = Date()
                    let outcome = await AIRuntime.$current.withValue(runtime) { await attempt(job.item) }
                    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                    let calls = usage.all
                    writer.append(EvalRecord(
                        task: task.rawValue, dataset: dataset, caseID: caseID(job.item),
                        candidate: job.candidate.id, provider: job.candidate.provider.rawValue,
                        model: job.candidate.model, effort: job.candidate.effort,
                        repeatIndex: job.repeatIndex, ok: outcome.ok, error: outcome.error,
                        scores: outcome.scores, pass: outcome.pass, latencyMs: elapsed,
                        modelAnswered: calls.last?.model,
                        uncachedInputTokens: calls.reduce(0) { $0 + $1.uncachedInputTokens },
                        cacheReadTokens: calls.reduce(0) { $0 + $1.cacheReadTokens },
                        cacheWriteTokens: calls.reduce(0) { $0 + $1.cacheWriteTokens },
                        outputTokens: calls.reduce(0) { $0 + $1.outputTokens },
                        calls: calls.count, output: outcome.output))
                }
            }
            for _ in 0..<EvalEnv.concurrency { addNext() }
            while await group.next() != nil { addNext() }
        }
        XCTAssertEqual(writer.count, jobs.count, "every job must leave a record")
    }

    static func compactJSON(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return String(describing: object)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
