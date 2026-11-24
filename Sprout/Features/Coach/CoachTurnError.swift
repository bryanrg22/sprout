import Foundation

/// Why a coach turn did not produce a reply, as far as the app can tell.
///
/// Each case has one message the user reads and one thing they can do about it. The
/// mapping from what the clients throw (`AIConfig.AIError`, `URLError`, a cancelled task)
/// and from a provider's error response (`AIHTTPFailure`) is `classify`, a pure function.
/// The sources for the provider side are in `docs/chat-standards.md`, section 4.
enum CoachTurnError: Equatable {
    /// The device has no connection (or cellular data is not allowed for the app).
    case offline
    /// A connection was opened and then lost, or the host could not be reached.
    case connectionLost
    /// The request ran out of time (the client's 60 s, or a 408 / 504 from the provider).
    case timeout
    /// The built-in AI does not work on this device (no App Attest, or no gateway address),
    /// so no request can be made.
    case missingKey
    /// The provider rejected the key (401) or the key may not do this (403). The key is the
    /// owner's, on the gateway: nothing the person can fix.
    case auth
    /// The model the app asks for does not exist for the owner's key (404).
    case modelUnavailable
    /// The owner's account is out of credit or over a spend limit.
    case billing
    /// Too many requests (429). `retryAfter` is what the provider asked for, when it said.
    case rateLimited(retryAfter: TimeInterval?)
    /// The built-in AI's allowance for today is used up (the gateway's `daily_limit`, or its
    /// `service_limit` for everyone). It comes back at midnight UTC; retrying sooner cannot work.
    case dailyLimit
    /// The provider is overloaded (529, 503).
    case overloaded
    /// The provider failed on its side (any other 5xx).
    case server
    /// The request was larger than the model accepts (413, or a context-length 400).
    case tooLong
    /// The output cap ended the reply before it was finished.
    case cutOff
    /// The model declined and said nothing the app can show.
    case refusal
    /// The user tapped Stop.
    case cancelled
    /// The newest message is the user's and nothing is in flight: the app was closed or
    /// suspended before the reply arrived.
    case interrupted
    /// A 2xx whose body the client could not read.
    case malformed
    /// Anything else.
    case unknown

    /// What the user can do about it.
    enum Action: Equatable {
        /// Send the same message again.
        case retry
        /// Send it again, but not before the provider's wait has passed.
        case retryAfter(TimeInterval)
        /// Nothing to tap: the message itself has to change.
        case rephrase
        /// Nothing to tap: it works again tomorrow.
        case waitForTomorrow
        /// Nothing to tap: the built-in AI does not work on this device.
        case unavailable
    }

    var action: Action {
        switch self {
        case .missingKey:
            return .unavailable
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter >= 1 { return .retryAfter(retryAfter) }
            return .retry
        case .tooLong, .refusal:
            return .rephrase
        case .dailyLimit:
            return .waitForTomorrow
        // The owner's key, model or account: fixed on the gateway, so trying later can work.
        case .auth, .modelUnavailable, .billing,
             .offline, .connectionLost, .timeout, .overloaded, .server, .cutOff, .cancelled,
             .interrupted, .malformed, .unknown:
            return .retry
        }
    }

    /// Whether sending the same message again can succeed.
    var canRetry: Bool {
        switch action {
        case .retry, .retryAfter: return true
        case .rephrase, .waitForTomorrow, .unavailable: return false
        }
    }

    /// A short name for the field log. Never shown to the user.
    var logName: String {
        switch self {
        case .offline: return "offline"
        case .connectionLost: return "connection-lost"
        case .timeout: return "timeout"
        case .missingKey: return "missing-key"
        case .auth: return "auth"
        case .modelUnavailable: return "model-unavailable"
        case .billing: return "billing"
        case .rateLimited: return "rate-limited"
        case .dailyLimit: return "daily-limit"
        case .overloaded: return "overloaded"
        case .server: return "server"
        case .tooLong: return "too-long"
        case .cutOff: return "cut-off"
        case .refusal: return "refusal"
        case .cancelled: return "cancelled"
        case .interrupted: return "interrupted"
        case .malformed: return "malformed"
        case .unknown: return "unknown"
        }
    }

    // MARK: - Classification

    /// What went wrong, from the thrown error and (when the provider answered with an error
    /// response) what that response said. Never reads the clock, the network or a key.
    static func classify(_ error: Error, http: AIHTTPFailure? = nil) -> CoachTurnError {
        if error is CancellationError { return .cancelled }
        if case AIConfig.AIError.missingKey = error { return .missingKey }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return .cancelled
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            case .timedOut:
                return .timeout
            case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .secureConnectionFailed:
                return .connectionLost
            default:
                return .unknown
            }
        }

        if let http { return classify(http) }
        if case AIConfig.AIError.decoding = error { return .malformed }
        return .unknown
    }

    /// A provider's error response → the taxonomy. Billing is checked before the status,
    /// because both providers report an empty account under a status that otherwise means
    /// something retryable (OpenAI: 429 `insufficient_quota`; Anthropic: 400 naming the
    /// credit balance).
    static func classify(_ http: AIHTTPFailure) -> CoachTurnError {
        // The built-in gateway's own allowance, before the generic 429.
        if http.type == "daily_limit" || http.type == "service_limit" { return .dailyLimit }
        if http.isBillingProblem { return .billing }
        if isContextOverflow(http) { return .tooLong }
        switch http.status {
        case 401, 403: return .auth
        case 404: return .modelUnavailable
        case 408, 504: return .timeout
        case 413: return .tooLong
        case 429: return .rateLimited(retryAfter: http.retryAfter)
        case 503, 529: return .overloaded
        case 500...599: return http.type == "overloaded_error" ? .overloaded : .server
        default: return .unknown
        }
    }

    /// A 400 that says the conversation is too large for the model. OpenAI names it in
    /// `error.code`; Anthropic says it in the message of an `invalid_request_error`.
    private static func isContextOverflow(_ http: AIHTTPFailure) -> Bool {
        guard http.status == 400 else { return false }
        if http.code == "context_length_exceeded" { return true }
        let message = http.message.lowercased()
        return message.contains("prompt is too long")
            || message.contains("context window")
            || message.contains("maximum context length")
    }

    // MARK: - What the user reads

    /// One or two friendly sentences in the coach's voice. `provider` is the vendor the
    /// turn was sent to. Nothing here asks the person to fix a key, a model or an account:
    /// those are the owner's, on the gateway.
    func message(provider: AIProvider) -> String {
        let name = provider.label
        switch self {
        case .offline:
            return "I can't reach the internet right now — mind checking your connection? 💚"
        case .connectionLost:
            return "The connection dropped before I could answer. Your message is saved."
        case .timeout:
            return "That took too long to come back. Your message is saved, so we can just try again."
        case .missingKey:
            return "I can't chat on this phone, sorry. Everything you log still works 💚"
        case .auth:
            return "\(name) turned my request away. That's on our side, not yours, so try again in a little while."
        case .modelUnavailable:
            return "\(name) isn't offering the model I use right now. That's on our side, not yours, so try again in a little while."
        case .billing:
            return "My \(name) account is paused right now. That's on our side, not yours, so try again in a little while."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter >= 1 {
                return "\(name) asked us to slow down. It should be clear in about \(Self.waitText(retryAfter))."
            }
            return "\(name) asked us to slow down for a moment."
        case .dailyLimit:
            return "That's all the AI for today. I'll be back tomorrow, and everything you log still counts 💚"
        case .overloaded:
            return "\(name) is overloaded right now. It usually clears within a minute."
        case .server:
            return "\(name) had a problem on its side. Nothing was lost."
        case .tooLong:
            return "That's more than I can take in at once. A shorter message or a smaller photo should get through."
        case .cutOff:
            return "My reply got cut off before I finished."
        case .refusal:
            return "I can't help with that one. Try asking it another way?"
        case .cancelled:
            return "Stopped. Your message is still here."
        case .interrupted:
            return "I didn't get to answer this one."
        case .malformed:
            return "I got a reply I couldn't read. Let's try that again."
        case .unknown:
            return "Something went wrong on my end. Let's try that again in a moment 💚"
        }
    }

    /// "12 seconds", "1 minute", "3 minutes": a wait, rounded up to a whole unit.
    static func waitText(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        if whole < 60 { return whole == 1 ? "1 second" : "\(whole) seconds" }
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
