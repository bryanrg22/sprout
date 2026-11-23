import Foundation

/// What a provider's error response said: the status, the provider's own error type and
/// code, its message, and how long it asked the caller to wait.
///
/// The clients keep throwing `AIConfig.AIError.badResponse(message)`, which carries only
/// the message. A caller that has to tell a rejected key from a rate limit from an
/// overloaded service scopes an `AIFailureRecorder` around the call and reads this.
struct AIHTTPFailure: Sendable, Equatable {
    var provider: AIProvider
    var status: Int
    /// `error.type` in the body: `rate_limit_error`, `overloaded_error`, `insufficient_quota`, …
    var type: String?
    /// `error.code` in the body (OpenAI): `context_length_exceeded`, `invalid_api_key`, …
    var code: String?
    var message: String
    /// Seconds the provider asked the caller to wait (`retry-after` / `retry-after-ms`).
    var retryAfter: TimeInterval?
    /// The provider's id for the request (`request-id` / `x-request-id`), for a support query.
    var requestID: String?

    /// Reads the failure out of an error response. `json` is the decoded body, `[:]` when
    /// the body was not JSON.
    init(provider: AIProvider, response: HTTPURLResponse, json: [String: Any]) {
        let error = json["error"] as? [String: Any]
        self.provider = provider
        status = response.statusCode
        type = error?["type"] as? String
        code = error?["code"] as? String
        message = (error?["message"] as? String) ?? "HTTP \(response.statusCode)"
        retryAfter = Self.retryAfter(
            seconds: response.value(forHTTPHeaderField: "retry-after"),
            milliseconds: response.value(forHTTPHeaderField: "retry-after-ms"))
        requestID = response.value(forHTTPHeaderField: "request-id")
            ?? response.value(forHTTPHeaderField: "x-request-id")
            ?? (json["request_id"] as? String)
    }

    init(provider: AIProvider, status: Int, type: String? = nil, code: String? = nil,
         message: String = "", retryAfter: TimeInterval? = nil, requestID: String? = nil) {
        self.provider = provider
        self.status = status
        self.type = type
        self.code = code
        self.message = message
        self.retryAfter = retryAfter
        self.requestID = requestID
    }

    /// The wait a provider asked for. `retry-after-ms` (OpenAI) wins when both are present;
    /// `retry-after` is read as seconds. The HTTP-date form of `retry-after` is not read
    /// (neither provider sends it) and yields nil, as does a negative or unparseable value.
    static func retryAfter(seconds: String?, milliseconds: String?) -> TimeInterval? {
        if let raw = milliseconds?.trimmingCharacters(in: .whitespaces), let ms = Double(raw), ms >= 0 {
            return ms / 1000
        }
        if let raw = seconds?.trimmingCharacters(in: .whitespaces), let s = Double(raw), s >= 0 {
            return s
        }
        return nil
    }

    /// Whether the account, not the moment, is the problem: out of credit or over a spend
    /// limit. Waiting does not help, so this is never retried.
    var isBillingProblem: Bool {
        if status == 402 { return true }
        let markers = ["insufficient_quota", "billing", "credit_balance", "spend_limit", "usage_limit"]
        let fields = [type, code].compactMap { $0?.lowercased() }
        if fields.contains(where: { field in markers.contains { field.contains($0) } }) { return true }
        // Anthropic reports an empty balance as a 400 `invalid_request_error` whose message
        // names the credit balance.
        return status == 400 && message.lowercased().contains("credit balance")
    }

    /// The longest wait a client sits out itself before its one automatic retry. A longer
    /// `retry-after` is handed to the caller instead, so the user is told how long.
    static let longestAutomaticWait: TimeInterval = 5

    /// How long a client waits before its one automatic retry of this failure, or nil when
    /// it should not retry at all. With no `retry-after` this is the short fixed back-off
    /// the clients have always used.
    func automaticRetryDelay(retryableStatuses: Set<Int>, fallback: TimeInterval = 0.7) -> TimeInterval? {
        guard retryableStatuses.contains(status), !isBillingProblem else { return nil }
        guard let retryAfter else { return fallback }
        return retryAfter <= Self.longestAutomaticWait ? retryAfter : nil
    }
}

/// Collects the last provider error of the calls made inside one scope.
///
/// Task-local, like `AIRuntime`: `AIFailureRecorder.$current.withValue(recorder) { … }`
/// scopes it to exactly the calls inside the block, and with nothing scoped (every call
/// site but the coach) reporting is a no-op.
final class AIFailureRecorder: @unchecked Sendable {
    @TaskLocal static var current: AIFailureRecorder?

    private let lock = NSLock()
    private var value: AIHTTPFailure?

    /// The most recent failure reported inside the scope, nil when none was.
    var last: AIHTTPFailure? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func record(_ failure: AIHTTPFailure) {
        lock.lock(); defer { lock.unlock() }
        value = failure
    }

    /// Called by a client just before it throws for an error response.
    static func report(_ failure: AIHTTPFailure) {
        current?.record(failure)
    }
}
