import XCTest
@testable import Sprout

/// The coach's error taxonomy: what each thrown error and each provider error response is
/// called, what the user is told, and what they can do. Pure: no client, no store.
final class CoachTurnErrorTests: XCTestCase {

    private func http(_ provider: AIProvider = .anthropic, _ status: Int, type: String? = nil,
                      code: String? = nil, message: String = "", retryAfter: TimeInterval? = nil) -> AIHTTPFailure {
        AIHTTPFailure(provider: provider, status: status, type: type, code: code,
                      message: message, retryAfter: retryAfter)
    }

    private let badResponse = AIConfig.AIError.badResponse("x")

    // MARK: - Thrown errors

    func testThrownErrorsWithNoProviderResponse() {
        XCTAssertEqual(CoachTurnError.classify(CancellationError()), .cancelled)
        XCTAssertEqual(CoachTurnError.classify(URLError(.cancelled)), .cancelled)
        XCTAssertEqual(CoachTurnError.classify(AIConfig.AIError.missingKey), .missingKey)
        XCTAssertEqual(CoachTurnError.classify(AIConfig.AIError.decoding("empty text")), .malformed)
        XCTAssertEqual(CoachTurnError.classify(badResponse), .unknown,
                       "a bad response with no recorded status cannot be told apart")
        struct Other: Error {}
        XCTAssertEqual(CoachTurnError.classify(Other()), .unknown)
    }

    func testURLErrors() {
        let table: [(URLError.Code, CoachTurnError)] = [
            (.notConnectedToInternet, .offline), (.dataNotAllowed, .offline), (.internationalRoamingOff, .offline),
            (.timedOut, .timeout),
            (.networkConnectionLost, .connectionLost), (.cannotConnectToHost, .connectionLost),
            (.cannotFindHost, .connectionLost), (.dnsLookupFailed, .connectionLost),
            (.secureConnectionFailed, .connectionLost),
            (.badURL, .unknown), (.badServerResponse, .unknown),
        ]
        for (code, expected) in table {
            XCTAssertEqual(CoachTurnError.classify(URLError(code)), expected, "URLError \(code.rawValue)")
        }
    }

    // MARK: - Provider responses

    func testStatusCodes() {
        let table: [(Int, CoachTurnError)] = [
            (401, .auth), (403, .auth), (404, .modelUnavailable), (408, .timeout), (413, .tooLong),
            (429, .rateLimited(retryAfter: nil)), (500, .server), (502, .server), (503, .overloaded),
            (504, .timeout), (529, .overloaded), (400, .unknown), (409, .unknown), (422, .unknown),
        ]
        for (status, expected) in table {
            XCTAssertEqual(CoachTurnError.classify(badResponse, http: http(.anthropic, status)), expected, "\(status)")
            XCTAssertEqual(CoachTurnError.classify(badResponse, http: http(.openai, status)), expected, "\(status)")
        }
        XCTAssertEqual(CoachTurnError.classify(http(.anthropic, 500, type: "overloaded_error")), .overloaded,
                       "the provider's own type wins over a generic 500")
        XCTAssertEqual(CoachTurnError.classify(http(.openai, 429, retryAfter: 12)), .rateLimited(retryAfter: 12))
    }

    func testAnEmptyAccountIsBillingWhateverTheStatus() {
        XCTAssertEqual(CoachTurnError.classify(http(.openai, 429, type: "insufficient_quota")), .billing)
        XCTAssertEqual(CoachTurnError.classify(http(.openai, 429, code: "insufficient_quota")), .billing)
        XCTAssertEqual(CoachTurnError.classify(http(.openai, 429, code: "credit_balance_exhausted")), .billing)
        XCTAssertEqual(CoachTurnError.classify(http(.openai, 429, code: "billing_hard_limit_reached")), .billing)
        XCTAssertEqual(CoachTurnError.classify(http(.anthropic, 402, type: "billing_error")), .billing)
        XCTAssertEqual(CoachTurnError.classify(http(
            .anthropic, 400, type: "invalid_request_error",
            message: "Your credit balance is too low to access the Anthropic API.")), .billing)
        XCTAssertEqual(CoachTurnError.classify(http(.openai, 429, type: "rate_limit_exceeded", code: "rate_limit_exceeded")),
                       .rateLimited(retryAfter: nil), "an ordinary rate limit is not a billing problem")
    }

    func testContextOverflow() {
        XCTAssertEqual(CoachTurnError.classify(http(.openai, 400, code: "context_length_exceeded")), .tooLong)
        XCTAssertEqual(CoachTurnError.classify(http(.anthropic, 400, message: "prompt is too long: 9 > 8")), .tooLong)
        XCTAssertEqual(CoachTurnError.classify(http(.openai, 400, message: "This model's maximum context length is 1.")), .tooLong)
        XCTAssertEqual(CoachTurnError.classify(http(.anthropic, 400, message: "messages: at least one message is required")),
                       .unknown, "another 400 is not a length problem")
        XCTAssertEqual(CoachTurnError.classify(http(.anthropic, 500, message: "prompt is too long")), .server,
                       "the wording only counts on a 400")
    }

    func testATransportErrorWinsOverAStaleProviderResponse() {
        // The recorder may still hold the response of an earlier attempt; the thrown error is
        // what ended this one.
        XCTAssertEqual(CoachTurnError.classify(URLError(.timedOut), http: http(.anthropic, 529)), .timeout)
        XCTAssertEqual(CoachTurnError.classify(AIConfig.AIError.missingKey, http: http(.anthropic, 401)), .missingKey)
    }

    // MARK: - Action and message

    private let all: [CoachTurnError] = [
        .offline, .connectionLost, .timeout, .missingKey, .auth, .modelUnavailable, .billing,
        .rateLimited(retryAfter: nil), .rateLimited(retryAfter: 30), .overloaded, .server, .tooLong,
        .cutOff, .refusal, .cancelled, .interrupted, .malformed, .unknown,
    ]

    func testEveryErrorHasItsAction() {
        let expected: [CoachTurnError.Action] = [
            .retry, .retry, .retry, .unavailable, .retry, .retry, .retry,
            .retry, .retryAfter(30), .retry, .retry, .rephrase,
            .retry, .rephrase, .retry, .retry, .retry, .retry,
        ]
        XCTAssertEqual(all.map(\.action), expected)
        XCTAssertEqual(all.filter { !$0.canRetry }, [.missingKey, .tooLong, .refusal],
                       "only a message that has to change, or a phone with no AI, cannot be sent again")
        XCTAssertEqual(CoachTurnError.rateLimited(retryAfter: 0.4).action, .retry,
                       "a wait under a second is not worth a countdown")
    }

    func testEveryErrorHasItsOwnMessageAndNoneIsTheGenericOneButUnknown() {
        let generic = CoachTurnError.unknown.message(provider: .anthropic)
        XCTAssertEqual(generic, "Something went wrong on my end. Let's try that again in a moment 💚")
        let messages = all.map { $0.message(provider: .anthropic) }
        XCTAssertEqual(Set(messages).count, messages.count, "two causes share a message")
        XCTAssertEqual(messages.filter { $0 == generic }.count, 1)
        for message in messages {
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains("HTTP"), "no status codes in what the user reads: \(message)")
            XCTAssertLessThanOrEqual(message.count, 170, "short enough for one row: \(message)")
        }
        XCTAssertEqual(Set(all.map(\.logName)).count, all.count - 1, "the two rate-limit cases share a log name")
    }

    func testMessagesNameTheProviderThatWasAsked() {
        for error in [CoachTurnError.auth, .billing, .rateLimited(retryAfter: nil), .overloaded, .server, .modelUnavailable] {
            XCTAssertTrue(error.message(provider: .anthropic).contains("Anthropic"), "\(error)")
            XCTAssertTrue(error.message(provider: .openai).contains("OpenAI"), "\(error)")
        }
        // The owner's key, model and account are on the gateway: nothing asks the person to
        // fix them, and nothing points at a console or a settings screen.
        for error in [CoachTurnError.auth, .billing, .modelUnavailable, .missingKey] {
            let message = error.message(provider: .anthropic)
            XCTAssertFalse(message.localizedCaseInsensitiveContains("key"), message)
            XCTAssertFalse(message.contains("Settings") || message.contains("More →") || message.contains(".com"), message)
        }
        XCTAssertEqual(CoachTurnError.offline.message(provider: .openai),
                       "I can't reach the internet right now — mind checking your connection? 💚",
                       "the offline wording the chat has always used")
    }

    func testNoAIOnThisPhoneWording() {
        XCTAssertEqual(CoachTurnError.missingKey.message(provider: .anthropic),
                       "I can't chat on this phone, sorry. Everything you log still works 💚")
        XCTAssertEqual(CoachTurnError.missingKey.action, .unavailable)
    }

    func testWaitText() {
        XCTAssertEqual(CoachTurnError.waitText(1), "1 second")
        XCTAssertEqual(CoachTurnError.waitText(1.2), "2 seconds")
        XCTAssertEqual(CoachTurnError.waitText(59), "59 seconds")
        XCTAssertEqual(CoachTurnError.waitText(60), "1 minute")
        XCTAssertEqual(CoachTurnError.waitText(61), "2 minutes")
        XCTAssertEqual(CoachTurnError.waitText(600), "10 minutes")
        XCTAssertTrue(CoachTurnError.rateLimited(retryAfter: 12).message(provider: .openai).contains("12 seconds"))
        XCTAssertFalse(CoachTurnError.rateLimited(retryAfter: nil).message(provider: .openai).contains("seconds"))
    }

    // MARK: - AIHTTPFailure

    func testRetryAfterHeaderParsing() {
        XCTAssertEqual(AIHTTPFailure.retryAfter(seconds: "20", milliseconds: nil), 20)
        XCTAssertEqual(AIHTTPFailure.retryAfter(seconds: " 1.5 ", milliseconds: nil), 1.5)
        XCTAssertEqual(AIHTTPFailure.retryAfter(seconds: "20", milliseconds: "250"), 0.25, "milliseconds win")
        XCTAssertEqual(AIHTTPFailure.retryAfter(seconds: "0", milliseconds: nil), 0)
        XCTAssertNil(AIHTTPFailure.retryAfter(seconds: nil, milliseconds: nil))
        XCTAssertNil(AIHTTPFailure.retryAfter(seconds: "-3", milliseconds: nil))
        XCTAssertNil(AIHTTPFailure.retryAfter(seconds: "Wed, 21 Oct 2026 07:28:00 GMT", milliseconds: nil),
                     "the date form is not read")
        XCTAssertEqual(AIHTTPFailure.retryAfter(seconds: "7", milliseconds: "soon"), 7)
    }

    func testFailureIsReadFromAnErrorResponse() throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid/v1/messages"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url, statusCode: 429, httpVersion: "HTTP/1.1",
            headerFields: ["Retry-After": "9", "request-id": "req_42"]))
        let failure = AIHTTPFailure(provider: .anthropic, response: response, json: [
            "type": "error", "error": ["type": "rate_limit_error", "message": "Slow down."]])
        XCTAssertEqual(failure, AIHTTPFailure(provider: .anthropic, status: 429, type: "rate_limit_error",
                                              message: "Slow down.", retryAfter: 9, requestID: "req_42"))

        let bare = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 502, httpVersion: nil, headerFields: nil))
        let unreadable = AIHTTPFailure(provider: .openai, response: bare, json: [:])
        XCTAssertEqual(unreadable.message, "HTTP 502", "the message the clients have always thrown")
        XCTAssertNil(unreadable.retryAfter)
        XCTAssertNil(unreadable.type)
    }

    func testAutomaticRetryDelay() {
        let retryable: Set<Int> = [429, 503, 529]
        XCTAssertEqual(http(.anthropic, 529).automaticRetryDelay(retryableStatuses: retryable), 0.7,
                       "no header: the fixed back-off the clients have always used")
        XCTAssertEqual(http(.anthropic, 429, retryAfter: 2).automaticRetryDelay(retryableStatuses: retryable), 2)
        XCTAssertEqual(http(.anthropic, 429, retryAfter: 5).automaticRetryDelay(retryableStatuses: retryable), 5)
        XCTAssertNil(http(.anthropic, 429, retryAfter: 5.1).automaticRetryDelay(retryableStatuses: retryable),
                     "a wait longer than five seconds is the caller's to show")
        XCTAssertNil(http(.anthropic, 500).automaticRetryDelay(retryableStatuses: retryable))
        XCTAssertNil(http(.anthropic, 401).automaticRetryDelay(retryableStatuses: retryable))
        XCTAssertNil(http(.openai, 429, type: "insufficient_quota").automaticRetryDelay(retryableStatuses: retryable))
        XCTAssertNil(http(.openai, 529).automaticRetryDelay(retryableStatuses: [429, 503]),
                     "529 is not in OpenAI's set")
    }

    func testTheRecorderIsScopedAndNothingIsRecordedOutsideAScope() {
        XCTAssertNil(AIFailureRecorder.current)
        AIFailureRecorder.report(http(.anthropic, 500))   // no scope: a no-op, not a crash
        let recorder = AIFailureRecorder()
        XCTAssertNil(recorder.last)
        AIFailureRecorder.$current.withValue(recorder) {
            AIFailureRecorder.report(http(.anthropic, 429))
            AIFailureRecorder.report(http(.anthropic, 529))
        }
        XCTAssertEqual(recorder.last?.status, 529, "the last failure of the scope")
        XCTAssertNil(AIFailureRecorder.current)
    }

    // MARK: - Finish reasons

    func testAnthropicStopReasons() {
        XCTAssertEqual(AnthropicClient.finish(stopReason: "end_turn"), .complete)
        XCTAssertEqual(AnthropicClient.finish(stopReason: "tool_use"), .complete)
        XCTAssertEqual(AnthropicClient.finish(stopReason: "stop_sequence"), .complete)
        XCTAssertEqual(AnthropicClient.finish(stopReason: "pause_turn"), .complete)
        XCTAssertEqual(AnthropicClient.finish(stopReason: "max_tokens"), .cutOff)
        XCTAssertEqual(AnthropicClient.finish(stopReason: "refusal"), .refusal)
        XCTAssertEqual(AnthropicClient.finish(stopReason: "model_context_window_exceeded"), .contextOverflow)
        XCTAssertEqual(AnthropicClient.finish(stopReason: nil), .complete)
        XCTAssertEqual(AnthropicClient.finish(stopReason: "something_new"), .complete)
    }

    func testOpenAIFinishReasons() throws {
        func chat(_ reason: String, content: Any = "hi", refusal: Any = NSNull()) throws -> AnthropicClient.ChatTurn {
            try OpenAIClient.parseToolTurn(["choices": [[
                "finish_reason": reason, "message": ["role": "assistant", "content": content, "refusal": refusal]]]])
        }
        XCTAssertEqual(try chat("stop").finish, .complete)
        XCTAssertEqual(try chat("tool_calls").finish, .complete)
        XCTAssertEqual(try chat("length").finish, .cutOff)
        XCTAssertEqual(try chat("content_filter").finish, .refusal)
        let refused = try chat("stop", content: NSNull(), refusal: "I can't help with that.")
        XCTAssertEqual(refused.finish, .refusal)
        XCTAssertEqual(refused.text, "I can't help with that.", "the refusal is what the model said")
        XCTAssertEqual(try chat("stop", content: "Sure.", refusal: "").finish, .complete)

        func responses(status: String, reason: String? = nil, parts: [[String: Any]]) throws -> AnthropicClient.ChatTurn {
            var json: [String: Any] = ["status": status,
                                       "output": [["type": "message", "content": parts]]]
            if let reason { json["incomplete_details"] = ["reason": reason] }
            return try OpenAIClient.parseResponsesToolTurn(json)
        }
        let text: [[String: Any]] = [["type": "output_text", "text": "hi"]]
        XCTAssertEqual(try responses(status: "completed", parts: text).finish, .complete)
        XCTAssertEqual(try responses(status: "incomplete", reason: "max_output_tokens", parts: text).finish, .cutOff)
        XCTAssertEqual(try responses(status: "incomplete", reason: "content_filter", parts: []).finish, .refusal)
        let part = try responses(status: "completed", parts: [["type": "refusal", "refusal": "No."]])
        XCTAssertEqual(part.finish, .refusal)
        XCTAssertEqual(part.text, "No.")
        XCTAssertEqual(try responses(status: "completed", reason: "max_output_tokens", parts: text).finish, .complete,
                       "a reason only counts on an incomplete response")
    }
}
