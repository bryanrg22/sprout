import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The custom character, as the widget sees it.
///
/// The widget runs in another process and cannot open the SwiftData store, so the app
/// writes a small copy of the character PNG into the shared App Group container, next to
/// the widget snapshot, and the widget reads it from there.
///
/// Two rules, both enforced here rather than at the call sites:
///
/// 1. **A widget never shows a different person's character.** The snapshot names the
///    exact bytes it expects (`WidgetSnapshot.companionAvatarDigest`, a SHA-256 of this
///    file). A file left behind by another profile (a store wipe, a restore, a different
///    iCloud account) does not match, and is not drawn.
/// 2. **A missing or unreadable file is a neutral state**, never a built-in character and
///    never sample art (`WidgetCompanionArt.neutral`).
///
/// The file is written with the container's default protection (readable after the first
/// unlock), unlike `widget_appearance.json`: it is a likeness of a person, and before the
/// first unlock the widget has no snapshot either, so it draws `WidgetUnavailableView`,
/// which shows no companion at all.
///
/// Shared by BOTH the app target (writes) and the widget extension (reads).
enum WidgetAvatarFile {
    static let fileName = "widget_avatar.png"
    /// Beside the image: the digest of the full-size PNG it was made from, so the app does
    /// not decode and re-encode the character on every widget refresh.
    static let sourceMarkerName = "widget_avatar.source"
    /// Longest side of the widget copy, in pixels. The largest place a widget draws the
    /// companion is 92 pt wide (276 px at 3x); WidgetKit also refuses very large images.
    static let maxEdge = 320

    static var defaultDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSharedStore.appGroup)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Make the directory hold exactly the widget copy of `sourcePNG` (or nothing, when
    /// it is nil), and return the digest the snapshot must carry. Returns nil when there is
    /// no custom character or the copy could not be made; the widget then draws neutral.
    @discardableResult
    static func sync(sourcePNG: Data?, in directory: URL?) -> String? {
        guard let directory else { return nil }
        let file = directory.appendingPathComponent(fileName)
        let marker = directory.appendingPathComponent(sourceMarkerName)
        guard let sourcePNG else {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: marker)
            return nil
        }
        let source = digest(sourcePNG)
        if let recorded = try? String(contentsOf: marker, encoding: .utf8), recorded == source,
           let existing = try? Data(contentsOf: file) {
            return digest(existing)
        }
        guard let small = downscaledPNG(sourcePNG, maxEdge: maxEdge) else {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: marker)
            return nil
        }
        do {
            try small.write(to: file, options: .atomic)
            try Data(source.utf8).write(to: marker, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: marker)
            return nil
        }
        return digest(small)
    }

    /// The widget copy, only when it is the one the snapshot names.
    static func read(expectedDigest: String?, in directory: URL?) -> Data? {
        guard let expectedDigest, !expectedDigest.isEmpty, let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              digest(data) == expectedDigest else { return nil }
        return data
    }

    /// A PNG no larger than `maxEdge` on its longest side, alpha kept. Never upscales.
    static func downscaledPNG(_ png: Data, maxEdge: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}

/// What a widget draws where the companion goes.
enum WidgetCompanionArt: Equatable {
    /// One of the two hand-drawn characters, by its stored raw value.
    case builtIn(raw: String)
    /// The person's own character: the PNG bytes of the verified widget copy.
    case custom(Data)
    /// Nothing about anyone: the custom image is missing, is not the one the snapshot
    /// names, or the stored value is one this build does not know.
    case neutral

    /// The raw values of the two built-in characters (`CompanionAvatar`, app target).
    static let builtInRawValues: Set<String> = ["victoria", "bryan"]
    static let customRawValue = "custom"

    /// Pure: `file` is whatever `WidgetAvatarFile.read` returned for this snapshot.
    static func resolve(raw: String, file: Data?) -> WidgetCompanionArt {
        if builtInRawValues.contains(raw) { return .builtIn(raw: raw) }
        if raw == customRawValue, let file { return .custom(file) }
        return .neutral
    }
}
