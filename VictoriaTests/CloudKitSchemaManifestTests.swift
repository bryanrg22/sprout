import XCTest
import CoreData
import SwiftData
@testable import Victoria

/// The app's models mirror to the user's private iCloud database. CloudKit's Production
/// schema is fixed: a record type or a field it does not know is rejected, and the app is
/// not told. `docs/cloudkit/model-manifest.json` is the list of everything the models
/// will send, exactly as Core Data sees them. This test holds that file to the models, so
/// a model change cannot land without the manifest changing, and
/// `tooling/check_cloudkit_schema.py` compares the manifest with an exported schema.
final class CloudKitSchemaManifestTests: XCTestCase {

    /// `<repo>/docs/cloudkit/model-manifest.json`, found from this file's own path.
    private var manifestURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/cloudkit/model-manifest.json")
    }

    /// Entity → attribute → Core Data attribute type name.
    static func liveManifest() throws -> [String: [String: String]] {
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: AppSchema.models))
        var out: [String: [String: String]] = [:]
        for entity in model.entities {
            let name = try XCTUnwrap(entity.name)
            var attributes: [String: String] = [:]
            for (key, attribute) in entity.attributesByName {
                attributes[key] = typeName(attribute.attributeType)
            }
            out[name] = attributes
            XCTAssertTrue(entity.relationshipsByName.isEmpty,
                          "\(name) has a relationship; the manifest and the checker cover attributes only")
        }
        return out
    }

    static func typeName(_ type: NSAttributeType) -> String {
        switch type {
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType: return "integer"
        case .doubleAttributeType, .floatAttributeType, .decimalAttributeType: return "double"
        case .stringAttributeType: return "string"
        case .booleanAttributeType: return "boolean"
        case .dateAttributeType: return "date"
        case .binaryDataAttributeType: return "binary"
        case .UUIDAttributeType: return "uuid"
        case .URIAttributeType: return "uri"
        case .transformableAttributeType: return "transformable"
        default: return "other(\(type.rawValue))"
        }
    }

    func testManifestMatchesTheModels() throws {
        let live = try Self.liveManifest()
        XCTAssertEqual(live.count, AppSchema.models.count)
        for (entity, attributes) in live {
            for (attribute, type) in attributes {
                XCTAssertFalse(type.hasPrefix("other"), "\(entity).\(attribute) has a type the checker cannot map")
            }
        }
        if ProcessInfo.processInfo.environment["SPROUT_WRITE_CLOUDKIT_MANIFEST"] == "1" {
            let data = try JSONSerialization.data(withJSONObject: live, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: manifestURL)
        }
        let stored = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: [String: String]],
            "docs/cloudkit/model-manifest.json is missing: run this test with TEST_RUNNER_SPROUT_WRITE_CLOUDKIT_MANIFEST=1")
        XCTAssertEqual(stored, live, """
            The models changed. Regenerate docs/cloudkit/model-manifest.json \
            (TEST_RUNNER_SPROUT_WRITE_CLOUDKIT_MANIFEST=1), then the CloudKit Development and \
            Production schemas need the new fields before a build ships (docs/cloudkit/README.md).
            """)
    }
}
