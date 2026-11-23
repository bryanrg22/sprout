#if DEBUG
import SwiftUI
import UIKit

/// DEBUG-only hooks so the character flow can be driven and screenshotted in the
/// simulator with no network, no key and no real photo. Compiled out of Release.
///
///   --avatar-stub success   the call returns a locally drawn sample character
///   --avatar-stub refusal   the call is blocked by moderation
///   --avatar-stub failure   the call fails with a server error
///   --avatar-stub slow      the call never answers (the "drawing" state)
///   --avatar-stub nokey     behave as though no OpenAI key is stored
///   --avatar-sample-photo   start with a drawn sample photo picked and consent ticked
///   --avatar-autostart      press "Make my character" as soon as the step appears
///   --avatar-accept         with autostart: also press "Use this" on the preview
///
/// The stub answers through `AIRuntime`, so the shipped request building, response
/// parsing and image validation all run; only the HTTP exchange is replaced.
enum AvatarDebug {
    private static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var mode: String? { value(after: "--avatar-stub") }
    static var wantsSamplePhoto: Bool { CommandLine.arguments.contains("--avatar-sample-photo") }
    static var wantsAutostart: Bool { CommandLine.arguments.contains("--avatar-autostart") }
    static var wantsAccept: Bool { CommandLine.arguments.contains("--avatar-accept") }

    /// nil = ask the Keychain as usual.
    static var hasKeyOverride: Bool? {
        guard let mode else { return nil }
        return mode != "nokey"
    }

    static var stubRuntime: AIRuntime? {
        guard let mode, mode != "nokey" else { return nil }
        return AIRuntime(provider: .openai, apiKey: "debug-stub-not-a-key", transport: StubTransport(mode: mode))
    }

    private struct StubTransport: AITransport {
        let mode: String

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            func reply(_ status: Int, _ object: [String: Any]) -> (Data, URLResponse) {
                let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
                return (data, HTTPURLResponse(url: request.url!, statusCode: status,
                                              httpVersion: "HTTP/1.1", headerFields: nil)!)
            }
            switch mode {
            case "refusal":
                try await Task.sleep(for: .seconds(1))
                return reply(400, ["error": ["message": "Your request was rejected by the safety system.",
                                             "type": "image_generation_user_error",
                                             "code": "moderation_blocked",
                                             "moderation_details": ["moderation_stage": "input"]]])
            case "failure":
                try await Task.sleep(for: .seconds(1))
                return reply(400, ["error": ["message": "The image could not be processed.",
                                             "type": "invalid_request_error"]])
            case "slow":
                try await Task.sleep(for: .seconds(600))
                throw URLError(.timedOut)
            default:
                try await Task.sleep(for: .seconds(1))
                return reply(200, ["created": 0,
                                   "data": [["b64_json": sampleCharacterPNG().base64EncodedString()]],
                                   "usage": ["input_tokens": 0, "output_tokens": 0, "total_tokens": 0]])
            }
        }
    }

    // MARK: Sample art (drawn here; no asset ships for this)

    /// A made-up character on a 16×16 grid, in the built-in characters' style. Nobody's likeness.
    private static let sampleGrid: [String] = [
        "................",
        "....HHHHHHHH....",
        "...HHhHHHHhHH...",
        "..HHHHHHHHHHHH..",
        "..HHSSSSSSSSHH..",
        "..HSSSSSSSSSSH..",
        "..HSbbSSSSbbSH..",
        "..HSWESSSSWESH..",
        "..HSSSSSSSSSSH..",
        "..HSCSSMMSSCSH..",
        "...SSSSSSSSSS...",
        "....SSSSSSSS....",
        ".....KSSSSK.....",
        "..TTTTTTTTTTTT..",
        ".TTTTTtTTtTTTTT.",
        "TTTTTTTTTTTTTTTT",
    ]

    private static let samplePalette: [Character: UIColor] = [
        "H": UIColor(red: 0.55, green: 0.27, blue: 0.16, alpha: 1),   // auburn hair
        "h": UIColor(red: 0.72, green: 0.40, blue: 0.24, alpha: 1),   // hair highlight
        "S": UIColor(red: 0.93, green: 0.76, blue: 0.62, alpha: 1),   // skin
        "K": UIColor(red: 0.82, green: 0.63, blue: 0.50, alpha: 1),   // skin shadow
        "b": UIColor(red: 0.40, green: 0.20, blue: 0.12, alpha: 1),   // brows
        "E": UIColor(red: 0.13, green: 0.10, blue: 0.10, alpha: 1),   // eyes
        "W": UIColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1),   // catch-light
        "C": UIColor(red: 0.95, green: 0.60, blue: 0.58, alpha: 1),   // blush
        "M": UIColor(red: 0.62, green: 0.28, blue: 0.27, alpha: 1),   // mouth
        "T": UIColor(red: 0.16, green: 0.55, blue: 0.55, alpha: 1),   // teal top
        "t": UIColor(red: 0.11, green: 0.43, blue: 0.44, alpha: 1),   // top shadow
    ]

    /// The sample character as a 1024×1024 PNG with a transparent background.
    static func sampleCharacterPNG(side: CGFloat = 1024) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let cell = side / CGFloat(sampleGrid.count)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { context in
            for (r, row) in sampleGrid.enumerated() {
                for (c, ch) in row.enumerated() {
                    guard let color = samplePalette[ch] else { continue }
                    color.setFill()
                    context.fill(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell))
                }
            }
        }
    }

    /// A stand-in for a picked photo: soft shapes, nobody's face.
    static func samplePhoto() -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colors = [UIColor(red: 0.42, green: 0.60, blue: 0.72, alpha: 1).cgColor,
                          UIColor(red: 0.80, green: 0.86, blue: 0.84, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            UIColor(red: 0.16, green: 0.55, blue: 0.55, alpha: 1).setFill()      // shoulders
            cg.fillEllipse(in: CGRect(x: 110, y: 820, width: 680, height: 640))
            UIColor(red: 0.93, green: 0.76, blue: 0.62, alpha: 1).setFill()      // neck + head
            cg.fill(CGRect(x: 380, y: 700, width: 140, height: 180))
            cg.fillEllipse(in: CGRect(x: 270, y: 300, width: 360, height: 440))
            UIColor(red: 0.55, green: 0.27, blue: 0.16, alpha: 1).setFill()      // hair
            cg.fillEllipse(in: CGRect(x: 250, y: 250, width: 400, height: 260))
        }
    }
}
#endif
