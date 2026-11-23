import XCTest
import SwiftData
import UIKit
@testable import Victoria

/// G8 (b), (c), (d): the "make my character" flow's rules. Consent before anything is
/// sent; the photo is never persisted; and every way the call can go wrong leaves the
/// person with a built-in character and a way forward.
@MainActor
final class AvatarCreationModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AvatarGenerator.retryDelay = .zero
    }

    override func tearDown() {
        AvatarGenerator.retryDelay = .milliseconds(700)
        super.tearDown()
    }

    private func runtime(_ transport: ScriptedTransport, key: String = "test-key-not-real") -> AIRuntime {
        AIRuntime(provider: .anthropic, apiKey: key, transport: transport)
    }

    private func good(_ png: Data = TestImages.characterPNG()) -> ScriptedTransport.Reply {
        .json(200, ["data": [["b64_json": png.base64EncodedString()]]])
    }

    private func model(theme: ThemeStyle = .cool, hasKey: Bool = true) -> AvatarCreationModel {
        AvatarCreationModel(theme: theme, hasKey: { hasKey })
    }

    private func run(_ model: AvatarCreationModel, _ transport: ScriptedTransport, key: String = "test-key-not-real") async {
        await AIRuntime.$current.withValue(runtime(transport, key: key)) {
            await model.generateAndWait()
        }
    }

    // MARK: - Where it starts

    func testWithoutAKeyTheFlowStartsOnTheKeyStepAndCanBeLeft() {
        let model = model(theme: .cute, hasKey: false)
        XCTAssertEqual(model.phase, .needsKey)
        XCTAssertNil(model.acceptedPNG)
        XCTAssertEqual(model.fallbackAvatar, .victoria)
        XCTAssertFalse(model.canGenerate)
    }

    func testWithAKeyTheFlowStartsOnThePhotoStep() {
        XCTAssertEqual(model().phase, .start)
    }

    func testKeyStepMovesOnOnceAKeyExists() {
        var stored = false
        let model = AvatarCreationModel(theme: .cool, hasKey: { stored })
        XCTAssertEqual(model.phase, .needsKey)
        model.refreshKeyState()
        XCTAssertEqual(model.phase, .needsKey, "no key yet")
        stored = true
        model.refreshKeyState()
        XCTAssertEqual(model.phase, .start)
    }

    // MARK: - Consent

    func testNothingIsSentWithoutAPhoto() async {
        let transport = ScriptedTransport([good()])
        let model = model()
        model.consented = true
        XCTAssertFalse(model.canGenerate)
        await run(model, transport)
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(model.phase, .start)
    }

    func testNothingIsSentWithoutConsent() async {
        let transport = ScriptedTransport([good()])
        let model = model()
        model.pick(TestImages.photo(width: 80, height: 80))
        XCTAssertFalse(model.consented)
        XCTAssertFalse(model.canGenerate)
        await run(model, transport)
        XCTAssertTrue(transport.requests.isEmpty, "the photo was sent before the person agreed")
        XCTAssertEqual(model.phase, .start)
    }

    func testPhotoAndConsentTogetherSendExactlyOneRequest() async {
        let transport = ScriptedTransport([good()])
        let model = model()
        model.pick(TestImages.photo(width: 80, height: 80))
        model.consented = true
        XCTAssertTrue(model.canGenerate)
        await run(model, transport)
        XCTAssertEqual(transport.requests.count, 1)
    }

    // MARK: - The happy path

    func testAGoodImageIsPreviewedAndOnlyAcceptedOnUseThis() async {
        let png = TestImages.characterPNG()
        let model = model()
        model.pick(TestImages.photo(width: 80, height: 80))
        model.consented = true
        await run(model, ScriptedTransport([good(png)]))

        guard case .preview(let character) = model.phase else { return XCTFail("expected a preview, got \(model.phase)") }
        XCTAssertEqual(character.png, png)
        XCTAssertNil(model.acceptedPNG, "a preview is not adopted until the person says so")
        XCTAssertNotNil(model.photo, "the photo is kept in memory for Try again")

        model.accept()
        XCTAssertEqual(model.acceptedPNG, png)
        XCTAssertNil(model.photo, "the photo is dropped once the character is accepted")
    }

    func testTryAgainAsksForAnotherImageFromTheSamePhoto() async {
        let second = TestImages.png(width: 32, height: 32, grid: TestImages.characterGrid, palette: TestImages.characterPalette)
        let transport = ScriptedTransport([good(), good(second)])
        let model = model()
        model.pick(TestImages.photo(width: 80, height: 80))
        model.consented = true
        await run(model, transport)
        await AIRuntime.$current.withValue(runtime(transport)) {
            model.tryAgain()
            await model.generateAndWait()   // no-op start (already working); waits for the retry
        }
        XCTAssertEqual(transport.requests.count, 2)
        guard case .preview(let character) = model.phase else { return XCTFail("expected a preview, got \(model.phase)") }
        XCTAssertEqual(character.png, second)
    }

    func testChoosingABuiltInDropsThePhotoAndTheCharacter() async {
        let model = model(theme: .cool)
        model.pick(TestImages.photo(width: 80, height: 80))
        model.consented = true
        await run(model, ScriptedTransport([good()]))
        model.useBuiltIn()
        XCTAssertEqual(model.phase, .declined)
        XCTAssertNil(model.photo)
        XCTAssertNil(model.acceptedPNG)
        XCTAssertFalse(model.consented, "consent does not carry over to a later photo")
        XCTAssertEqual(model.fallbackAvatar, .bryan)
    }

    // MARK: - Every failure leaves a built-in character and a way forward

    func testEachFailureEndsInTheFailedStateWithNoCustomCharacter() async {
        let opaque = TestImages.png(width: 64, height: 64, background: .white, opaque: true)
        let wide = TestImages.png(width: 96, height: 64, grid: TestImages.characterGrid, palette: TestImages.characterPalette)
        let cases: [(String, [ScriptedTransport.Reply], AvatarGenerator.Failure)] = [
            ("http", [.json(400, ["error": ["message": "bad request"]])], .http(status: 400, message: "bad request")),
            ("refusal", [.json(400, ["error": ["message": "blocked", "code": "moderation_blocked",
                                               "moderation_details": ["moderation_stage": "output"]]])],
             .refused(message: "blocked", stage: "output")),
            ("malformed", [ScriptedTransport.Reply(status: 200, body: Data("oops".utf8))],
             .malformedResponse("the body is not a JSON object")),
            ("undecodable", [good(Data([9, 9, 9]))], .imageNotDecodable),
            ("not square", [good(wide)], .imageNotSquare(width: 96, height: 64)),
            ("no alpha", [good(opaque)], .imageHasNoAlpha),
        ]
        for (name, replies, want) in cases {
            let model = model(theme: .cute)
            model.pick(TestImages.photo(width: 80, height: 80))
            model.consented = true
            await run(model, ScriptedTransport(replies))
            XCTAssertEqual(model.phase, .failed(want), name)
            XCTAssertNil(model.acceptedPNG, name)
            XCTAssertEqual(model.fallbackAvatar, .victoria, name)
        }
    }

    func testANetworkFailureEndsInTheFailedState() async {
        let model = model()
        model.pick(TestImages.photo(width: 80, height: 80))
        model.consented = true
        await run(model, ScriptedTransport([]))   // the transport throws, as a dropped connection does
        guard case .failed(.network) = model.phase else { return XCTFail("expected .failed(.network), got \(model.phase)") }
        XCTAssertNil(model.acceptedPNG)
    }

    func testAKeyThatVanishedMidFlowGoesBackToTheKeyStep() async {
        let transport = ScriptedTransport([good()])
        let model = model()
        model.pick(TestImages.photo(width: 80, height: 80))
        model.consented = true
        await run(model, transport, key: "")
        XCTAssertEqual(model.phase, .needsKey)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAfterAFailureAnotherPhotoReturnsToThePhotoStep() async {
        let model = model()
        model.pick(TestImages.photo(width: 80, height: 80))
        model.consented = true
        await run(model, ScriptedTransport([.json(400, ["error": ["message": "bad"]])]))
        XCTAssertEqual(model.phase, .failed(.http(status: 400, message: "bad")))
        model.pick(TestImages.photo(width: 90, height: 90))
        XCTAssertEqual(model.phase, .start)
        XCTAssertTrue(model.canGenerate)
    }

    func testCancelWhileDrawingReturnsToThePhotoStepAndIgnoresTheLateAnswer() async {
        let model = model()
        model.pick(TestImages.photo(width: 80, height: 80))
        model.consented = true
        await AIRuntime.$current.withValue(runtime(ScriptedTransport([good()]))) {
            model.generate()
            XCTAssertEqual(model.phase, .working)
            model.cancel()
        }
        XCTAssertEqual(model.phase, .start)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.phase, .start, "an answer that arrived after Cancel was shown")
    }

    // MARK: - What reaches the profile

    func testAnAcceptedCharacterIsStoredAndBecomesTheCompanion() throws {
        let png = TestImages.characterPNG()
        let container = try TestStore.makeContainer()
        let writer = ModelContext(container)
        let profile = UserProfile()
        profile.name = "Alex"
        profile.themeStyle = .cool
        profile.companionAvatar = .bryan
        writer.insert(profile)
        profile.useCustomAvatar(png: png)
        try writer.save()

        let read = try XCTUnwrap(try TestStore.fetchAll(UserProfile.self, in: container).first)
        XCTAssertEqual(read.companionAvatarRaw, "custom")
        XCTAssertEqual(read.companionAvatar, .custom)
        XCTAssertEqual(read.customAvatarPNG, png)
    }

    func testSwitchingBackToABuiltInKeepsTheCharacterForLater() {
        let profile = UserProfile()
        profile.themeStyle = .cool
        profile.useCustomAvatar(png: TestImages.characterPNG())
        profile.companionAvatar = .bryan
        XCTAssertEqual(profile.companionAvatar, .bryan)
        XCTAssertNotNil(profile.customAvatarPNG)
        profile.companionAvatar = .custom
        XCTAssertEqual(profile.companionAvatar, .custom)
    }

    // MARK: - The photo is not persisted

    /// Files changed since `start` under the app's own directories and the App Group
    /// container whose bytes are exactly `needle`.
    private func filesHolding(_ needle: Data, since start: Date) -> [String] {
        let manager = FileManager.default
        var roots = [manager.temporaryDirectory]
        roots += manager.urls(for: .documentDirectory, in: .userDomainMask)
        roots += manager.urls(for: .cachesDirectory, in: .userDomainMask)
        roots += manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        if let group = WidgetAvatarFile.defaultDirectory { roots.append(group) }
        var hits: [String] = []
        for root in roots {
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
            guard let walker = manager.enumerator(at: root, includingPropertiesForKeys: keys) else { continue }
            for case let url as URL in walker {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= start,
                      values.fileSize == needle.count,
                      let data = try? Data(contentsOf: url), data == needle else { continue }
                hits.append(url.path)
            }
        }
        return hits
    }

    func testThePhotoIsWrittenNowhereAndOnlyTheCharacterIsStored() async throws {
        let start = Date().addingTimeInterval(-1)
        let png = TestImages.characterPNG()
        let transport = ScriptedTransport([good(png)])
        let container = try TestStore.makeContainer()
        let writer = ModelContext(container)
        let profile = UserProfile()
        profile.name = "Sam"
        writer.insert(profile)

        let model = model(theme: .cute)
        model.pick(TestImages.photo(width: 640, height: 480))
        model.consented = true
        await run(model, transport)
        model.accept()
        let accepted = try XCTUnwrap(model.acceptedPNG)
        profile.useCustomAvatar(png: accepted)
        try writer.save()

        // What left the device: one JPEG, in the request.
        let request = try XCTUnwrap(transport.requests.first)
        let uploaded = try XCTUnwrap(Multipart.parts(of: request).first { $0.name == "image" }?.data)
        XCTAssertEqual(Array(uploaded.prefix(3)), [0xFF, 0xD8, 0xFF])

        // The scan can find a file with those bytes (so "no hits" below means something).
        let planted = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-photo-control-\(UUID().uuidString).jpg")
        try uploaded.write(to: planted)
        let control = filesHolding(uploaded, since: start)
        XCTAssertEqual(control.count, 1, "the control file was not found by the scan")
        XCTAssertEqual(control.first.map { URL(fileURLWithPath: $0).lastPathComponent }, planted.lastPathComponent)
        try FileManager.default.removeItem(at: planted)

        // The photo's bytes are in no file the app wrote.
        XCTAssertEqual(filesHolding(uploaded, since: start), [], "the uploaded photo was written to disk")

        // The store holds the character and no other image: no food photo, no chat image.
        let read = try XCTUnwrap(try TestStore.fetchAll(UserProfile.self, in: container).first)
        XCTAssertEqual(read.customAvatarPNG, png)
        XCTAssertNotEqual(read.customAvatarPNG, uploaded)
        XCTAssertEqual(try TestStore.count(FoodEntry.self, in: container), 0)
        XCTAssertEqual(try TestStore.count(ChatMessage.self, in: container), 0)
        let counts = try TestStore.countsByEntity(in: container)
        XCTAssertEqual(counts.values.reduce(0, +), 1, "something besides the profile was written: \(counts)")

        // And the model no longer holds the photo.
        XCTAssertNil(model.photo)
    }
}
