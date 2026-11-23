import XCTest
import SwiftUI
@testable import Victoria

/// G8 (e): where the custom character is kept and how each place that draws the companion
/// decides what to draw. The avatar's stored raw values, the profile's resolution of them,
/// and the widget's copy of the image in the App Group container.
final class AvatarStorageTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-widget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    // MARK: - The stored raw values

    func testRawValuesAreStable() {
        // These strings are in every existing profile, in iCloud and in widget snapshots.
        XCTAssertEqual(CompanionAvatar.victoria.rawValue, "victoria")
        XCTAssertEqual(CompanionAvatar.bryan.rawValue, "bryan")
        XCTAssertEqual(CompanionAvatar.custom.rawValue, "custom")
        XCTAssertEqual(CompanionAvatar.allCases.map(\.rawValue), ["victoria", "bryan", "custom"])
        XCTAssertEqual(CompanionAvatar.builtIns, [.victoria, .bryan])
        XCTAssertEqual(CompanionAvatar.allCases.filter(\.isBuiltIn), CompanionAvatar.builtIns)
        XCTAssertEqual(WidgetCompanionArt.builtInRawValues, Set(CompanionAvatar.builtIns.map(\.rawValue)))
        XCTAssertEqual(WidgetCompanionArt.customRawValue, CompanionAvatar.custom.rawValue)
    }

    func testAnUnknownStoredValueResolvesToABuiltInCharacter() {
        for raw in ["", "panda", "CUSTOM", "custom2", "  bryan"] {
            for hasImage in [false, true] {
                for theme in ThemeStyle.allCases {
                    let resolved = CompanionAvatar.resolve(stored: raw, hasCustomImage: hasImage, theme: theme)
                    XCTAssertEqual(resolved, .victoria, "\"\(raw)\"")
                    XCTAssertTrue(resolved.isBuiltIn)
                }
            }
        }
    }

    func testAKnownBuiltInIsKeptWhateverElseIsStored() {
        for theme in ThemeStyle.allCases {
            XCTAssertEqual(CompanionAvatar.resolve(stored: "bryan", hasCustomImage: true, theme: theme), .bryan)
            XCTAssertEqual(CompanionAvatar.resolve(stored: "victoria", hasCustomImage: true, theme: theme), .victoria)
        }
    }

    func testCustomWithoutItsImageFallsBackToTheLooksBuiltIn() {
        XCTAssertEqual(CompanionAvatar.resolve(stored: "custom", hasCustomImage: true, theme: .cool), .custom)
        XCTAssertEqual(CompanionAvatar.resolve(stored: "custom", hasCustomImage: false, theme: .cool), .bryan)
        XCTAssertEqual(CompanionAvatar.resolve(stored: "custom", hasCustomImage: false, theme: .cute), .victoria)
    }

    func testTheProfileNeverReportsCustomWithoutAnImage() {
        let profile = UserProfile()
        profile.themeStyle = .cool
        profile.companionAvatarRaw = "custom"
        XCTAssertNil(profile.customAvatarPNG)
        XCTAssertEqual(profile.companionAvatar, .bryan)
        profile.customAvatarPNG = TestImages.characterPNG()
        XCTAssertEqual(profile.companionAvatar, .custom)
        profile.customAvatarPNG = nil
        XCTAssertEqual(profile.companionAvatar, .bryan)
    }

    func testExistingProfilesKeepTheirBuiltInCharacter() {
        // The two existing users: a stored built-in, no custom image.
        for (raw, want) in [("victoria", CompanionAvatar.victoria), ("bryan", .bryan)] {
            let profile = UserProfile()
            profile.companionAvatarRaw = raw
            XCTAssertEqual(profile.companionAvatar, want)
            XCTAssertNil(profile.customAvatarPNG)
        }
        XCTAssertEqual(UserProfile().companionAvatar, .victoria, "the default is unchanged")
    }

    func testTheBuddyIsAlwaysDrawnAsABuiltIn() {
        XCTAssertEqual(CompanionAvatar.victoria.buddyStandIn, .bryan)
        XCTAssertEqual(CompanionAvatar.bryan.buddyStandIn, .victoria)
        for avatar in CompanionAvatar.allCases {
            XCTAssertTrue(avatar.buddyStandIn.isBuiltIn, "\(avatar)")
        }
    }

    func testEveryAvatarHasPhrasesAndACustomOneBorrowsNobodysVoice() {
        for avatar in CompanionAvatar.allCases {
            XCTAssertFalse(CompanionPhrases.phrases(for: avatar).isEmpty, "\(avatar)")
        }
        let custom = Set(CompanionPhrases.phrases(for: .custom))
        XCTAssertTrue(custom.isDisjoint(with: CompanionPhrases.victoria))
        XCTAssertTrue(custom.isDisjoint(with: CompanionPhrases.bryan))
    }

    func testTheCoachCanOnlyPickABuiltInCharacter() throws {
        let profile = UserProfile()
        profile.onboardingComplete = true
        let schema = try XCTUnwrap(CoachTools.schemas(for: profile).first { ($0["name"] as? String) == "set_companion" })
        let input = try XCTUnwrap(schema["input_schema"] as? [String: Any])
        let avatar = try XCTUnwrap((input["properties"] as? [String: Any])?["avatar"] as? [String: Any])
        XCTAssertEqual(avatar["enum"] as? [String], ["victoria", "bryan"])
        switch CoachTools.parse(name: "set_companion", input: ["avatar": "custom"], profile: profile, todaysFoods: []) {
        case .ok: XCTFail("the coach set a custom character that has no image")
        case .invalid(let reason): XCTAssertTrue(reason.contains("isn't an avatar I have"), reason)
        }
        switch CoachTools.parse(name: "set_companion", input: ["avatar": "bryan"], profile: profile, todaysFoods: []) {
        case .ok: break
        case .invalid(let reason): XCTFail("a built-in was refused: \(reason)")
        }
    }

    // MARK: - The widget's copy of the image

    func testTheWidgetFileIsWrittenAndReadBackByItsDigest() throws {
        let source = TestImages.characterPNG(side: 1024)
        let digest = try XCTUnwrap(WidgetAvatarFile.sync(sourcePNG: source, in: directory))
        XCTAssertEqual(files(), ["widget_avatar.png", "widget_avatar.source"])

        let read = try XCTUnwrap(WidgetAvatarFile.read(expectedDigest: digest, in: directory))
        XCTAssertEqual(WidgetAvatarFile.digest(read), digest)
        XCTAssertEqual(digest.count, 64, "a SHA-256 in hex")

        // A small copy, still square, still a PNG with its transparent background.
        let size = try XCTUnwrap(TestImages.pixelSize(of: read))
        XCTAssertEqual(size.width, 320)
        XCTAssertEqual(size.height, 320)
        XCTAssertLessThan(read.count, source.count * 4)
        XCTAssertEqual(try AvatarImage.validateCharacterPNG(read), 320)
        let pixels = try XCTUnwrap(AvatarImage.rgba(ofImageData: read))
        XCTAssertEqual(pixels.alpha(x: 0, y: 0), 0, "the top-left corner is no longer transparent")
        XCTAssertEqual(pixels.alpha(x: 160, y: 300), 255, "the character's body is no longer opaque")
    }

    func testASmallCharacterIsNotEnlargedForTheWidget() throws {
        let digest = try XCTUnwrap(WidgetAvatarFile.sync(sourcePNG: TestImages.characterPNG(side: 64), in: directory))
        let read = try XCTUnwrap(WidgetAvatarFile.read(expectedDigest: digest, in: directory))
        XCTAssertEqual(TestImages.pixelSize(of: read)?.width, 64)
    }

    func testSyncingTheSameCharacterAgainDoesNotRewriteTheFile() throws {
        let source = TestImages.characterPNG(side: 256)
        let first = try XCTUnwrap(WidgetAvatarFile.sync(sourcePNG: source, in: directory))
        let file = directory.appendingPathComponent(WidgetAvatarFile.fileName)
        let past = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: file.path)
        let second = try XCTUnwrap(WidgetAvatarFile.sync(sourcePNG: source, in: directory))
        XCTAssertEqual(first, second)
        let modified = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        XCTAssertEqual(modified, past, "an unchanged character was encoded again")
    }

    func testANewCharacterReplacesTheWidgetFile() throws {
        let first = try XCTUnwrap(WidgetAvatarFile.sync(sourcePNG: TestImages.characterPNG(side: 64), in: directory))
        var palette = TestImages.characterPalette
        palette["T"] = .red
        let other = TestImages.png(width: 64, height: 64, grid: TestImages.characterGrid, palette: palette)
        let second = try XCTUnwrap(WidgetAvatarFile.sync(sourcePNG: other, in: directory))
        XCTAssertNotEqual(first, second)
        XCTAssertNil(WidgetAvatarFile.read(expectedDigest: first, in: directory), "the old character is still served")
        XCTAssertNotNil(WidgetAvatarFile.read(expectedDigest: second, in: directory))
    }

    func testSwitchingToABuiltInRemovesTheWidgetFile() throws {
        _ = try XCTUnwrap(WidgetAvatarFile.sync(sourcePNG: TestImages.characterPNG(), in: directory))
        XCTAssertEqual(files().count, 2)
        XCTAssertNil(WidgetAvatarFile.sync(sourcePNG: nil, in: directory))
        XCTAssertEqual(files(), [])
    }

    func testABrokenCharacterLeavesNoWidgetFile() {
        XCTAssertNil(WidgetAvatarFile.sync(sourcePNG: Data("not a png".utf8), in: directory))
        XCTAssertEqual(files(), [])
    }

    func testNoDirectoryMeansNoFileAndNoRead() {
        XCTAssertNil(WidgetAvatarFile.sync(sourcePNG: TestImages.characterPNG(), in: nil))
        XCTAssertNil(WidgetAvatarFile.read(expectedDigest: "abc", in: nil))
    }

    // MARK: - A widget never shows another person's character

    func testAFileThatIsNotTheOneTheSnapshotNamesIsNotRead() throws {
        // Another profile's character was left in the container.
        let theirs = try XCTUnwrap(WidgetAvatarFile.sync(sourcePNG: TestImages.characterPNG(side: 64), in: directory))
        let mine = WidgetAvatarFile.digest(TestImages.characterPNG(side: 32))
        XCTAssertNotEqual(theirs, mine)
        XCTAssertNil(WidgetAvatarFile.read(expectedDigest: mine, in: directory))
        XCTAssertNil(WidgetAvatarFile.read(expectedDigest: nil, in: directory))
        XCTAssertNil(WidgetAvatarFile.read(expectedDigest: "", in: directory))
        XCTAssertNotNil(WidgetAvatarFile.read(expectedDigest: theirs, in: directory), "control: the right digest reads it")
    }

    func testAMissingFileIsNotRead() {
        XCTAssertNil(WidgetAvatarFile.read(expectedDigest: String(repeating: "a", count: 64), in: directory))
    }

    func testWidgetArtIsNeutralWheneverTheCustomImageCannotBeShown() {
        let png = TestImages.characterPNG()
        XCTAssertEqual(WidgetCompanionArt.resolve(raw: "custom", file: png), .custom(png))
        XCTAssertEqual(WidgetCompanionArt.resolve(raw: "custom", file: nil), .neutral)
        XCTAssertEqual(WidgetCompanionArt.resolve(raw: "", file: nil), .neutral)
        XCTAssertEqual(WidgetCompanionArt.resolve(raw: "somebody-else", file: png), .neutral)
        XCTAssertEqual(WidgetCompanionArt.resolve(raw: "victoria", file: nil), .builtIn(raw: "victoria"))
        // A built-in profile never draws a leftover file, even one that is present.
        XCTAssertEqual(WidgetCompanionArt.resolve(raw: "bryan", file: png), .builtIn(raw: "bryan"))
    }

    // MARK: - The snapshot carries the digest

    private func snapshot(raw: String, digest: String?) -> WidgetSnapshot {
        WidgetSnapshot(updated: Date(timeIntervalSince1970: 1_800_000_000), name: "Alex",
                       themeStyleRaw: ThemeStyle.cool.rawValue, companionAvatarRaw: raw,
                       companionAvatarDigest: digest,
                       calorieTarget: 2400, calorieMax: 0, caloriesEaten: 900, stepBonus: 0,
                       protein: 60, proteinTarget: 160, carbs: 100, carbsTarget: 280, fat: 30, fatTarget: 70,
                       steps: 4000, stepGoal: 9000, waterOz: 20, waterGoalOz: 90,
                       trendWeight: 160, ratePerWeek: 0.3, goalWeight: 172, trendSpark: [159, 160], streak: 4)
    }

    func testTheDigestSurvivesEncodingAndAnOldSnapshotDecodesWithoutOne() throws {
        let data = try JSONEncoder().encode(snapshot(raw: "custom", digest: "abc123"))
        let decoded = try XCTUnwrap(WidgetSharedStore.decode(data))
        XCTAssertEqual(decoded.companionAvatarRaw, "custom")
        XCTAssertEqual(decoded.companionAvatarDigest, "abc123")

        // A snapshot written by the build before this one has no such key.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "companionAvatarDigest"))
        let old = try XCTUnwrap(WidgetSharedStore.decode(try JSONSerialization.data(withJSONObject: object)))
        XCTAssertNil(old.companionAvatarDigest)
        XCTAssertEqual(old.streak, 4)
    }

    func testEndToEndTheWidgetDrawsOnlyTheCharacterItsSnapshotNames() throws {
        let digest = try XCTUnwrap(WidgetAvatarFile.sync(sourcePNG: TestImages.characterPNG(side: 64), in: directory))
        func art(_ snap: WidgetSnapshot) -> WidgetCompanionArt {
            WidgetCompanionArt.resolve(raw: snap.companionAvatarRaw,
                                       file: WidgetAvatarFile.read(expectedDigest: snap.companionAvatarDigest, in: directory))
        }
        guard case .custom = art(snapshot(raw: "custom", digest: digest)) else {
            return XCTFail("the snapshot's own character was not drawn")
        }
        XCTAssertEqual(art(snapshot(raw: "custom", digest: "0000")), .neutral, "a different person's file was drawn")
        XCTAssertEqual(art(snapshot(raw: "custom", digest: nil)), .neutral)
        XCTAssertEqual(art(snapshot(raw: "bryan", digest: nil)), .builtIn(raw: "bryan"))
    }

    // MARK: - Decoding for display

    func testTheImageCacheDecodesACharacterAndRefusesGarbage() {
        XCTAssertNotNil(CustomCompanionImageCache.image(for: TestImages.characterPNG(side: 48)))
        XCTAssertNil(CustomCompanionImageCache.image(for: Data("nope".utf8)))
        let a = CustomCompanionImageCache.image(for: TestImages.characterPNG(side: 48))
        let b = CustomCompanionImageCache.image(for: TestImages.characterPNG(side: 48))
        XCTAssertTrue(a === b, "the same bytes were decoded twice")
        XCTAssertEqual(a?.size.width, 48)
    }
}
