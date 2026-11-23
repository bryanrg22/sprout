import XCTest
@testable import Victoria

/// A forced structured answer that arrives with JSON inside a string is repaired when,
/// and only when, the schema says that property is an array or an object.
final class StructuredOutputRepairTests: XCTestCase {

    private let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "tasks": ["type": "array", "items": ["type": "object"]],
            "chips": ["type": "array", "items": ["type": "object"]],
            "note": ["type": "string"],
            "meta": ["type": "object"],
            "count": ["type": "number"],
        ],
        "required": ["tasks", "chips"],
    ]

    func testAWellFormedAnswerIsLeftExactlyAsItIs() {
        let input: [String: Any] = ["tasks": [["title": "Walk"]], "chips": [["title": "Gym"]], "note": "ok", "count": 2]
        let out = StructuredOutputRepair.repair(input, schema: schema)
        XCTAssertEqual(out["note"] as? String, "ok")
        XCTAssertEqual((out["tasks"] as? [[String: String]])?.first?["title"], "Walk")
        XCTAssertEqual((out["chips"] as? [[String: String]])?.first?["title"], "Gym")
        XCTAssertEqual(out["count"] as? Int, 2)
        XCTAssertEqual(out.count, 4)
    }

    /// Measured on claude-haiku-4-5 (progress summary) and claude-sonnet-5 (meal estimate).
    func testAnArrayThatArrivedAsAStringIsParsed() {
        let input: [String: Any] = ["tasks": "[{\"title\": \"Walk\"}, {\"title\": \"Stretch\"}]", "chips": [["title": "Gym"]]]
        let out = StructuredOutputRepair.repair(input, schema: schema)
        XCTAssertEqual((out["tasks"] as? [[String: String]])?.map { $0["title"] ?? "" }, ["Walk", "Stretch"])
    }

    func testAnObjectThatArrivedAsAStringIsParsed() {
        let input: [String: Any] = ["tasks": [], "chips": [], "meta": "{\"source\": \"plan\"}"]
        let out = StructuredOutputRepair.repair(input, schema: schema)
        XCTAssertEqual((out["meta"] as? [String: String])?["source"], "plan")
    }

    /// Recorded from claude-sonnet-5 on the checklist, 14 of 48 calls: every key holds a
    /// string of an object that wraps that same key.
    func testEachKeyWrappingItselfInAStringIsUnwrapped() {
        let input: [String: Any] = [
            "chips": "{\"chips\":[{\"title\":\"Gym (Legs)\",\"icon\":\"dumbbell.fill\"},{\"title\":\"Evening Walk\",\"icon\":\"figure.walk\"}]}",
            "tasks": "{\"tasks\":[{\"title\":\"Recover after legs\"}]}",
        ]
        let out = StructuredOutputRepair.repair(input, schema: schema)
        XCTAssertEqual((out["chips"] as? [[String: String]])?.map { $0["title"] ?? "" }, ["Gym (Legs)", "Evening Walk"])
        XCTAssertEqual((out["tasks"] as? [[String: String]])?.first?["title"], "Recover after legs")
        XCTAssertEqual(out.count, 2)
    }

    func testAnObjectPropertyWrappingItselfIsUnwrappedToItsValue() {
        let input: [String: Any] = ["tasks": [], "chips": [], "meta": "{\"meta\": {\"source\": \"plan\"}}"]
        let out = StructuredOutputRepair.repair(input, schema: schema)
        XCTAssertEqual((out["meta"] as? [String: String])?["source"], "plan")
    }

    /// Recorded from claude-haiku-4-5 on the progress summary: tool-call markup leaked into
    /// the field. It is not JSON, it is not repaired, and the decode error still surfaces.
    func testLeakedMarkupIsNotRepaired() {
        let leaked = "\n<parameter name=\"highlights\">\n<parameter name=\"item\">📈 0.5 lb/week gain</parameter>"
        let out = StructuredOutputRepair.repair(["tasks": leaked, "chips": []], schema: schema)
        XCTAssertEqual(out["tasks"] as? String, leaked)
    }

    func testAStringPropertyIsNeverParsedEvenWhenItLooksLikeJSON() {
        let input: [String: Any] = ["tasks": [], "chips": [], "note": "[\"this\", \"is\", \"text\"]"]
        let out = StructuredOutputRepair.repair(input, schema: schema)
        XCTAssertEqual(out["note"] as? String, "[\"this\", \"is\", \"text\"]")
    }

    func testAStringThatIsNotJSONIsLeftForTheDecoderToReject() {
        let input: [String: Any] = ["tasks": "walk, stretch", "chips": []]
        let out = StructuredOutputRepair.repair(input, schema: schema)
        XCTAssertEqual(out["tasks"] as? String, "walk, stretch", "not repairable: the decode error must still surface")
    }

    func testAStringOfTheWrongContainerKindIsLeftAlone() {
        // The schema wants an array; a string holding an object is not that array.
        let input: [String: Any] = ["tasks": "{\"title\": \"Walk\"}", "chips": []]
        let out = StructuredOutputRepair.repair(input, schema: schema)
        XCTAssertEqual(out["tasks"] as? String, "{\"title\": \"Walk\"}")
    }

    func testAWrapperForADifferentKeyIsLeftAlone() {
        // "chips" holds an object, but not one that wraps chips: nothing to unwrap.
        let input: [String: Any] = ["chips": "{\"tasks\": [{\"title\": \"Walk\"}]}", "tasks": []]
        let out = StructuredOutputRepair.repair(input, schema: schema)
        XCTAssertNotNil(out["chips"] as? String)
        XCTAssertEqual((out["tasks"] as? [Any])?.count, 0)
    }

    func testASchemaWithoutPropertiesChangesNothing() {
        let input: [String: Any] = ["tasks": "[1]"]
        XCTAssertEqual(StructuredOutputRepair.repair(input, schema: ["type": "object"])["tasks"] as? String, "[1]")
    }

    // MARK: - Through the real client

    func testChecklistShapedDoubleEncodingDecodesThroughTheAnthropicClient() async throws {
        let transport = ScriptedTransport([.json(200, [
            "content": [["type": "tool_use", "id": "tu_1", "name": "plan", "input": [
                "chips": "{\"chips\":[{\"title\":\"Gym\"}]}",
                "tasks": "{\"tasks\":[{\"title\":\"Walk\"}]}",
            ]]],
            "usage": ["input_tokens": 10, "output_tokens": 10],
        ])])
        let runtime = AIRuntime(provider: .anthropic, apiKey: "test-key-not-real", transport: transport)
        let out = try await AIRuntime.$current.withValue(runtime) {
            try await AIClient.makeFull().structured(system: "s", userContent: "u", toolName: "plan",
                                                     toolDescription: "d", schema: schema,
                                                     model: "claude-sonnet-5", maxTokens: 100)
        }
        XCTAssertEqual((out["tasks"] as? [[String: String]])?.first?["title"], "Walk")
        XCTAssertEqual((out["chips"] as? [[String: String]])?.first?["title"], "Gym")
    }
}
