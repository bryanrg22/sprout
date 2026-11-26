import XCTest
import SwiftData
import SQLite3
@testable import Sprout

/// The SQLite file SwiftData writes for the app's real schema, opened as plain SQLite.
///
/// `learn/sql/README.md` teaches SQL on this file, so what it says about the tables is
/// checked here against a store built from `AppSchema`, not against memory of Core Data:
/// a table per model named `Z` + the model's name in capitals, a column per property named
/// the same way, Core Data's own `Z_` tables, no `UNIQUE` index on any model's table, and
/// the flat `UUID` links instead of relationship columns.
///
/// Writing the learning database: with `SPROUT_SQL_DEMO_OUT` set (pass it to the test
/// runner as `TEST_RUNNER_SPROUT_SQL_DEMO_OUT=/abs/path/sprout-demo.sqlite`), the store is
/// also filled with the fictional "Alex" demo (`DemoSeed`) and copied, write-ahead log
/// merged, to that path. `learn/sql/build_demo_db.sh` does this. Without it the test only
/// checks the shape and writes nothing outside its temporary folder.
final class SQLStoreShapeTests: XCTestCase {

    func testTheStoreHasTheTablesAndColumnsTheSQLGuideDescribes() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("sql-shape-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("default.store")

        let output = ProcessInfo.processInfo.environment["SPROUT_SQL_DEMO_OUT"].flatMap { $0.isEmpty ? nil : $0 }
        do {
            // The app's schema on disk, with CloudKit off (no account, no network in a test).
            let schema = AppSchema.schema
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container)
            if output != nil {
                DemoSeed.seed(context, gaining: true)
            }
            try context.save()
        }

        let db = try SQLiteFile(url)

        // One table per model, `Z` + the class name in capitals.
        let tables = try db.strings("SELECT name FROM sqlite_master WHERE type = 'table'")
        for model in AppSchema.models {
            let table = "Z" + String(describing: model).uppercased()
            XCTAssertTrue(tables.contains(table), "no table \(table) for \(model)")
        }
        // Core Data's bookkeeping: the entity list with each table's last key, and the model.
        for table in ["Z_PRIMARYKEY", "Z_METADATA", "Z_MODELCACHE"] {
            XCTAssertTrue(tables.contains(table), "no \(table)")
        }

        // Every model table starts with Core Data's three columns.
        let food = try db.strings("SELECT name FROM pragma_table_info('ZFOODENTRY')")
        XCTAssertEqual(Array(food.prefix(3)), ["Z_PK", "Z_ENT", "Z_OPT"])
        // A property becomes `Z` + its name in capitals; a date is a REAL (seconds since 2001).
        XCTAssertTrue(food.contains("ZCALORIES"))
        XCTAssertTrue(food.contains("ZMEALTYPERAW"))   // an enum is stored through its raw-value property
        XCTAssertEqual(try db.strings("SELECT type FROM pragma_table_info('ZFOODENTRY') WHERE name = 'ZDATE'"),
                       ["TIMESTAMP"])

        // The workout link is a flat UUID column, not a relationship: no `Z…` integer key
        // column pointing at ZWORKOUTSESSION, and the parent's date copied onto the child.
        let exercise = try db.strings("SELECT name FROM pragma_table_info('ZEXERCISEENTRY')")
        XCTAssertTrue(exercise.contains("ZSESSIONID"))
        XCTAssertTrue(exercise.contains("ZDATE"))
        XCTAssertFalse(exercise.contains("ZSESSION"), "a relationship column appeared")

        // CloudKit cannot keep a uniqueness rule, so no model table may have a UNIQUE index.
        for model in AppSchema.models {
            let table = "Z" + String(describing: model).uppercased()
            let unique = try db.strings("SELECT name FROM pragma_index_list('\(table)') WHERE \"unique\" = 1")
            XCTAssertEqual(unique, [], "\(table) has a unique index")
        }

        guard let output else { return }
        // The seeded rows really are there, with the fictional name.
        XCTAssertEqual(try db.strings("SELECT ZNAME FROM ZUSERPROFILE"), ["Alex"])
        XCTAssertGreaterThan(try db.strings("SELECT Z_PK FROM ZFOODENTRY").count, 5)
        // One self-contained file (the write-ahead log merged in), replacing any old copy.
        try? FileManager.default.removeItem(atPath: output)
        _ = try db.strings("VACUUM INTO '\(output.replacingOccurrences(of: "'", with: "''"))'")
    }
}

/// A read of a SQLite file through the system library; enough for the checks above.
private final class SQLiteFile {
    private var handle: OpaquePointer?

    init(_ url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLiteFile", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "could not open \(url.path)"])
        }
    }

    deinit { sqlite3_close(handle) }

    /// The first column of every row, as text.
    func strings(_ sql: String) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLiteFile", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))])
        }
        defer { sqlite3_finalize(statement) }
        var rows: [String] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw NSError(domain: "SQLiteFile", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))])
            }
            if sqlite3_column_count(statement) > 0, let text = sqlite3_column_text(statement, 0) {
                rows.append(String(cString: text))
            }
        }
        return rows
    }
}
