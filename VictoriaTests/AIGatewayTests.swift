import CryptoKit
import XCTest
@testable import Victoria

/// The app's side of the built-in AI (`AIGateway`): which requests go to the gateway, the
/// exact bytes a device signs (they must match `server/src/app.ts`), registration, and the
/// one retry. App Attest and the network are fakes, so nothing here needs a device.
final class AIGatewayTests: XCTestCase {

    private let base = URL(string: "https://gateway.test")!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "AIGatewayTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: - Fakes

    /// App Attest as a device does it, recording what it was asked to sign.
    actor FakeAttest: AppAttesting {
        var keysMade = 0
        var attested: [(keyId: String, hash: Data)] = []
        var signed: [(keyId: String, hash: Data)] = []
        var failNextAssertion = false

        func generateKey() async throws -> String {
            keysMade += 1
            return "key-\(keysMade)"
        }
        func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
            attested.append((keyId, clientDataHash))
            return Data("attestation-of-\(keyId)".utf8)
        }
        func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
            if failNextAssertion {
                failNextAssertion = false
                throw NSError(domain: "DCErrorDomain", code: 3) // invalidKey
            }
            signed.append((keyId, clientDataHash))
            return Data("assertion-\(signed.count)".utf8)
        }
        func setFailNextAssertion() { failNextAssertion = true }
    }

    /// The gateway: answers by path, and records every request it got.
    actor FakeGateway: GatewayHTTP {
        var requests: [URLRequest] = []
        /// Responses to model calls, used in order; then 200 forever.
        var modelReplies: [(Int, String)] = []
        var challengeCount = 0

        func setModelReplies(_ replies: [(Int, String)]) { modelReplies = replies }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            let path = request.url!.path()
            func reply(_ status: Int, _ body: String) -> (Data, URLResponse) {
                (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            switch path {
            case "/v1/attest/challenge":
                challengeCount += 1
                return reply(200, #"{"challenge":"challenge-\#(challengeCount)","expiresInSeconds":300}"#)
            case "/v1/attest/register":
                return reply(201, #"{"ok":true,"environment":"development"}"#)
            default:
                if !modelReplies.isEmpty {
                    let (status, body) = modelReplies.removeFirst()
                    return reply(status, body)
                }
                return reply(200, #"{"id":"msg_1","content":[{"type":"text","text":"hi"}]}"#)
            }
        }

        func modelCalls() -> [URLRequest] { requests.filter { $0.url!.path().hasPrefix("/anthropic") || $0.url!.path().hasPrefix("/openai") } }
        func registrations() -> [URLRequest] { requests.filter { $0.url!.path() == "/v1/attest/register" } }
    }

    private func providerRequest(body: String = #"{"model":"claude-sonnet-5","max_tokens":700}"#) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(AIGateway.placeholderKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = Data(body.utf8)
        return request
    }

    private func transport(_ attest: FakeAttest, _ gateway: FakeGateway, at ms: Int64 = 1_764_000_000_000) -> AIGatewayTransport {
        AIGatewayTransport(base: base,
                           key: AppAttestKey(attest: attest, http: gateway, defaults: defaults),
                           http: gateway,
                           now: { Date(timeIntervalSince1970: TimeInterval(ms) / 1000) })
    }

    private func status(_ response: URLResponse) -> Int { (response as! HTTPURLResponse).statusCode }

    // MARK: - Which requests go to the gateway

    func testTheGatewayServesTheFourProviderEndpointsTheAppCalls() {
        XCTAssertEqual(AIGateway.route(for: URL(string: "https://api.anthropic.com/v1/messages")!), "/anthropic/v1/messages")
        XCTAssertEqual(AIGateway.route(for: URL(string: "https://api.openai.com/v1/chat/completions")!), "/openai/v1/chat/completions")
        XCTAssertEqual(AIGateway.route(for: URL(string: "https://api.openai.com/v1/responses")!), "/openai/v1/responses")
        XCTAssertEqual(AIGateway.route(for: URL(string: "https://api.openai.com/v1/images/edits")!), "/openai/v1/images/edits")
        XCTAssertNil(AIGateway.route(for: URL(string: "https://api.anthropic.com/v1/models")!))
        XCTAssertNil(AIGateway.route(for: URL(string: "https://example.com/v1/messages")!))
    }

    func testOnlyARequestCarryingThePlaceholderGoesToTheGateway() {
        var anthropic = providerRequest()
        XCTAssertTrue(AIGateway.carriesPlaceholder(anthropic))
        anthropic.setValue("sk-ant-her-own-key", forHTTPHeaderField: "x-api-key")
        XCTAssertFalse(AIGateway.carriesPlaceholder(anthropic), "her own key goes straight to Anthropic")

        var openai = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        openai.setValue("Bearer \(AIGateway.placeholderKey)", forHTTPHeaderField: "Authorization")
        XCTAssertTrue(AIGateway.carriesPlaceholder(openai))
        openai.setValue("Bearer sk-proj-real", forHTTPHeaderField: "Authorization")
        XCTAssertFalse(AIGateway.carriesPlaceholder(openai))
    }

    func testTheGatewayIsOffWithoutAnAddressAndInsideTests() {
        // The shipped address is empty until the gateway is deployed, and a scoped runtime
        // (every unit test and evaluation) turns it off regardless.
        XCTAssertFalse(AIRuntime.$current.withValue(AIRuntime()) { AIGateway.isAvailable })
        if AIGateway.address.isEmpty {
            XCTAssertFalse(AIGateway.isAvailable)
            XCTAssertNil(AIGateway.placeholder(for: .anthropic))
        }
    }

    func testTheSignedBytesAreMethodRouteTimestampThenTheBody() {
        let body = Data(#"{"a":1}"#.utf8)
        let data = AIGateway.clientData(route: "/anthropic/v1/messages", timestamp: "1764000000000", body: body)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "POST\n/anthropic/v1/messages\n1764000000000\n{\"a\":1}")
    }

    // MARK: - Registration and signing

    func testTheFirstCallRegistersTheDeviceThenSendsTheSignedRequestWithoutAKey() async throws {
        let attest = FakeAttest(), gateway = FakeGateway()
        let (data, response) = try await transport(attest, gateway).data(for: providerRequest())
        XCTAssertEqual(status(response), 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"id":"msg_1","content":[{"type":"text","text":"hi"}]}"#)

        // Registration: Apple attested the new key over SHA-256 of the gateway's challenge.
        let attested = await attest.attested
        XCTAssertEqual(attested.count, 1)
        XCTAssertEqual(attested[0].keyId, "key-1")
        XCTAssertEqual(attested[0].hash, Data(SHA256.hash(data: Data("challenge-1".utf8))))
        let registration = await gateway.registrations()
        let registered = try JSONSerialization.jsonObject(with: registration[0].httpBody!) as! [String: String]
        XCTAssertEqual(registered["keyId"], "key-1")
        XCTAssertEqual(registered["challenge"], "challenge-1")
        XCTAssertEqual(registered["attestation"], Data("attestation-of-key-1".utf8).base64EncodedString())

        // The model call: to the gateway route, same body and provider headers, no key.
        let call = await gateway.modelCalls()[0]
        XCTAssertEqual(call.url?.absoluteString, "https://gateway.test/anthropic/v1/messages")
        XCTAssertEqual(call.httpMethod, "POST")
        XCTAssertNil(call.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertNil(call.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(call.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(call.httpBody, providerRequest().httpBody)
        XCTAssertEqual(call.value(forHTTPHeaderField: "X-Sprout-Key-Id"), "key-1")
        XCTAssertEqual(call.value(forHTTPHeaderField: "X-Sprout-Timestamp"), "1764000000000")
        XCTAssertEqual(call.value(forHTTPHeaderField: "X-Sprout-Assertion"), Data("assertion-1".utf8).base64EncodedString())

        // What the device signed is exactly what the gateway will rebuild.
        let signed = await attest.signed
        let expected = AIGateway.clientData(route: "/anthropic/v1/messages", timestamp: "1764000000000", body: providerRequest().httpBody!)
        XCTAssertEqual(signed[0].hash, Data(SHA256.hash(data: expected)))
        XCTAssertEqual(defaults.string(forKey: AppAttestKey.defaultsKey), "key-1")
    }

    func testLaterCallsReuseTheRegisteredKey() async throws {
        let attest = FakeAttest(), gateway = FakeGateway()
        let t = transport(attest, gateway)
        _ = try await t.data(for: providerRequest())
        _ = try await t.data(for: providerRequest())
        _ = try await t.data(for: providerRequest())
        let keysMade = await attest.keysMade
        let registrations = await gateway.registrations().count
        let calls = await gateway.modelCalls().count
        XCTAssertEqual(keysMade, 1)
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(calls, 3)
    }

    func testConcurrentFirstCallsShareOneRegistration() async throws {
        let attest = FakeAttest(), gateway = FakeGateway()
        let t = transport(attest, gateway)
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<5 { group.addTask { self.status(try await t.data(for: self.providerRequest()).1) } }
            for try await code in group { XCTAssertEqual(code, 200) }
        }
        let keysMade = await attest.keysMade
        XCTAssertEqual(keysMade, 1)
    }

    func testAGatewayThatForgotTheDeviceGetsItRegisteredAgainOnce() async throws {
        let attest = FakeAttest(), gateway = FakeGateway()
        defaults.set("key-old", forKey: AppAttestKey.defaultsKey)
        await gateway.setModelReplies([(401, #"{"type":"error","error":{"type":"unknown_device","message":"x"}}"#)])
        let (_, response) = try await transport(attest, gateway).data(for: providerRequest())
        XCTAssertEqual(status(response), 200)
        let calls = await gateway.modelCalls()
        XCTAssertEqual(calls.map { $0.value(forHTTPHeaderField: "X-Sprout-Key-Id") }, ["key-old", "key-1"])
        XCTAssertEqual(defaults.string(forKey: AppAttestKey.defaultsKey), "key-1")
    }

    func testARefusedSignatureIsMadeAgainWithoutRegistering() async throws {
        let attest = FakeAttest(), gateway = FakeGateway()
        await gateway.setModelReplies([(401, #"{"type":"error","error":{"type":"assertion_rejected","message":"x"}}"#)])
        let (_, response) = try await transport(attest, gateway).data(for: providerRequest())
        XCTAssertEqual(status(response), 200)
        let calls = await gateway.modelCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertNotEqual(calls[0].value(forHTTPHeaderField: "X-Sprout-Assertion"), calls[1].value(forHTTPHeaderField: "X-Sprout-Assertion"))
        let registrations = await gateway.registrations().count
        XCTAssertEqual(registrations, 1)
    }

    func testItRetriesOnlyOnce() async throws {
        let attest = FakeAttest(), gateway = FakeGateway()
        let refused = (401, #"{"type":"error","error":{"type":"assertion_rejected","message":"x"}}"#)
        await gateway.setModelReplies([refused, refused, refused])
        let (_, response) = try await transport(attest, gateway).data(for: providerRequest())
        XCTAssertEqual(status(response), 401)
        let calls = await gateway.modelCalls().count
        XCTAssertEqual(calls, 2)
    }

    func testAKeyTheDeviceLostIsReplaced() async throws {
        let attest = FakeAttest(), gateway = FakeGateway()
        defaults.set("key-restored-from-backup", forKey: AppAttestKey.defaultsKey)
        await attest.setFailNextAssertion()
        let (_, response) = try await transport(attest, gateway).data(for: providerRequest())
        XCTAssertEqual(status(response), 200)
        let calls = await gateway.modelCalls()
        XCTAssertEqual(calls.map { $0.value(forHTTPHeaderField: "X-Sprout-Key-Id") }, ["key-1"])
    }

    func testEveryOtherAnswerGoesBackToTheClientUnchanged() async throws {
        let attest = FakeAttest(), gateway = FakeGateway()
        let limit = #"{"type":"error","error":{"type":"daily_limit","message":"You've used today's AI allowance."}}"#
        await gateway.setModelReplies([(429, limit), (529, #"{"type":"error","error":{"type":"overloaded_error"}}"#)])
        let t = transport(attest, gateway)
        let (first, r1) = try await t.data(for: providerRequest())
        XCTAssertEqual(status(r1), 429)
        XCTAssertEqual(String(decoding: first, as: UTF8.self), limit)
        let (_, r2) = try await t.data(for: providerRequest())
        XCTAssertEqual(status(r2), 529)
        let calls = await gateway.modelCalls().count
        XCTAssertEqual(calls, 2, "no retry of its own: the client's handling decides")
    }

    func testAnEndpointTheGatewayDoesNotServeIsRefusedBeforeAnythingIsSent() async {
        let attest = FakeAttest(), gateway = FakeGateway()
        var request = providerRequest()
        request.url = URL(string: "https://api.anthropic.com/v1/models")
        do {
            _ = try await transport(attest, gateway).data(for: request)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertTrue(error is AIGatewayError)
        }
        let sent = await gateway.requests.count
        XCTAssertEqual(sent, 0)
    }

    // MARK: - What she reads when the allowance is used up

    func testTheDailyAllowanceHasItsOwnMessageAndNoRetry() {
        for type in ["daily_limit", "service_limit"] {
            let failure = AIHTTPFailure(provider: .anthropic, status: 429, type: type, message: "x", retryAfter: 43_200)
            let error = CoachTurnError.classify(failure)
            XCTAssertEqual(error, .dailyLimit, type)
            XCTAssertEqual(error.action, .waitForTomorrow)
            XCTAssertFalse(error.canRetry)
            XCTAssertEqual(error.logName, "daily-limit")
            XCTAssertTrue(error.message(provider: .anthropic).contains("back tomorrow"))
        }
        // A provider's own 429 is still a rate limit.
        let provider429 = AIHTTPFailure(provider: .anthropic, status: 429, type: "rate_limit_error", message: "x", retryAfter: 12)
        XCTAssertEqual(CoachTurnError.classify(provider429), .rateLimited(retryAfter: 12))
    }
}
