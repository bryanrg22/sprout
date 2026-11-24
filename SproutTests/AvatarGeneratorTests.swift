import XCTest
import UIKit
@testable import Sprout

/// G8 (f): the custom-character call, end to end through `AIRuntime` with a scripted
/// transport. The shipped request building, response parsing and image validation run;
/// nothing reaches OpenAI and no key is read.
final class AvatarGeneratorTests: XCTestCase {

    private let setting = AIConfig.ImageSetting(model: "gpt-image-2.6-flare", quality: "medium",
                                                size: "1024x1024", background: "transparent",
                                                outputFormat: "png")

    override func setUp() {
        super.setUp()
        AvatarGenerator.retryDelay = .zero
    }

    override func tearDown() {
        AvatarGenerator.retryDelay = .milliseconds(700)
        super.tearDown()
    }

    private func runtime(_ transport: ScriptedTransport, key: String? = "test-key-not-real",
                         model: String? = nil, usage: UsageRecorder? = nil) -> AIRuntime {
        AIRuntime(provider: .anthropic, apiKey: key, model: model, transport: transport,
                  onUsage: usage.map { recorder in { @Sendable reported in recorder.record(reported) } })
    }

    private func success(_ png: Data, usage: [String: Any]? = nil) -> ScriptedTransport.Reply {
        var body: [String: Any] = ["created": 1_800_000_000,
                                   "data": [["b64_json": png.base64EncodedString()]],
                                   "background": "transparent", "output_format": "png",
                                   "quality": "medium", "size": "1024x1024"]
        if let usage { body["usage"] = usage }
        return .json(200, body)
    }

    private func generate(_ transport: ScriptedTransport, key: String? = "test-key-not-real",
                          photo: UIImage = TestImages.photo(width: 200, height: 300),
                          model: String? = nil, usage: UsageRecorder? = nil) async throws -> AvatarGenerator.Character {
        try await AIRuntime.$current.withValue(runtime(transport, key: key, model: model, usage: usage)) {
            try await AvatarGenerator.generate(from: photo, setting: self.setting)
        }
    }

    private func failure(_ transport: ScriptedTransport,
                         file: StaticString = #filePath, line: UInt = #line) async -> AvatarGenerator.Failure? {
        do {
            _ = try await generate(transport)
            XCTFail("expected a failure", file: file, line: line)
            return nil
        } catch let failure as AvatarGenerator.Failure {
            return failure
        } catch {
            XCTFail("expected AvatarGenerator.Failure, got \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: - Request building

    func testRequestGoesToTheImageEditEndpointWithTheKeyAsBearer() async throws {
        let transport = ScriptedTransport([success(TestImages.characterPNG())])
        _ = try await generate(transport)
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/images/edits")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key-not-real")
        XCTAssertEqual(request.timeoutInterval, 180)
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary=sprout-"), contentType)
    }

    func testEveryMultipartFieldIsSentOnceWithItsValue() async throws {
        let transport = ScriptedTransport([success(TestImages.characterPNG())])
        _ = try await generate(transport)
        let parts = Multipart.parts(of: try XCTUnwrap(transport.requests.first))
        XCTAssertEqual(parts.map(\.name), ["model", "prompt", "background", "output_format", "size", "quality", "image"])
        func text(_ name: String) -> String? { parts.first { $0.name == name }?.text }
        XCTAssertEqual(text("model"), "gpt-image-2.6-flare")
        XCTAssertEqual(text("prompt"), AvatarGenerator.prompt)
        XCTAssertEqual(text("background"), "transparent")
        XCTAssertEqual(text("output_format"), "png")
        XCTAssertEqual(text("size"), "1024x1024")
        XCTAssertEqual(text("quality"), "medium")
        // The text fields are plain form fields: no filename, no content type.
        for part in parts where part.name != "image" {
            XCTAssertNil(part.filename, part.name)
            XCTAssertNil(part.contentType, part.name)
        }
    }

    func testThePhotoIsAttachedAsOneJPEGFilePart() async throws {
        let transport = ScriptedTransport([success(TestImages.characterPNG())])
        _ = try await generate(transport, photo: TestImages.photo(width: 200, height: 300))
        let parts = Multipart.parts(of: try XCTUnwrap(transport.requests.first))
        let images = parts.filter { $0.name == "image" }
        XCTAssertEqual(images.count, 1)
        let image = try XCTUnwrap(images.first)
        XCTAssertEqual(image.filename, "photo.jpg")
        XCTAssertEqual(image.contentType, "image/jpeg")
        XCTAssertEqual(Array(image.data.prefix(3)), [0xFF, 0xD8, 0xFF], "JPEG start-of-image marker")
        let size = try XCTUnwrap(TestImages.pixelSize(of: image.data))
        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, 300)
    }

    func testBuildRequestIsDeterministicForAGivenBoundary() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0x01, 0x02])
        let a = AvatarGenerator.buildRequest(photoJPEG: jpeg, key: "k", setting: setting, boundary: "b1")
        let b = AvatarGenerator.buildRequest(photoJPEG: jpeg, key: "k", setting: setting, boundary: "b1")
        XCTAssertEqual(a.httpBody, b.httpBody)
        XCTAssertEqual(Multipart.parts(of: a).last?.data, jpeg, "the file bytes are sent unchanged")
        let body = String(decoding: a.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.hasSuffix("\r\n--b1--\r\n"), "the body ends with the closing boundary")
    }

    func testModelAndQualityComeFromTheSetting() async throws {
        var other = setting
        other.model = "gpt-image-2.6-sunburst"
        other.quality = "high"
        let transport = ScriptedTransport([success(TestImages.characterPNG())])
        let character = try await AIRuntime.$current.withValue(runtime(transport)) {
            try await AvatarGenerator.generate(from: TestImages.photo(width: 64, height: 64), setting: other)
        }
        let parts = Multipart.parts(of: try XCTUnwrap(transport.requests.first))
        XCTAssertEqual(parts.first { $0.name == "model" }?.text, "gpt-image-2.6-sunburst")
        XCTAssertEqual(parts.first { $0.name == "quality" }?.text, "high")
        XCTAssertEqual(character.model, "gpt-image-2.6-sunburst")
        XCTAssertEqual(character.quality, "high")
    }

    func testAScopedModelOverridesTheSetting() async throws {
        let transport = ScriptedTransport([success(TestImages.characterPNG())])
        let character = try await generate(transport, model: "gpt-image-2.6-sunburst")
        let parts = Multipart.parts(of: try XCTUnwrap(transport.requests.first))
        XCTAssertEqual(parts.first { $0.name == "model" }?.text, "gpt-image-2.6-sunburst")
        XCTAssertEqual(character.model, "gpt-image-2.6-sunburst")
    }

    func testTheShippedSettingIsSunburstLowTransparentPNG1024() {
        XCTAssertEqual(AIConfig.avatarImage,
                       AIConfig.ImageSetting(model: "gpt-image-2.6-sunburst", quality: "low", size: "1024x1024",
                                             background: "transparent", outputFormat: "png"))
    }

    func testThePromptNamesTheStyleAndCarriesAVersion() {
        XCTAssertEqual(AvatarGenerator.promptVersion, "avatar-v1")
        let prompt = AvatarGenerator.prompt.lowercased()
        for phrase in ["pixel-art", "head-and-shoulders", "facing straight", "12 to 16 colours",
                       "no outline", "fully transparent", "no anti-aliasing", "32 by 32"] {
            XCTAssertTrue(prompt.contains(phrase), "the prompt no longer says \"\(phrase)\"")
        }
    }

    // MARK: - No key

    func testNoKeyIsATypedErrorAndNoRequestIsMade() async {
        let transport = ScriptedTransport([success(TestImages.characterPNG())])
        do {
            _ = try await generate(transport, key: "")
            XCTFail("expected missingKey")
        } catch {
            XCTAssertEqual(error as? AvatarGenerator.Failure, .missingKey)
        }
        XCTAssertTrue(transport.requests.isEmpty, "a request was built without a key")
    }

    func testImageKeyGateFollowsTheScopedKey() {
        AIRuntime.$current.withValue(AIRuntime(apiKey: "")) { XCTAssertFalse(AIConfig.hasImageKey) }
        AIRuntime.$current.withValue(AIRuntime(apiKey: "k")) { XCTAssertTrue(AIConfig.hasImageKey) }
    }

    // MARK: - Success

    func testSuccessReturnsTheDecodedCharacterAndItsUsage() async throws {
        let png = TestImages.characterPNG(side: 64)
        let recorder = UsageRecorder()
        let transport = ScriptedTransport([success(png, usage: [
            "input_tokens": 1_210, "input_tokens_details": ["image_tokens": 900, "text_tokens": 310],
            "output_tokens": 4_160, "total_tokens": 5_370,
        ])])
        let character = try await generate(transport, usage: recorder)
        XCTAssertEqual(character.png, png)
        XCTAssertEqual(character.pixelSize, 64)
        XCTAssertEqual(character.model, "gpt-image-2.6-flare")
        XCTAssertEqual(character.quality, "medium")
        XCTAssertEqual(character.promptVersion, "avatar-v1")
        XCTAssertEqual(character.usage, AvatarGenerator.Usage(inputTokens: 1_210, inputTextTokens: 310,
                                                               inputImageTokens: 900, outputTokens: 4_160,
                                                               totalTokens: 5_370))
        XCTAssertEqual(recorder.all.count, 1)
        let reported = try XCTUnwrap(recorder.all.first)
        XCTAssertEqual(reported.provider, .openai)
        XCTAssertEqual(reported.model, "gpt-image-2.6-flare")
        XCTAssertEqual(reported.endpoint, "/v1/images/edits")
        XCTAssertEqual(reported.uncachedInputTokens, 1_210)
        XCTAssertEqual(reported.outputTokens, 4_160)
        XCTAssertEqual(reported.cacheReadTokens, 0)
        XCTAssertEqual(reported.attempts, 1)
    }

    func testAResponseWithoutUsageReportsNone() async throws {
        let recorder = UsageRecorder()
        let transport = ScriptedTransport([success(TestImages.characterPNG())])
        let character = try await generate(transport, usage: recorder)
        XCTAssertNil(character.usage)
        XCTAssertTrue(recorder.all.isEmpty)
    }

    // MARK: - Provider errors

    func testHTTPErrorCarriesTheProvidersMessage() async {
        let transport = ScriptedTransport([.json(401, ["error": [
            "message": "Incorrect API key provided.", "type": "invalid_request_error", "code": "invalid_api_key",
        ]])])
        let failed = await failure(transport)
        XCTAssertEqual(failed, .http(status: 401, message: "Incorrect API key provided."))
        XCTAssertEqual(transport.requests.count, 1, "an auth failure is not retried")
    }

    func testHTTPErrorWithoutABodyNamesTheStatus() async {
        let transport = ScriptedTransport([ScriptedTransport.Reply(status: 404, body: Data("not json".utf8))])
        let failed = await failure(transport)
        XCTAssertEqual(failed, .http(status: 404, message: "HTTP 404"))
    }

    func testModerationBlockIsARefusalWithItsStage() async {
        let transport = ScriptedTransport([.json(400, ["error": [
            "message": "Your request was rejected by the safety system.",
            "type": "image_generation_user_error", "code": "moderation_blocked",
            "moderation_details": ["moderation_stage": "input", "categories": ["sexual"]],
        ]])])
        let failed = await failure(transport)
        XCTAssertEqual(failed, .refused(message: "Your request was rejected by the safety system.", stage: "input"))
        XCTAssertEqual(transport.requests.count, 1, "a refusal is never retried")
        XCTAssertEqual(failed?.isWorthRetrying, false)
    }

    func testAUserErrorThatIsNotModerationIsAnHTTPError() async {
        let transport = ScriptedTransport([.json(400, ["error": [
            "message": "The image could not be processed.", "type": "image_generation_user_error",
        ]])])
        let failed = await failure(transport)
        XCTAssertEqual(failed, .http(status: 400, message: "The image could not be processed."))
    }

    func testServerOverloadIsRetriedOnceThenSucceeds() async throws {
        let recorder = UsageRecorder()
        let transport = ScriptedTransport([
            .json(503, ["error": ["message": "The model is overloaded."]]),
            success(TestImages.characterPNG(), usage: ["input_tokens": 10, "output_tokens": 20, "total_tokens": 30]),
        ])
        let character = try await generate(transport, usage: recorder)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(character.usage?.outputTokens, 20)
        XCTAssertEqual(recorder.all.first?.attempts, 2)
    }

    func testSecondOverloadSurfacesTheProvidersMessage() async {
        let transport = ScriptedTransport([
            .json(503, ["error": ["message": "The model is overloaded."]]),
            .json(503, ["error": ["message": "Still overloaded."]]),
        ])
        let failed = await failure(transport)
        XCTAssertEqual(failed, .http(status: 503, message: "Still overloaded."))
        XCTAssertEqual(transport.requests.count, 2, "one retry, not more")
    }

    func testExhaustedQuotaIsNotRetried() async {
        let transport = ScriptedTransport([.json(429, ["error": [
            "message": "You exceeded your current quota.", "type": "insufficient_quota", "code": "insufficient_quota",
        ]])])
        let failed = await failure(transport)
        XCTAssertEqual(failed, .http(status: 429, message: "You exceeded your current quota."))
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testTransientRuleNamesExactlyTheRetryableStatuses() {
        let empty = Data("{}".utf8)
        XCTAssertTrue(AvatarGenerator.isTransient(status: 429, body: empty))
        XCTAssertTrue(AvatarGenerator.isTransient(status: 500, body: empty))
        XCTAssertTrue(AvatarGenerator.isTransient(status: 503, body: empty))
        XCTAssertFalse(AvatarGenerator.isTransient(status: 400, body: empty))
        XCTAssertFalse(AvatarGenerator.isTransient(status: 401, body: empty))
        let quota = Data(#"{"error":{"type":"insufficient_quota"}}"#.utf8)
        XCTAssertFalse(AvatarGenerator.isTransient(status: 429, body: quota))
    }

    func testANetworkFailureIsTyped() async {
        // An exhausted script throws from the transport, exactly as a dropped connection would.
        let failed = await failure(ScriptedTransport([]))
        guard case .network = failed else { return XCTFail("expected .network, got \(String(describing: failed))") }
    }

    // MARK: - Malformed responses

    func testBodyThatIsNotJSONIsMalformed() async {
        let transport = ScriptedTransport([ScriptedTransport.Reply(status: 200, body: Data("<html>".utf8))])
        let failed = await failure(transport)
        XCTAssertEqual(failed, .malformedResponse("the body is not a JSON object"))
    }

    func testMissingImageFieldIsMalformed() async {
        let transport = ScriptedTransport([.json(200, ["created": 1, "data": [["url": "https://example.invalid/x.png"]]])])
        let failed = await failure(transport)
        XCTAssertEqual(failed, .malformedResponse("missing data[0].b64_json"))
    }

    func testEmptyDataArrayIsMalformed() async {
        let failed = await failure(ScriptedTransport([.json(200, ["created": 1, "data": [[String: Any]]()])]))
        XCTAssertEqual(failed, .malformedResponse("missing data[0].b64_json"))
    }

    func testImageFieldThatIsNotBase64IsMalformed() async {
        let failed = await failure(ScriptedTransport([.json(200, ["data": [["b64_json": "@@@@"]]])]))
        XCTAssertEqual(failed, .malformedResponse("data[0].b64_json is not base64"))
    }

    // MARK: - Image validation

    func testBytesThatAreNotAnImageAreNotDecodable() async {
        let failed = await failure(ScriptedTransport([success(Data("not an image at all".utf8))]))
        XCTAssertEqual(failed, .imageNotDecodable)
    }

    func testAJPEGIsNotAccepted() async throws {
        let jpeg = try XCTUnwrap(TestImages.photo(width: 64, height: 64).jpegData(compressionQuality: 0.8))
        let failed = await failure(ScriptedTransport([success(jpeg)]))
        XCTAssertEqual(failed, .imageNotDecodable, "the character must be a PNG")
    }

    func testATruncatedPNGIsNotDecodable() async {
        let truncated = TestImages.characterPNG().prefix(40)
        let failed = await failure(ScriptedTransport([success(Data(truncated))]))
        XCTAssertEqual(failed, .imageNotDecodable)
    }

    func testANonSquareImageIsRejectedWithItsSize() async {
        let wide = TestImages.png(width: 96, height: 64, grid: TestImages.characterGrid, palette: TestImages.characterPalette)
        let failed = await failure(ScriptedTransport([success(wide)]))
        XCTAssertEqual(failed, .imageNotSquare(width: 96, height: 64))
    }

    func testAnImageWithNoAlphaChannelIsRejected() async {
        let opaque = TestImages.png(width: 64, height: 64, grid: TestImages.characterGrid,
                                    palette: TestImages.characterPalette, background: .white, opaque: true)
        let failed = await failure(ScriptedTransport([success(opaque)]))
        XCTAssertEqual(failed, .imageHasNoAlpha)
    }

    func testAnAlphaChannelWithAPaintedBackgroundIsRejected() async {
        // An alpha channel, but every pixel is opaque: the model painted a backdrop.
        let painted = TestImages.png(width: 64, height: 64, grid: TestImages.characterGrid,
                                     palette: TestImages.characterPalette, background: .white)
        XCTAssertNoThrow(try XCTUnwrap(AvatarImage.rgba(ofImageData: painted)))
        let failed = await failure(ScriptedTransport([success(painted)]))
        XCTAssertEqual(failed, .imageNotTransparent(transparentShare: 0))
    }

    func testValidationAcceptsTheGoodCharacterAndReportsItsSide() throws {
        XCTAssertEqual(try AvatarImage.validateCharacterPNG(TestImages.characterPNG(side: 128)), 128)
    }

    // MARK: - Fallback to a built-in character

    func testEveryFailureBecomesTheBuiltInCharacterForTheLook() async {
        let wide = TestImages.png(width: 96, height: 64, grid: TestImages.characterGrid, palette: TestImages.characterPalette)
        let opaque = TestImages.png(width: 64, height: 64, background: .white, opaque: true)
        let cases: [(name: String, key: String, replies: [ScriptedTransport.Reply], want: AvatarGenerator.Failure)] = [
            ("no key", "", [], .missingKey),
            ("http", "k", [.json(400, ["error": ["message": "bad"]])], .http(status: 400, message: "bad")),
            ("refusal", "k", [.json(400, ["error": ["message": "no", "code": "moderation_blocked"]])],
             .refused(message: "no", stage: nil)),
            ("malformed", "k", [.json(200, ["nothing": true])], .malformedResponse("missing data[0].b64_json")),
            ("undecodable", "k", [success(Data([1, 2, 3]))], .imageNotDecodable),
            ("not square", "k", [success(wide)], .imageNotSquare(width: 96, height: 64)),
            ("no alpha", "k", [success(opaque)], .imageHasNoAlpha),
        ]
        for item in cases {
            for (theme, builtIn) in [(ThemeStyle.cool, CompanionAvatar.bryan), (.cute, .cute)] {
                let transport = ScriptedTransport(item.replies)
                let outcome = await AIRuntime.$current.withValue(runtime(transport, key: item.key)) {
                    await AvatarGenerator.outcome(for: TestImages.photo(width: 64, height: 64), theme: theme,
                                                  setting: self.setting)
                }
                XCTAssertEqual(outcome, .builtIn(builtIn, because: item.want), "\(item.name), \(theme)")
            }
        }
    }

    func testAGoodResponseIsACustomOutcome() async {
        let png = TestImages.characterPNG()
        let outcome = await AIRuntime.$current.withValue(runtime(ScriptedTransport([success(png)]))) {
            await AvatarGenerator.outcome(for: TestImages.photo(width: 64, height: 64), theme: .cool, setting: self.setting)
        }
        guard case .custom(let character) = outcome else { return XCTFail("expected .custom, got \(outcome)") }
        XCTAssertEqual(character.png, png)
    }

    // MARK: - Input downscale

    func testALargePhotoIsShrunkToALongestSideOf1024() throws {
        let landscape = try XCTUnwrap(AvatarImage.uploadJPEG(from: TestImages.photo(width: 3000, height: 2000)))
        let l = try XCTUnwrap(TestImages.pixelSize(of: landscape))
        XCTAssertEqual(l.width, 1024)
        XCTAssertEqual(l.height, 683)

        let portrait = try XCTUnwrap(AvatarImage.uploadJPEG(from: TestImages.photo(width: 1500, height: 4000)))
        let p = try XCTUnwrap(TestImages.pixelSize(of: portrait))
        XCTAssertEqual(p.width, 384)
        XCTAssertEqual(p.height, 1024)
    }

    func testASmallPhotoIsNotEnlarged() throws {
        let data = try XCTUnwrap(AvatarImage.uploadJPEG(from: TestImages.photo(width: 400, height: 300)))
        let size = try XCTUnwrap(TestImages.pixelSize(of: data))
        XCTAssertEqual(size.width, 400)
        XCTAssertEqual(size.height, 300)
    }

    func testDownscaleCountsPixelsNotPoints() throws {
        // A 3x image of 1000x1000 points is 3000x3000 pixels: it must still be shrunk.
        let retina = TestImages.photo(width: 3000, height: 3000, scale: 3)
        XCTAssertEqual(retina.size.width, 1000)
        let data = try XCTUnwrap(AvatarImage.uploadJPEG(from: retina))
        let size = try XCTUnwrap(TestImages.pixelSize(of: data))
        XCTAssertEqual(size.width, 1024)
        XCTAssertEqual(size.height, 1024)
    }

    func testTheUploadDropsTheCamerasLocationAndDeviceMetadata() throws {
        // A photo as a camera writes it: pixels plus an EXIF block with a location and a device.
        let pixels = try XCTUnwrap(TestImages.photo(width: 2000, height: 1000).cgImage)
        let tagged = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(tagged, "public.jpeg" as CFString, 1, nil))
        let metadata: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 122.25, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "TestCam", kCGImagePropertyTIFFModel: "Model 1"],
        ]
        CGImageDestinationAddImage(destination, pixels, metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        func properties(_ data: Data) throws -> [CFString: Any] {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        }
        func make(_ props: [CFString: Any]) -> String? {
            (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String
        }
        // Control: the input really carries both, so the assertions below can fail.
        let before = try properties(tagged as Data)
        XCTAssertNotNil(before[kCGImagePropertyGPSDictionary])
        XCTAssertEqual(make(before), "TestCam")

        let photo = try XCTUnwrap(UIImage(data: tagged as Data))
        let upload = try XCTUnwrap(AvatarImage.uploadJPEG(from: photo))
        XCTAssertEqual(Array(upload.prefix(3)), [0xFF, 0xD8, 0xFF])
        let after = try properties(upload)
        XCTAssertNil(after[kCGImagePropertyGPSDictionary], "the location was uploaded")
        XCTAssertNil(make(after), "the camera make was uploaded")
        let size = try XCTUnwrap(TestImages.pixelSize(of: upload))
        XCTAssertEqual(size.width, 1024)
        XCTAssertEqual(size.height, 512)
    }

    func testTheGeneratorUploadsTheShrunkPhoto() async throws {
        let transport = ScriptedTransport([success(TestImages.characterPNG())])
        _ = try await generate(transport, photo: TestImages.photo(width: 2048, height: 4096))
        let image = try XCTUnwrap(Multipart.parts(of: try XCTUnwrap(transport.requests.first)).first { $0.name == "image" })
        let size = try XCTUnwrap(TestImages.pixelSize(of: image.data))
        XCTAssertEqual(size.width, 512)
        XCTAssertEqual(size.height, 1024)
    }
}
