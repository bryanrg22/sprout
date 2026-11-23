import Foundation
import SwiftData
import XCTest
@testable import Victoria

/// An in-memory store on the full production schema (`AppSchema`), with CloudKit off, for
/// tests that must go through the real store: insert, save, then read back through a new
/// `ModelContext`, which fetches from the store and shares no object with the writer.
enum TestStore {

    static func makeContainer() throws -> ModelContainer {
        let schema = AppSchema.schema
        let configuration = ModelConfiguration(schema: schema,
                                               isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Every row of one model, read through a context that has never seen the writer's objects.
    static func fetchAll<T: PersistentModel>(_ type: T.Type,
                                             in container: ModelContainer,
                                             sortBy: [SortDescriptor<T>] = []) throws -> [T] {
        try ModelContext(container).fetch(FetchDescriptor<T>(sortBy: sortBy))
    }

    /// Row count of one model, read through a new context.
    static func count<T: PersistentModel>(_ type: T.Type, in container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<T>())
    }

    /// Row count of every model in `AppSchema.models`, keyed by entity name.
    static func countsByEntity(in container: ModelContainer) throws -> [String: Int] {
        var out: [String: Int] = [:]
        for model in AppSchema.models {
            out[Schema.entityName(for: model)] = try count(model, in: container)
        }
        return out
    }
}

/// Fixed dates for store tests: an explicit Gregorian calendar in an explicit time zone, so
/// no test depends on the machine's clock, zone or locale.
struct FixedCalendar {
    let calendar: Calendar

    init(zone: String = "America/Los_Angeles") {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        calendar = cal
    }

    /// The instant of a civil date and time in this calendar's zone.
    func at(_ year: Int, _ month: Int, _ day: Int,
            _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute, second: second))!
    }
}

// MARK: - Round-trip harness

/// One stored property of `M`: its schema name, the literal written, and how to read it.
struct StoreField<M: PersistentModel> {
    let name: String
    /// Writes the literal. `nil` when the initializer under test already wrote it.
    let assign: ((M) -> Void)?
    /// `nil` when the row holds the literal, else a description of the difference.
    let mismatch: (M) -> String?
}

@MainActor
extension XCTestCase {

    /// A property the initializer wrote: checked only.
    func wrote<M: PersistentModel, V: Equatable>(_ name: String, _ keyPath: KeyPath<M, V>,
                                         _ value: V) -> StoreField<M> {
        StoreField(name: name, assign: nil) {
            $0[keyPath: keyPath] == value ? nil : "\(name): read \($0[keyPath: keyPath]), wrote \(value)"
        }
    }

    /// A property the initializer does not take: set after init, then checked.
    func assigned<M: PersistentModel, V: Equatable>(_ name: String,
                                            _ keyPath: ReferenceWritableKeyPath<M, V>,
                                            _ value: V) -> StoreField<M> {
        StoreField(name: name, assign: { $0[keyPath: keyPath] = value }) {
            $0[keyPath: keyPath] == value ? nil : "\(name): read \($0[keyPath: keyPath]), wrote \(value)"
        }
    }

    /// A property whose stored text has no fixed spelling (JSON): checked through `mismatch`.
    func decoded<M: PersistentModel>(_ name: String, _ mismatch: @escaping (M) -> String?) -> StoreField<M> {
        StoreField(name: name, assign: nil, mismatch: mismatch)
    }

    /// Saves `full()` (and `sparse()`, the same model with its optionals left nil) and reads
    /// both back through a new context.
    ///
    /// - `blank`: the model with nothing but its required arguments, to prove every literal in
    ///   `fields` differs from the default the column would hold anyway.
    /// - `typed`: assertions on the typed accessors of the fetched full row.
    func assertRoundTrip<M: PersistentModel>(
        full: () -> M,
        blank: () -> M,
        fields: [StoreField<M>],
        sparse: (() -> M)? = nil,
        sparseFields: [StoreField<M>] = [],
        typed: (M) -> Void = { _ in },
        typedSparse: (M) -> Void = { _ in },
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        // The table names exactly the properties the schema stores for this model.
        let entity = try XCTUnwrap(AppSchema.schema.entities.first { $0.name == Schema.entityName(for: M.self) },
                                   file: file, line: line)
        XCTAssertEqual(fields.map(\.name).sorted(), entity.storedProperties.map { $0.name }.sorted(),
                       "the field table and the stored properties of \(entity.name) differ", file: file, line: line)
        XCTAssertEqual(Set(fields.map(\.name)).count, fields.count, "a field is listed twice", file: file, line: line)

        let container = try TestStore.makeContainer()
        let writer = ModelContext(container)

        let written = full()
        fields.forEach { $0.assign?(written) }
        writer.insert(written)

        // Every literal is a non-default value: a blank instance must fail every check.
        let untouched = blank()
        for field in fields {
            XCTAssertNotNil(field.mismatch(untouched),
                            "\(field.name) was written with its default value, so the check proves nothing",
                            file: file, line: line)
        }

        var writtenSparse: M?
        if let sparse {
            let row = sparse()
            writer.insert(row)
            writtenSparse = row
            XCTAssertFalse(sparseFields.isEmpty, "a sparse row needs its nil fields listed", file: file, line: line)
        }
        try writer.save()

        let reader = ModelContext(container)
        let rows = try reader.fetch(FetchDescriptor<M>())
        XCTAssertEqual(rows.count, sparse == nil ? 1 : 2, file: file, line: line)

        let read = try XCTUnwrap(rows.first { $0.persistentModelID == written.persistentModelID },
                                 "the saved row was not found in a new context", file: file, line: line)
        XCTAssertFalse(read === written, "the reader returned the writer's object, not a fetched row",
                       file: file, line: line)
        for field in fields {
            if let difference = field.mismatch(read) { XCTFail(difference, file: file, line: line) }
        }
        typed(read)

        if let writtenSparse {
            let readSparse = try XCTUnwrap(rows.first { $0.persistentModelID == writtenSparse.persistentModelID },
                                           file: file, line: line)
            XCTAssertFalse(readSparse === writtenSparse, file: file, line: line)
            for field in sparseFields {
                if let difference = field.mismatch(readSparse) { XCTFail(difference, file: file, line: line) }
                XCTAssertNotNil(field.mismatch(read), "\(field.name) is the same in the full and the sparse row",
                                file: file, line: line)
            }
            typedSparse(readSparse)
        }
    }

    /// A fixed UUID, so an `id` column is compared with a literal.
    func fixedUUID(_ lastDigits: Int) -> UUID {
        UUID(uuidString: String(format: "0F1E2D3C-4B5A-4978-8695-%012d", lastDigits))!
    }
}
