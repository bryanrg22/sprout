import XCTest
@testable import Sprout

/// The personal onboarding note: its text is not in the repository, and its page exists only
/// for the one person it is addressed to (EVAL_REPORT 27).
final class PersonalNoteTests: XCTestCase {

    private let note = PersonalNote(recipient: "Sam", from: "Alex", text: "Welcome in.")

    func testItIsForTheNameItIsAddressedTo() {
        for typed in ["Sam", "sam", "  SAM ", "Sam Rivera", "sám"] {
            XCTAssertTrue(note.isFor(name: typed), typed)
        }
        for typed in ["", "   ", "Sa", "Samantha", "Alex", "Rivera Sam", "S am"] {
            XCTAssertFalse(note.isFor(name: typed), typed)
        }
        XCTAssertFalse(PersonalNote(recipient: "  ", from: "Alex", text: "x").isFor(name: "  "))
    }

    func testItDecodesOnlyWhenEveryFieldHasSomethingInIt() {
        func decode(_ json: String) -> PersonalNote? { PersonalNote.decode(Data(json.utf8)) }
        XCTAssertEqual(decode(#"{"recipient":"Sam","from":"Alex","text":"Hi\nthere"}"#),
                       PersonalNote(recipient: "Sam", from: "Alex", text: "Hi\nthere"))
        XCTAssertNil(decode(#"{"recipient":"Sam","from":"Alex","text":"   "}"#))
        XCTAssertNil(decode(#"{"recipient":"","from":"Alex","text":"Hi"}"#))
        XCTAssertNil(decode(#"{"recipient":"Sam","text":"Hi"}"#), "a missing field")
        XCTAssertNil(decode("not json"))
    }

    func testItIsReadFromTheBundleAndAbsentWithoutTheFile() throws {
        // Two folders: `Bundle` caches what it found in a folder, so one folder cannot be
        // read before and after the file is added.
        func folder(withNote: Bool) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("note-\(UUID().uuidString).bundle")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if withNote {
                try Data(#"{"recipient":"Sam","from":"Alex","text":"Welcome in."}"#.utf8)
                    .write(to: url.appendingPathComponent("PersonalNote.json"))
            }
            return url
        }
        let empty = try folder(withNote: false)
        let withNote = try folder(withNote: true)
        defer { [empty, withNote].forEach { try? FileManager.default.removeItem(at: $0) } }
        XCTAssertNil(PersonalNote.load(bundle: try XCTUnwrap(Bundle(url: empty))))
        XCTAssertEqual(PersonalNote.load(bundle: try XCTUnwrap(Bundle(url: withNote))), note)
    }

    func testTheTestHostIsBuiltWithoutANoteOrWithACompleteOne() {
        // On CI there is no private file; on the owner's machine there may be. Either way a
        // note that is present is complete.
        if let bundled = PersonalNote.load() {
            XCTAssertFalse(bundled.recipient.isEmpty)
            XCTAssertFalse(bundled.text.isEmpty)
        }
    }

    // MARK: - Where its page goes

    func testWithoutTheNoteTheStepsAreTheTwelveOthersInOrder() {
        let steps = OnboardingView.steps(personalNoteShown: false)
        XCTAssertEqual(steps.count, 12)
        XCTAssertFalse(steps.contains(.personalNote))
        XCTAssertEqual(steps.first, .welcome, "the first screen is the app's own welcome, for everyone")
        XCTAssertEqual(steps.last, .vitaNote)
    }

    func testWithTheNoteItComesRightAfterTheNameIsTyped() throws {
        let steps = OnboardingView.steps(personalNoteShown: true)
        XCTAssertEqual(steps.count, 13)
        let about = try XCTUnwrap(steps.firstIndex(of: .about))
        XCTAssertEqual(steps[about + 1], .personalNote)
        XCTAssertEqual(steps.filter { $0 != .personalNote }, OnboardingView.steps(personalNoteShown: false),
                       "the other steps keep their order")
    }

    func testThePublicOnboardingSourceHoldsNoNote() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sprout/Features/Onboarding/OnboardingView.swift"),
                                encoding: .utf8)
        XCTAssertFalse(source.contains("private let bryanNote"))
        XCTAssertFalse(source.contains("\"from Bryan\""))
        XCTAssertFalse(source.contains("— Bryan 🫶"))
    }
}
