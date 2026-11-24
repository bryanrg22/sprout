import Foundation

/// One HTTP exchange with a model provider.
///
/// Production uses `URLSession.shared`. Unit tests inject a scripted transport that
/// replays recorded provider responses (so the whole request-build → parse path runs
/// with no network), and the eval harness injects a recording transport around the
/// real one.
protocol AITransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionTransport: AITransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

/// Token accounting for one logical model call, normalized across providers.
///
/// The providers count differently: Anthropic's `input_tokens` EXCLUDES cached
/// tokens (cache reads and writes are reported beside it); OpenAI's `input_tokens`
/// / `prompt_tokens` INCLUDES the cached part. Here `uncachedInputTokens` is always
/// the part billed at the full input price, so one cost formula serves both.
struct AIUsage: Sendable, Equatable {
    var provider: AIProvider
    var model: String
    /// Path of the endpoint that answered (`/v1/messages`, `/v1/responses`, …).
    var endpoint: String
    var uncachedInputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int
    var outputTokens: Int
    /// Wall-clock milliseconds for the call, retries included.
    var latencyMs: Int
    /// HTTP attempts made (2 means the one transient-overload retry was used).
    var attempts: Int
    /// The part of `outputTokens` the model spent thinking before it wrote, when the
    /// provider reports it (Anthropic: `usage.output_tokens_details.thinking_tokens`).
    /// nil means "not reported", which is not the same as zero.
    var thinkingTokens: Int? = nil
    /// Why the model stopped, in the provider's own word (`end_turn`, `max_tokens`, …).
    var stopReason: String? = nil

    /// Every input token the request carried, cached or not.
    var totalInputTokens: Int { uncachedInputTokens + cacheReadTokens + cacheWriteTokens }
}

/// A scoped override of how the AI layer runs, for tests and evals.
///
/// Task-local on purpose: nothing global is mutated, so a test or an eval case can
/// pin a provider, key, model or transport for exactly the calls made inside
/// `AIRuntime.$current.withValue(...) { ... }` while the rest of the process (and
/// every other concurrently running case) is untouched. When `current` is nil, which
/// is always the case in the shipped app, behaviour is identical to having no seam.
///
/// A task-local value is inherited by child tasks and by `Task { }`, but NOT by
/// `Task.detached`; code under test must not hop through a detached task between
/// the override and the client call.
struct AIRuntime: Sendable {
    /// Which vendor `AIConfig.provider` reports (and so which client `AIClient` builds).
    var provider: AIProvider?
    /// Key used instead of the Keychain. Never logged, never written to a record.
    var apiKey: String?
    /// Model used for every call, overriding the task default and any call-site argument.
    var model: String?
    /// OpenAI reasoning effort used instead of the client's built-in choice.
    var reasoningEffort: String?
    /// Transport used instead of `URLSession.shared`.
    var transport: (any AITransport)?
    /// Called once per successful model call with its token usage.
    var onUsage: (@Sendable (AIUsage) -> Void)?

    @TaskLocal static var current: AIRuntime?

    /// A process-wide runtime, for the one case a task-local cannot cover: the UI smoke
    /// flows, where the app runs as its own process and every model call it makes (from
    /// any task, detached ones included) has to be answered by a scripted transport.
    ///
    /// It exists only in DEBUG builds. In a Release build there is no setter and the value
    /// is the constant `nil`, so the shipped app cannot be pointed at anything but the
    /// Keychain and `URLSession`. Set once at launch by `UITestHooks`, before any call.
    #if DEBUG
    private static let processDefaultStorage = ProcessDefaultStorage()
    static var processDefault: AIRuntime? { processDefaultStorage.get() }
    static func setProcessDefault(_ runtime: AIRuntime?) { processDefaultStorage.set(runtime) }

    private final class ProcessDefaultStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var value: AIRuntime?
        func get() -> AIRuntime? { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ runtime: AIRuntime?) { lock.lock(); defer { lock.unlock() }; value = runtime }
    }
    #else
    static var processDefault: AIRuntime? { nil }
    #endif

    /// The runtime in force for a call. Precedence: the task-local scope (tests, evals),
    /// then the process default (UI smoke flows, DEBUG only), then nothing, which is the
    /// shipped behaviour (Keychain key, the task's model, `URLSession`). The scope wins
    /// as a whole: a field it leaves nil is NOT filled in from the process default.
    static var effective: AIRuntime? { current ?? processDefault }

    /// The model a client should send: the scoped override when there is one.
    static func resolve(model: String) -> String {
        effective?.model ?? model
    }

    /// The scoped transport, or the app's own: straight to the provider, or to the built-in
    /// gateway for a request carrying its placeholder key (`AIDefaultTransport`).
    static var transport: any AITransport {
        effective?.transport ?? AIDefaultTransport()
    }

    static func report(_ usage: AIUsage) {
        effective?.onUsage?(usage)
    }
}
