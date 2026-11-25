import CryptoKit
import DeviceCheck
import Foundation

/// Built-in AI: the owner's gateway (`server/`) holds the API keys, so a person who installs
/// the app from TestFlight can use every AI feature without one.
///
/// How a call gets there: a client carries `placeholderKey` instead of a key
/// (`AIConfig.key(for:)`), and the default transport (`AIRuntime.transport`) sends any request
/// carrying it to the gateway through `AIGatewayTransport`, which signs it with App Attest.
/// The gateway serves Anthropic's Messages API, OpenAI's Responses and Chat Completions (the tasks that measured
/// best on OpenAI, EVAL_REPORT 41) and its image edits (the character), and
/// nothing else: there is no way for a person to add a key of their own.
///
/// Off when there is no gateway address, when the device cannot do App Attest (the Simulator,
/// older hardware), and whenever a scoped runtime is in force (unit tests, evaluations, UI
/// flows), so tests never reach it.
enum AIGateway {
    /// The gateway's address (`server/README.md`). Empty means off. Deployed 2026-11-25 on the
    /// droplet beside the phone-agent services: HTTPS on port 8446 (Caddy, Let's Encrypt;
    /// port 443 belongs to another service there), the gateway itself on 127.0.0.1 only.
    static let address = "https://137-184-90-238.sslip.io:8446"

    /// What a client carries instead of a key when the gateway adds the key.
    static let placeholderKey = "sprout-gateway"

    static var baseURL: URL? {
        address.isEmpty ? nil : URL(string: address)
    }

    /// The gateway is configured and this device can sign for it.
    static var isAvailable: Bool {
        guard baseURL != nil, AIRuntime.effective == nil, !UITestHooks.isActive else { return false }
        return DCAppAttestService.shared.isSupported
    }

    private static let openAIKey = "ai_gateway_covers_openai"

    /// Whether the gateway pays for `provider`. Anthropic always; OpenAI when its `/health`
    /// last said so (it is optional on the server).
    static func covers(_ provider: AIProvider) -> Bool {
        guard isAvailable else { return false }
        switch provider {
        case .anthropic: return true
        case .openai: return UserDefaults.standard.bool(forKey: openAIKey)
        }
    }

    /// The key a client should carry for `provider` when the person has none of their own.
    static func placeholder(for provider: AIProvider) -> String? {
        covers(provider) ? placeholderKey : nil
    }

    /// Reads `/health` once per launch to learn whether OpenAI is covered. Best-effort: on any
    /// failure the last known answer stays.
    static func refreshStatus(session: URLSession = .shared) async {
        guard isAvailable, let url = baseURL.map({ $0.appending(path: "health") }) else { return }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let openai = json["openai"] as? Bool ?? false
            UserDefaults.standard.set(openai, forKey: openAIKey)
            Diagnostics.shared.log("ai gateway: reachable, openai \(openai)", .ai)
        } catch {
            Diagnostics.shared.log("ai gateway: health check failed (\(error.localizedDescription))", .ai)
        }
    }

    /// The gateway route for a provider endpoint, or nil for one it does not serve.
    static func route(for url: URL) -> String? {
        switch (url.host(), url.path()) {
        case ("api.anthropic.com", "/v1/messages"): return "/anthropic/v1/messages"
        case ("api.openai.com", "/v1/responses"): return "/openai/v1/responses"
        case ("api.openai.com", "/v1/chat/completions"): return "/openai/v1/chat/completions"
        case ("api.openai.com", "/v1/images/edits"): return "/openai/v1/images/edits"
        default: return nil
        }
    }

    /// Whether a request was built with the placeholder instead of a real key.
    static func carriesPlaceholder(_ request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "x-api-key") == placeholderKey
            || request.value(forHTTPHeaderField: "Authorization") == "Bearer \(placeholderKey)"
    }

    /// The bytes the device signs for one request: `POST\n<route>\n<timestamp>\n` then the
    /// body. Must match `server/src/app.ts`.
    static func clientData(route: String, timestamp: String, body: Data) -> Data {
        var data = Data("POST\n\(route)\n\(timestamp)\n".utf8)
        data.append(body)
        return data
    }
}

// MARK: - App Attest

/// The App Attest calls, behind a protocol so the transport can be tested without a device.
protocol AppAttesting: Sendable {
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

struct DeviceAppAttest: AppAttesting {
    func generateKey() async throws -> String { try await DCAppAttestService.shared.generateKey() }
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
    }
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
    }
}

/// One HTTP exchange, behind a protocol for the same reason.
protocol GatewayHTTP: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: GatewayHTTP {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

/// This device's registered App Attest key. Registration (a new key, the gateway's one-time
/// challenge, Apple's attestation of the key, the gateway's check of it) runs once; a key the
/// gateway or the device no longer accepts is dropped and the next call registers again.
///
/// The key id is kept in UserDefaults, which a reinstall clears. App Attest keys do not
/// survive a reinstall, a restore from backup or a move to a new device (Apple), so a key id
/// restored with a backup fails on its first use and is replaced then.
actor AppAttestKey {
    static let shared = AppAttestKey(attest: DeviceAppAttest(), http: URLSession.shared, defaults: .standard)

    static let defaultsKey = "ai_gateway_key_id"

    private let attest: any AppAttesting
    private let http: any GatewayHTTP
    private let defaults: UserDefaults
    private var registration: Task<String, Error>?

    init(attest: any AppAttesting, http: any GatewayHTTP, defaults: UserDefaults) {
        self.attest = attest
        self.http = http
        self.defaults = defaults
    }

    /// The registered key id, registering first if there is none. Concurrent callers share
    /// one registration.
    func keyId(base: URL) async throws -> String {
        if let id = defaults.string(forKey: Self.defaultsKey) { return id }
        if let registration { return try await registration.value }
        let task = Task { try await register(base: base) }
        registration = task
        defer { registration = nil }
        let id = try await task.value
        defaults.set(id, forKey: Self.defaultsKey)
        return id
    }

    /// Forget the key (the gateway does not know it, or the device cannot use it).
    func discard() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    func assertion(keyId: String, clientData: Data) async throws -> Data {
        try await attest.generateAssertion(keyId, clientDataHash: Data(SHA256.hash(data: clientData)))
    }

    private func register(base: URL) async throws -> String {
        let keyId = try await attest.generateKey()

        var challengeRequest = URLRequest(url: base.appending(path: "v1/attest/challenge"))
        challengeRequest.httpMethod = "POST"
        let (challengeData, challengeResponse) = try await http.data(for: challengeRequest)
        guard (challengeResponse as? HTTPURLResponse)?.statusCode == 200,
              let challenge = (try? JSONSerialization.jsonObject(with: challengeData) as? [String: Any])?["challenge"] as? String
        else { throw AIGatewayError.registration("no challenge") }

        let attestation = try await attest.attestKey(keyId, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))

        var register = URLRequest(url: base.appending(path: "v1/attest/register"))
        register.httpMethod = "POST"
        register.setValue("application/json", forHTTPHeaderField: "Content-Type")
        register.httpBody = try JSONSerialization.data(withJSONObject: [
            "keyId": keyId,
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge,
        ])
        let (data, response) = try await http.data(for: register)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 201 else {
            let message = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
            Diagnostics.shared.log("ai gateway: registration refused (HTTP \(status)) \(message ?? "")", .ai)
            throw AIGatewayError.registration("HTTP \(status)")
        }
        Diagnostics.shared.log("ai gateway: device registered", .ai)
        return keyId
    }
}

enum AIGatewayError: LocalizedError {
    case notConfigured, unsupportedEndpoint, registration(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Built-in AI is not set up."
        case .unsupportedEndpoint: return "Built-in AI does not serve this request."
        case .registration(let why): return "This device could not be registered for built-in AI (\(why))."
        }
    }
}

// MARK: - Transport

/// Sends a request built for a provider to the gateway instead: the same body, the same
/// provider headers except the key, plus the App Attest signature. Retries once when the
/// gateway does not know the device (it registers again) or refuses the signature (a fresh
/// one is made); every other answer, error or not, goes back to the client unchanged so its
/// own handling (retries, messages) works as it does against the provider.
struct AIGatewayTransport: AITransport {
    var base: URL
    var key: AppAttestKey = .shared
    var http: any GatewayHTTP = URLSession.shared
    var now: @Sendable () -> Date = { Date() }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url, let route = AIGateway.route(for: url) else {
            throw AIGatewayError.unsupportedEndpoint
        }
        let body = request.httpBody ?? Data()
        var lastResult: (Data, URLResponse)?
        for attempt in 0..<2 {
            let keyId = try await key.keyId(base: base)
            let timestamp = String(Int64((now().timeIntervalSince1970 * 1000).rounded()))
            let assertion: Data
            do {
                assertion = try await key.assertion(keyId: keyId,
                                                    clientData: AIGateway.clientData(route: route, timestamp: timestamp, body: body))
            } catch {
                // The device no longer has this key (a restore from backup, a new device).
                Diagnostics.shared.log("ai gateway: assertion failed (\(error.localizedDescription)); registering again", .ai)
                await key.discard()
                if attempt == 0 { continue }
                throw error
            }

            var forwarded = URLRequest(url: base.appending(path: String(route.dropFirst())))
            forwarded.httpMethod = "POST"
            forwarded.timeoutInterval = max(request.timeoutInterval, 60)
            for (name, value) in request.allHTTPHeaderFields ?? [:] {
                let lower = name.lowercased()
                if lower == "x-api-key" || lower == "authorization" { continue }
                forwarded.setValue(value, forHTTPHeaderField: name)
            }
            forwarded.setValue(keyId, forHTTPHeaderField: "X-Sprout-Key-Id")
            forwarded.setValue(timestamp, forHTTPHeaderField: "X-Sprout-Timestamp")
            forwarded.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-Sprout-Assertion")
            forwarded.httpBody = body

            let result = try await http.data(for: forwarded)
            lastResult = result
            guard attempt == 0, (result.1 as? HTTPURLResponse)?.statusCode == 401 else { return result }
            switch Self.errorType(result.0) {
            case "unknown_device":
                Diagnostics.shared.log("ai gateway: device unknown to the gateway; registering again", .ai)
                await key.discard()
            case "assertion_rejected":
                Diagnostics.shared.log("ai gateway: signature refused; signing again", .ai)
            default:
                return result
            }
        }
        return lastResult!
    }

    /// `error.type` of a gateway refusal, in either provider's error shape.
    static func errorType(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["type"] as? String
    }
}

/// The transport the app uses when no scoped runtime is in force: a request carrying the
/// gateway placeholder goes to the gateway, everything else to the provider directly.
struct AIDefaultTransport: AITransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if AIGateway.carriesPlaceholder(request) {
            guard let base = AIGateway.baseURL else { throw AIGatewayError.notConfigured }
            return try await AIGatewayTransport(base: base).data(for: request)
        }
        return try await URLSessionTransport().data(for: request)
    }
}
