import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Makes a person's own pixel character from a photo of them: one call to OpenAI's image
/// EDIT endpoint, with the photo as the reference image.
///
/// What the documentation did and did not confirm about every field below is written up,
/// with sources, in `docs/avatar-generation.md`. A wire name the documentation shows only
/// in an example, or does not state for the 2.6 models, is a constant in `Wire` so a
/// correction is a one-line change.
///
/// Decisions already made by the owner (do not re-litigate here):
/// 1. Version 1 makes ONE character image per person, no per-mood frames.
/// 2. The photo is sent to OpenAI only after an explicit consent step (the UI's job:
///    `AvatarCreationModel`), and the photo itself is never stored: this type holds it in
///    memory for the duration of the call and writes nothing to disk.
/// 3. With no OpenAI key, a refusal, a network failure or a bad response, the caller
///    continues with a built-in character (`outcome(for:)`); nothing here can block.
///
/// Image generation is OpenAI-only (Anthropic's models do not produce images), so this
/// always uses the OpenAI key, whatever provider the user picked for chat. It deliberately
/// does not go through `AIClient.make()`, which builds the ACTIVE provider's chat client.
enum AvatarGenerator {

    // MARK: - Wire names (see docs/avatar-generation.md)

    enum Wire {
        static let endpoint = URL(string: "https://api.openai.com/v1/images/edits")!

        // Multipart field names. `model`, `prompt`, `quality` and a single `image` file part
        // are shown in the image-generation guide's curl example for `gpt-image-2.6-flare`;
        // `background`, `output_format` and `size` are documented request parameters of the
        // endpoint (the reference lists them for the JSON body; the guide's multipart
        // examples do not happen to use them).
        static let model = "model"
        static let prompt = "prompt"
        /// The guide uses `image` for one input file and `image[]` for several.
        static let image = "image"
        static let background = "background"
        static let outputFormat = "output_format"
        static let size = "size"
        static let quality = "quality"

        static let imageFilename = "photo.jpg"
        static let imageContentType = "image/jpeg"

        /// `error.code` of a moderation block, the one discriminator the guide names.
        static let moderationBlockedCode = "moderation_blocked"
        /// `error.code` / `error.type` of an exhausted quota: retrying cannot help.
        static let quotaExhausted = "insufficient_quota"

        /// The guide: "Complex prompts may take up to 2 minutes to process."
        static let timeout: TimeInterval = 180
    }

    // MARK: - The prompt

    /// Bump when the wording changes, so an evaluation record says which prompt made an image.
    static let promptVersion = "avatar-v1"

    /// Describes the style of the app's two hand-made characters (`PixelCute` and
    /// `PixelBryan` in `PixelCompanion.swift`, 20x24-cell grids, and the generated
    /// `alejandro_base` asset): a front-facing head-and-shoulders bust in a small flat
    /// palette, no outline, no shading beyond one shadow tone, on nothing.
    static let prompt = """
    Turn the person in this photo into a pixel-art character portrait for a mobile app. \
    It must match the style of the app's existing characters exactly:

    FRAMING: a head-and-shoulders bust of this one person only, facing straight at the \
    viewer, centred, upright and symmetrical in pose. The head (with hair) fills roughly \
    the top two thirds of the picture; the shoulders and upper chest fill the bottom third \
    and are cut off by the bottom edge. Nothing else is in the picture: no hands, no \
    props, no second person, no scenery.

    PIXELS: true low-resolution pixel art on a coarse grid of about 32 by 32 cells, each \
    cell one flat square of a single colour, every edge aligned to the grid. No \
    anti-aliasing, no gradients, no dithering, no blur, no glow, no texture.

    COLOUR: a small flat palette of 12 to 16 colours in total. Skin is one base tone plus \
    one slightly darker shadow tone; hair is one base tone plus one highlight tone; the \
    top is one colour plus one shadow tone. Warm, natural colours taken from the photo.

    OUTLINE: no outline at all. Shapes are separated only by blocks of colour.

    FACE: simple and friendly. Each eye is a dark pupil two cells tall with a single \
    white catch-light cell beside it; eyebrows are short solid bars in the hair colour; \
    the mouth is a small closed smile three or four cells wide; no nose line beyond at \
    most one shadow cell. Calm, kind expression.

    LIKENESS: keep what makes this person recognisable: hair style, hair length and hair \
    colour, skin tone, facial hair, glasses, and one or two signature accessories such as \
    a necklace or earrings, each reduced to a few cells. Dress them in a plain solid top \
    in the colour they are wearing, with no logo and no lettering.

    BACKGROUND: fully transparent everywhere outside the character. No backdrop, no \
    floor, no frame, no border, no drop shadow, no text, no watermark.
    """

    // MARK: - Results

    /// Token accounting of one image call, as the response reports it. Image input and
    /// text input are priced differently, so they are kept apart here (`AIUsage`, which
    /// this also reports through, has one input bucket).
    struct Usage: Equatable, Sendable {
        var inputTokens: Int
        var inputTextTokens: Int
        var inputImageTokens: Int
        var outputTokens: Int
        var totalTokens: Int
    }

    /// A character that passed validation.
    struct Character: Equatable, Sendable {
        /// A square PNG with a transparent background.
        var png: Data
        var pixelSize: Int
        var model: String
        var quality: String
        var promptVersion: String
        /// nil when the response carried no `usage` block.
        var usage: Usage?
        var latencyMs: Int
    }

    /// Every way this can fail, each of which the caller answers with a built-in character.
    enum Failure: Error, Equatable, LocalizedError {
        /// No OpenAI key is stored. Thrown before any request is built.
        case missingKey
        /// The photo could not be read or encoded for upload.
        case unreadablePhoto
        /// The request never got an HTTP answer (offline, timed out, cancelled).
        case network(String)
        /// OpenAI answered with an error; `message` is its own `error.message`.
        case http(status: Int, message: String)
        /// OpenAI's moderation blocked the photo, the prompt or the result.
        case refused(message: String, stage: String?)
        /// A success status whose body is not the documented shape.
        case malformedResponse(String)
        /// The returned bytes are not a PNG that decodes.
        case imageNotDecodable
        case imageNotSquare(width: Int, height: Int)
        /// The PNG has no alpha channel.
        case imageHasNoAlpha
        /// The PNG has an alpha channel but (almost) nothing in it is transparent: the
        /// model painted a background, which would show as a square behind the character.
        case imageNotTransparent(transparentShare: Double)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "This needs an OpenAI key."
            case .unreadablePhoto:
                return "That photo couldn't be read. Try another one."
            case .network:
                return "Couldn't reach OpenAI. Check your connection and try again."
            case .http(_, let message):
                return "OpenAI couldn't make the character: \(message)"
            case .refused:
                return "OpenAI declined to make a character from this photo. Try a different photo, or use a built-in character."
            case .malformedResponse, .imageNotDecodable, .imageNotSquare, .imageHasNoAlpha, .imageNotTransparent:
                return "The character didn't come out right this time. Try again, or use a built-in character."
            }
        }

        /// Whether asking again with the same photo could plausibly work.
        var isWorthRetrying: Bool {
            switch self {
            case .missingKey, .unreadablePhoto, .refused: return false
            case .network, .http, .malformedResponse, .imageNotDecodable, .imageNotSquare,
                 .imageHasNoAlpha, .imageNotTransparent: return true
            }
        }
    }

    /// What onboarding or Settings ends up with. There is no third case: a failure IS a
    /// built-in character, which is what keeps the flow from ever getting stuck.
    enum Outcome: Equatable {
        case custom(Character)
        case builtIn(CompanionAvatar, because: Failure)
    }

    /// Never throws: every failure becomes the built-in character that goes with `theme`.
    static func outcome(for photo: UIImage, theme: ThemeStyle,
                        setting: AIConfig.ImageSetting = AIConfig.avatarImage) async -> Outcome {
        do {
            return .custom(try await generate(from: photo, setting: setting))
        } catch let failure as Failure {
            return .builtIn(.builtIn(for: theme), because: failure)
        } catch {
            return .builtIn(.builtIn(for: theme), because: .network(error.localizedDescription))
        }
    }

    // MARK: - The call

    /// The key the image call carries: a scoped runtime's (tests, evaluations), else the
    /// built-in gateway's (`AIConfig.key(for:)`).
    static func apiKey() -> String? { AIConfig.key(for: .openai) }

    /// One image from one photo. Throws `Failure`.
    static func generate(from photo: UIImage,
                         setting: AIConfig.ImageSetting = AIConfig.avatarImage) async throws -> Character {
        // The key is checked first, so a person without one costs no work and no request.
        guard let key = apiKey() else { throw Failure.missingKey }
        guard let jpeg = AvatarImage.uploadJPEG(from: photo) else { throw Failure.unreadablePhoto }

        let model = AIRuntime.resolve(model: setting.model)
        var resolved = setting
        resolved.model = model
        let request = buildRequest(photoJPEG: jpeg, key: key, setting: resolved,
                                   boundary: "sprout-\(UUID().uuidString)")

        let transport = AIRuntime.transport
        let started = Date()
        var attempt = 0
        while true {
            attempt += 1
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await transport.data(for: request)
            } catch {
                Diagnostics.shared.log("avatar: no response (\(error.localizedDescription))", .ai)
                throw Failure.network(error.localizedDescription)
            }
            guard let http = response as? HTTPURLResponse else { throw Failure.network("no HTTP response") }
            let latency = Int(Date().timeIntervalSince(started) * 1000)

            if (200..<300).contains(http.statusCode) {
                let parsed = try parseSuccess(data)
                let pixelSize = try AvatarImage.validateCharacterPNG(parsed.png)
                if let usage = parsed.usage {
                    Diagnostics.shared.log("avatar usage: in \(usage.inputTokens) (image \(usage.inputImageTokens)) out \(usage.outputTokens)", .ai)
                    AIRuntime.report(AIUsage(provider: .openai, model: model, endpoint: Wire.endpoint.path,
                                             uncachedInputTokens: usage.inputTokens, cacheReadTokens: 0,
                                             cacheWriteTokens: 0, outputTokens: usage.outputTokens,
                                             latencyMs: latency, attempts: attempt))
                }
                return Character(png: parsed.png, pixelSize: pixelSize, model: model,
                                 quality: resolved.quality, promptVersion: promptVersion,
                                 usage: parsed.usage, latencyMs: latency)
            }

            let failure = parseFailure(status: http.statusCode, body: data)
            Diagnostics.shared.log("avatar HTTP \(http.statusCode): \(failure)", .ai)
            if attempt == 1, isTransient(status: http.statusCode, body: data) {
                try? await Task.sleep(for: retryDelay)
                continue
            }
            throw failure
        }
    }

    /// Pause before the single retry of a transient failure.
    static var retryDelay: Duration = .milliseconds(700)

    // MARK: - Request building (pure)

    /// The multipart request for one photo. Pure, so a test can read every part of it.
    static func buildRequest(photoJPEG: Data, key: String, setting: AIConfig.ImageSetting,
                             boundary: String) -> URLRequest {
        var request = URLRequest(url: Wire.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Wire.timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func text(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        text(Wire.model, setting.model)
        text(Wire.prompt, prompt)
        text(Wire.background, setting.background)
        text(Wire.outputFormat, setting.outputFormat)
        text(Wire.size, setting.size)
        text(Wire.quality, setting.quality)
        body.append(Data(("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Wire.image)\"; "
                          + "filename=\"\(Wire.imageFilename)\"\r\nContent-Type: \(Wire.imageContentType)\r\n\r\n").utf8))
        body.append(photoJPEG)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }

    // MARK: - Response handling (pure)

    /// `data[0].b64_json` and the optional `usage` block of a success response.
    static func parseSuccess(_ data: Data) throws -> (png: Data, usage: Usage?) {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Failure.malformedResponse("the body is not a JSON object")
        }
        guard let first = (json["data"] as? [[String: Any]])?.first,
              let encoded = first["b64_json"] as? String, !encoded.isEmpty else {
            throw Failure.malformedResponse("missing data[0].b64_json")
        }
        guard let png = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), !png.isEmpty else {
            throw Failure.malformedResponse("data[0].b64_json is not base64")
        }
        var usage: Usage?
        if let u = json["usage"] as? [String: Any] {
            let details = u["input_tokens_details"] as? [String: Any]
            let input = (u["input_tokens"] as? Int) ?? 0
            let output = (u["output_tokens"] as? Int) ?? 0
            usage = Usage(inputTokens: input,
                          inputTextTokens: (details?["text_tokens"] as? Int) ?? 0,
                          inputImageTokens: (details?["image_tokens"] as? Int) ?? 0,
                          outputTokens: output,
                          totalTokens: (u["total_tokens"] as? Int) ?? (input + output))
        }
        return (png, usage)
    }

    /// The typed failure for an error status. The body is `{ "error": { "message", "type",
    /// "code", "moderation_details": { "moderation_stage" } } }`.
    static func parseFailure(status: Int, body: Data) -> Failure {
        let error = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? [String: Any]
        let message = (error?["message"] as? String) ?? "HTTP \(status)"
        if (error?["code"] as? String) == Wire.moderationBlockedCode {
            let stage = (error?["moderation_details"] as? [String: Any])?["moderation_stage"] as? String
            return .refused(message: message, stage: stage)
        }
        return .http(status: status, message: message)
    }

    /// Worth one automatic retry: a rate limit that is not an exhausted quota, or a server
    /// error. The guide: retry transient rate-limit and server errors with backoff, never
    /// quota errors or user errors.
    static func isTransient(status: Int, body: Data) -> Bool {
        guard [429, 500, 503].contains(status) else { return false }
        let error = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? [String: Any]
        let code = error?["code"] as? String
        let type = error?["type"] as? String
        return code != Wire.quotaExhausted && type != Wire.quotaExhausted
    }
}

/// The pixel work around `AvatarGenerator`: shrinking the photo before it is uploaded, and
/// checking that what came back is a character the app can draw.
enum AvatarImage {
    /// Longest side of the uploaded photo, in pixels. A face does not need more, and a
    /// smaller upload is fewer image input tokens.
    static let uploadMaxEdge: CGFloat = 1024
    static let uploadJPEGQuality: CGFloat = 0.85
    /// A character needs at least this share of fully transparent pixels: a bust on a
    /// transparent background leaves far more than this, a painted background leaves none.
    static let minimumTransparentShare = 0.02

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// The photo as a JPEG whose longest side is at most `maxEdge` pixels (never upscaled),
    /// upright, and re-encoded from pixels alone: the camera's EXIF block (location, device,
    /// time) is not carried into what is uploaded.
    static func uploadJPEG(from photo: UIImage, maxEdge: CGFloat = uploadMaxEdge,
                           quality: CGFloat = uploadJPEGQuality) -> Data? {
        let pixels = CGSize(width: photo.size.width * photo.scale, height: photo.size.height * photo.scale)
        let longest = max(pixels.width, pixels.height)
        guard longest >= 1 else { return nil }
        let scale = min(1, maxEdge / longest)
        let target = CGSize(width: max(1, (pixels.width * scale).rounded()),
                            height: max(1, (pixels.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            photo.draw(in: CGRect(origin: .zero, size: target))   // applies the orientation
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    /// Checks a returned character and gives its side length in pixels. Throws the
    /// `AvatarGenerator.Failure` that names what is wrong.
    @discardableResult
    static func validateCharacterPNG(_ data: Data) throws -> Int {
        guard data.count > pngSignature.count, Array(data.prefix(pngSignature.count)) == pngSignature,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0 else {
            throw AvatarGenerator.Failure.imageNotDecodable
        }
        guard image.width == image.height else {
            throw AvatarGenerator.Failure.imageNotSquare(width: image.width, height: image.height)
        }
        guard hasAlphaChannel(image) else { throw AvatarGenerator.Failure.imageHasNoAlpha }
        guard let pixels = rgba(of: image) else { throw AvatarGenerator.Failure.imageNotDecodable }
        let share = pixels.transparentShare
        guard share >= minimumTransparentShare else {
            throw AvatarGenerator.Failure.imageNotTransparent(transparentShare: share)
        }
        return image.width
    }

    static func hasAlphaChannel(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: return true
        @unknown default: return false
        }
    }

    /// An image's pixels as RGBA bytes (premultiplied, sRGB), for counting and grading.
    struct Pixels {
        let width: Int
        let height: Int
        /// `width * height * 4` bytes, row by row from the top.
        let bytes: [UInt8]

        func alpha(x: Int, y: Int) -> UInt8 { bytes[(y * width + x) * 4 + 3] }

        /// Share of pixels whose alpha is exactly 0.
        var transparentShare: Double {
            let total = width * height
            guard total > 0 else { return 0 }
            var clear = 0
            var index = 3
            while index < bytes.count {
                if bytes[index] == 0 { clear += 1 }
                index += 4
            }
            return Double(clear) / Double(total)
        }
    }

    static func rgba(of image: CGImage) -> Pixels? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Pixels(width: width, height: height, bytes: bytes) : nil
    }

    static func rgba(ofImageData data: Data) -> Pixels? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return rgba(of: image)
    }
}
