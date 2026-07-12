import Foundation
import AuthenticationServices
import CryptoKit

/// OAuth 2.0 for the Google Health API (the Fitbit Air's data source) using the
/// installed-app flow: PKCE (S256), an iOS-type client (NO client secret — Google
/// doesn't issue one for iOS clients), and the reversed-client-ID custom scheme as
/// the redirect. The whole dance runs in ASWebAuthenticationSession, so the user
/// signs in with Google's real pages and we only ever see the authorization code.
///
/// Storage: the client ID (public, not a secret) lives in UserDefaults so Bryan can
/// paste it once from the Google Cloud console without a rebuild; tokens (the actual
/// secrets) live ONLY in the Keychain, same as the LLM API keys.
@MainActor
final class GoogleHealthAuth: NSObject {
    static let shared = GoogleHealthAuth()

    private static let clientIDKey = "googleHealth.clientID"
    private static let keychainAccount = "google_health_tokens"

    /// The three read scopes our features need: sleep (+stages), daily RHR/HRV,
    /// and detected exercise sessions.
    static let scopes = [
        "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
        "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
        "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
    ]

    // MARK: - Client ID

    static var clientID: String? {
        let id = UserDefaults.standard.string(forKey: clientIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (id?.isEmpty == false) ? id : nil
    }

    static func setClientID(_ id: String?) {
        let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set((trimmed?.isEmpty == false) ? trimmed : nil,
                                  forKey: clientIDKey)
    }

    /// "12345-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.12345-abc".
    /// Google's iOS redirect is this reversed form used as a URL scheme.
    nonisolated static func reversedClientID(_ clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    nonisolated static func redirectURI(for clientID: String) -> String {
        reversedClientID(clientID) + ":/oauthredirect"
    }

    // MARK: - Tokens

    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    private(set) var tokens: Tokens? {
        didSet { persistTokens() }
    }

    /// Connected = we hold a refresh token. (Access tokens expire hourly; that's normal.)
    var isConnected: Bool { tokens != nil }

    override private init() {
        super.init()
        if let data = KeychainStore.secret(account: Self.keychainAccount),
           let stored = try? JSONDecoder().decode(Tokens.self, from: data) {
            tokens = stored
        }
    }

    private func persistTokens() {
        if let tokens, let data = try? JSONEncoder().encode(tokens) {
            KeychainStore.setSecret(data, account: Self.keychainAccount)
        } else {
            KeychainStore.setSecret(nil, account: Self.keychainAccount)
        }
    }

    func disconnect() {
        // Best-effort revoke so the grant disappears from the Google account page too.
        if let token = tokens?.refreshToken,
           var comps = URLComponents(string: "https://oauth2.googleapis.com/revoke") {
            comps.queryItems = [URLQueryItem(name: "token", value: token)]
            if let url = comps.url {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                Task { _ = try? await URLSession.shared.data(for: req) }
            }
        }
        tokens = nil
        Diagnostics.shared.log("google health disconnected", .sync)
    }

    // MARK: - PKCE

    nonisolated static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    nonisolated static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Authorization URL

    nonisolated static func authorizationURL(clientID: String, challenge: String) -> URL? {
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        comps?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI(for: clientID)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return comps?.url
    }

    // MARK: - Sign in

    enum AuthError: LocalizedError {
        case noClientID
        case badClientID
        case cancelled
        case noCode
        case tokenExchange(String)
        case notConnected

        var errorDescription: String? {
            switch self {
            case .noClientID:   return "Paste your Google OAuth client ID first."
            case .badClientID:  return "That client ID doesn't look right — it should end in .apps.googleusercontent.com."
            case .cancelled:    return "Sign-in was cancelled."
            case .noCode:       return "Google didn't return an authorization code."
            case .tokenExchange(let detail): return "Couldn't finish connecting: \(detail)"
            case .notConnected: return "Google Health isn't connected."
            }
        }
    }

    private var activeSession: ASWebAuthenticationSession?

    /// Runs the full OAuth dance. On success, tokens are stored and `isConnected` flips.
    func signIn() async throws {
        guard let clientID = Self.clientID else { throw AuthError.noClientID }
        guard clientID.hasSuffix(".apps.googleusercontent.com") else { throw AuthError.badClientID }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        guard let url = Self.authorizationURL(clientID: clientID, challenge: challenge) else {
            throw AuthError.badClientID
        }
        let scheme = Self.reversedClientID(clientID)

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            // A continuation may resume exactly once. The completion handler fires once
            // by contract, but the `start() == false` branch below ALSO resumes — the
            // flag makes the two paths mutually exclusive instead of trusting AS not to
            // call the handler after a failed start.
            var resumed = false
            func resumeOnce(_ result: Result<URL, Error>) {
                guard !resumed else { return }
                resumed = true
                cont.resume(with: result)
            }
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
                if let url {
                    resumeOnce(.success(url))
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    resumeOnce(.failure(AuthError.cancelled))
                } else {
                    resumeOnce(.failure(error ?? AuthError.noCode))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeSession = session
            if !session.start() {
                self.activeSession = nil   // don't retain a dead session
                resumeOnce(.failure(AuthError.tokenExchange("couldn't open the sign-in window")))
            }
        }
        activeSession = nil

        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.noCode
        }
        try await exchangeCode(code, verifier: verifier, clientID: clientID)
        Diagnostics.shared.log("google health connected", .sync)
    }

    // MARK: - Token endpoint

    private func exchangeCode(_ code: String, verifier: String, clientID: String) async throws {
        let fields = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": Self.redirectURI(for: clientID),
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        let json = try await postTokenForm(fields)
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Double else {
            throw AuthError.tokenExchange(Self.errorDetail(json))
        }
        tokens = Tokens(accessToken: access, refreshToken: refresh,
                        expiresAt: Date().addingTimeInterval(expiresIn))
    }

    /// Single-flight refresh so concurrent fetches don't race the token endpoint.
    private var refreshTask: Task<String, Error>?

    /// A valid bearer token, refreshing transparently when the hour is up.
    func validAccessToken() async throws -> String {
        guard let current = tokens else { throw AuthError.notConnected }
        if current.expiresAt.timeIntervalSinceNow > 120 { return current.accessToken }

        if let running = refreshTask { return try await running.value }
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw AuthError.notConnected }
            return try await self.refreshAccessToken()
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func refreshAccessToken() async throws -> String {
        guard let clientID = Self.clientID, let current = tokens else { throw AuthError.notConnected }
        let fields = [
            "client_id": clientID,
            "refresh_token": current.refreshToken,
            "grant_type": "refresh_token",
        ]
        let json = try await postTokenForm(fields)
        // The user may have tapped Disconnect while the refresh was in flight — writing
        // the new tokens now would silently resurrect the connection (zombie tokens).
        guard tokens != nil else { throw AuthError.notConnected }
        guard let access = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Double else {
            let detail = Self.errorDetail(json)
            // A dead refresh token (revoked in the Google account, or 7-day testing-mode
            // expiry) can only be fixed by reconnecting — surface that as disconnected.
            if (json["error"] as? String) == "invalid_grant" {
                tokens = nil
                Diagnostics.shared.log("google health refresh token expired — reconnect needed", .sync)
                throw AuthError.notConnected
            }
            throw AuthError.tokenExchange(detail)
        }
        tokens = Tokens(accessToken: access,
                        refreshToken: current.refreshToken,
                        expiresAt: Date().addingTimeInterval(expiresIn))
        return access
    }

    private func postTokenForm(_ fields: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = fields
            .map { key, value in
                let escaped = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
                return "\(key)=\(escaped)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func errorDetail(_ json: [String: Any]) -> String {
        let err = json["error"] as? String ?? "unknown error"
        let desc = json["error_description"] as? String
        return desc.map { "\(err): \($0)" } ?? err
    }
}

extension GoogleHealthAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
