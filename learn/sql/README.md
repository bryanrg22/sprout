# SQL on Sprout's own database

A short course in SQL, done on the real database the app writes, not a textbook one. It
covers how an iPhone app's data ends up in tables, why these tables look the way they do,
how to get answers out of them, how to make a query fast, and how to test data with
queries. There are fourteen exercises and a checker that marks them.

Everything here is fictional demo data ("Alex", the app's public demo). Nothing comes from a
real person's phone.

## Start

You need `python3` and `sqlite3` (both come with macOS; on Linux, install `sqlite3`).

```bash
TZ=America/Los_Angeles sqlite3 learn/sql/sprout-demo.sqlite
```

```bash
python3 learn/sql/check.py
```

The first opens the database in SQLite's shell (`.tables`, `.schema ZFOODENTRY`, `.headers on`
and `.mode column` help; `.quit` leaves). The second marks your answers. Write each answer in
its file in `exercises/`, under the question, then run the checker, or `check.py 07` for one.

`TZ=America/Los_Angeles` matters: the demo was recorded there, and exercise 03 shows why.

## 1. How the app stores data

The app never writes SQL. Its code describes each kind of record as a Swift class:

```swift
@Model
final class FoodEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var name: String = ""
    var calories: Double = 0
    var mealTypeRaw: String = MealType.snack.rawValue
    // ...
}
```

SwiftData (Apple's persistence framework) hands these classes to Core Data, which keeps them
in one SQLite file, `default.store`, in the app's shared folder on the phone. Core Data
creates the tables and writes every `SELECT`, `INSERT` and `UPDATE` itself. To watch it do
so, an Xcode scheme can pass Core Data's debug argument `-com.apple.CoreData.SQLDebug 1`,
and the console then shows each statement.

That class becomes this table (from the demo file, `.schema ZFOODENTRY`, shortened):

```sql
CREATE TABLE ZFOODENTRY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER,
  ZISFAVORITE INTEGER, ZCALORIES FLOAT, ..., ZCREATEDAT TIMESTAMP, ZDATE TIMESTAMP, ...,
  ZMEALTYPERAW VARCHAR, ZNAME VARCHAR, ..., ZID BLOB, ZPHOTODATA BLOB );
```

**The rules.** `SproutTests/SQLStoreShapeTests.swift` checks each one against a store built
from the app's real schema, so a change in Core Data would fail a test, not leave this page
wrong.

| In Swift | In SQLite |
|---|---|
| a model, `FoodEntry` | a table, `ZFOODENTRY`: `Z` + the name in capitals |
| a property, `calories` | a column, `ZCALORIES` |
| (added by Core Data) | `Z_PK`, the row's key, 1, 2, 3, ...; `Z_ENT`, the entity's number; `Z_OPT`, how many times the row has been saved |
| `Int`, `Bool` | `INTEGER` (a `Bool` is 0 or 1) |
| `Double` | `FLOAT` |
| `Date` | `TIMESTAMP`: seconds since **2001-01-01 00:00 UTC** |
| `String` | `VARCHAR` |
| `UUID` | `BLOB`, 16 bytes (`hex(ZID)` to read it) |
| an enum | the app stores its raw string itself, so the column is `...RAW` (`ZMEALTYPERAW`: `'dinner'`) |
| an array, `gymWeekdays: [Int]` | `BLOB`: a binary property list (it starts `bplist00`), which SQL cannot see inside |

Columns come grouped by type (integers, floats, dates, strings, blobs), alphabetical within
each, after the three `Z_` columns.

**The declared types are only names.** SQLite stores by *affinity*: `TIMESTAMP` gets numeric
affinity, so a date on a whole second is stored as an integer and one with a fraction as a
real (`SELECT typeof(ZDATE), typeof(ZCREATEDAT) FROM ZFOODENTRY` gives `integer`, `real`).
`VARCHAR` is text. Compare and calculate with them as numbers and text and it doesn't matter.

**Core Data's own tables.**
- `Z_PRIMARYKEY`: one row per entity, with its number (`Z_ENT`) and `Z_MAX`, the last key
  handed out. Exercise 02.
- `Z_METADATA`: the model version, so Core Data knows when to migrate the file.
- `Z_MODELCACHE`: a copy of the model.
- `ACHANGE`, `ATRANSACTION`, `ATRANSACTIONSTRING`: *persistent history*, a log of every insert,
  update and delete, which SwiftData turns on. Their entities are numbered from 16001.
  `ATRANSACTIONSTRING` holds the writer's bundle id, `com.bryanram.victoria`, the app's id
  since before it was called Sprout.
- In the app on a phone, 18 more tables starting `ANSCK` (`ANSCKRECORDMETADATA`, ...): CloudKit's
  bookkeeping of what has been sent to iCloud and what came back. The demo file was built with
  CloudKit off, so it has none; a simulator's store of the real app has them.

**The real file.** On a simulator it is at
`~/Library/Developer/CoreSimulator/Devices/<device>/data/Containers/Shared/AppGroup/<id>/Library/Application Support/default.store`,
with `default.store-wal` beside it: SQLite's write-ahead log, where the newest rows wait before
they are copied into the main file. Open it read-only (`sqlite3 "file:default.store?mode=ro"`)
and keep the `-wal` file beside it, or the newest rows are missing. Never write to it: Core
Data keeps `Z_PK`, `Z_MAX`, `Z_OPT` and the history consistent, and CloudKit sends only the
changes Core Data recorded. A row added with SQL would collide with a key, be missing from the
history and never reach iCloud. `tooling/verify_store.py` is the read-only report the project
uses on real stores.

## 2. Why the tables look like this

Sprout's data syncs between the phone and iCloud through CloudKit, and a SwiftData model that
syncs this way must follow Apple's rules (Apple's guide is "Creating a Core Data model for
CloudKit"; the reasons are written down in the code too, for example `BuddyLink.swift`):

1. **Every property has a default or is optional.** A record arriving from iCloud may lack a
   field added in a later version. So no `NOT NULL` column can be relied on, and none of
   these tables declares one.
2. **No uniqueness rule.** Two phones can each create "today's steps" while offline; CloudKit
   cannot refuse one of them. So there is no `UNIQUE` index anywhere (the shape test checks),
   and "one steps row per day" is a promise the app's code keeps, not the database.
   Exercise 14 is the query that finds a broken promise.
3. **No relationships, by this app's choice.** CloudKit allows relationships if they are
   optional and two-way. Sprout uses none: a gym session's exercises point at it by its UUID,
   `ZEXERCISEENTRY.ZSESSIONID = ZWORKOUTSESSION.ZID`, which is a plain column, not a foreign
   key. Nothing deletes the exercises when a session goes and nothing refuses an exercise
   whose session doesn't exist; the app's code does both. Exercise 07 joins on it and
   exercise 13 finds the orphans.
4. **Copies on purpose (denormalisation).** `ZEXERCISEENTRY.ZDATE` repeats its session's date.
   Without a relationship the app's queries cannot sort exercises by their session's date, so
   the date is copied on save (`ExerciseEntry.swift` says why). The cost: two copies that must
   agree.
5. **A list in a string.** `ZWORKOUTSESSION.ZFOCUSESRAW` is `'chest,arms'`: two values in one
   column, which breaks the first rule of table design (first normal form). It is easy to
   show and easy to sync, and finding "arms days" takes `LIKE`, which `'forearms'` would also
   match. A table of (session, focus) rows is the textbook design. Question 4 below.
6. **No indexes.** No model declares one, so every query reads the whole table. With a few
   hundred rows that takes microseconds and an index would only slow every save. Exercises
   11 and 12, and the lab below, are about when that stops being true. (SwiftData can declare
   one with `#Index` since iOS 18.)

**Time.** A date column is an *instant*, the same for everyone: seconds since 2001 in UTC.
A *day* is local. The app stores a day's rows (steps, sleep, weigh-ins) at that day's local
midnight, and a meal at the moment it was eaten. To get a day back you need the place: a
dinner at 7 pm in Los Angeles is the next day in UTC (exercise 04), and Los Angeles was UTC-7
until daylight saving ended on 1 November 2026 and UTC-8 after, so a fixed `'-8 hours'` puts
every October day one day early (exercise 03). SQLite has no time zones of its own: its
`'localtime'` follows the `TZ` of the program running it, which is why the commands above
and the checker set it.

## 3. The exercises

| # | What | You use |
|---|---|---|
| 01 | Which tables hold the app's data | `sqlite_master`, `GLOB` |
| 02 | How keys are handed out | `Z_PRIMARYKEY`, `WHERE` |
| 03 | Dates are numbers | date functions, `'localtime'` |
| 04 | The day depends on where you are | the same, twice |
| 05 | Calories per meal today | `GROUP BY`, `SUM` |
| 06 | Average sleep | `AVG`, integer division |
| 07 | Sessions and their exercises | `LEFT JOIN` on a UUID, `COALESCE` |
| 08 | The best lift per machine | `GROUP BY`, `MAX` |
| 09 | A 7-weigh-in moving average | a window function |
| 10 | Good days | two tables and a setting, a subquery |
| 11 | Make the strength chart's query fast | `EXPLAIN QUERY PLAN`, `CREATE INDEX` |
| 12 | Make "today's food" fast | an index for a range |
| 13 | Find orphaned rows | a query that tests data |
| 14 | Find a day stored twice | `HAVING` |

How the checker marks them is at the top of `check.py`. In short: a result is compared by
value, column by column (the names you give columns don't matter, and `600` equals `600.0`); order
matters only where the question asks for one; it tells you how your answer differs (rows,
columns, order), never what the answer is. An index answer is run on a copy and the query's
plan must change. A data test must stay quiet on the clean database and catch a defect the
checker plants, a different one each run, beside a harmless decoy.

The reference answers are in `solutions/`. Try first: the point is the doing.

## 4. Measuring

On a few dozen rows every query is instant, so speed can't be seen in the demo file. `lab.sql` makes a
copy 200,000 rows bigger and times two queries three ways:

```bash
cp learn/sql/sprout-demo.sqlite /tmp/big.sqlite
```

```bash
sqlite3 /tmp/big.sqlite < learn/sql/lab.sql
```

What it gave on the Mac this was written on (five runs each; yours will differ, the ratios
less so):

| Query | No index | Index (machine, date) | Covering index (machine, date, weight) |
|---|---|---|---|
| One machine's whole history (18,183 rows, 1 in 11) | 8–9 ms | 5–7 ms | about 1 ms |
| One machine on one day (13 rows) | 7–8 ms | under 1 ms | |

Read it as:
- An index wins most when it lets SQLite skip almost everything: 13 rows out of 200,000.
- When the query needs 1 row in 11, the index still saves the scan and the sort, but each
  match costs a jump back into the table for the weight. So the gain is small.
- A *covering* index holds every column the query reads, so the table is never touched.

Every index is also a cost: written on every insert, and bigger on disk. That is the trade
behind point 6 above.

## 5. Testing

Queries can be wrong in the same quiet way code can, so the project tests them:
- `SproutTests/SQLStoreShapeTests.swift` builds a store from the app's schema and checks
  what section 1 says.
- `tooling/verify_store.py` runs data checks like exercises 13 and 14 on a real store.
  `--self-test` builds stores with one planted defect each and checks the report finds it.
- `check.py --self-test` tests the checker: it passes the reference answers, and fails a
  wrong order, a wrong count, a write, a `UNIQUE` index, an index on the wrong column, and
  a data test that reports everything or only the newest row.

The idea to take away is from exercises 13 and 14: a check that returns nothing proves little
until you have seen it catch a planted defect.

## 6. Questions

Answer these in your own words in `ANSWERS.md`. There's no checker; talk them over with
Bryan.

1. After a row is deleted, is `Z_MAX` still the number of rows? Why does Core Data keep it
   instead of using `MAX(Z_PK)`?
2. The exercises link sessions and exercises by UUID. What would a real foreign key with
   `ON DELETE CASCADE` give the app, and why can't it have one?
3. `ZEXERCISEENTRY.ZDATE` copies its session's date. Name a way the two could come to
   disagree, and a query that would find it.
4. Design the table that would replace `ZFOCUSESRAW`. Write the query for "every arms day"
   both ways. Which needs `LIKE`, and what does that get wrong?
5. Why is "one steps row per day" safe to leave to the app's code here, and when would you
   insist on a `UNIQUE` index?
6. Exercise 11's index makes reads faster. What does it make slower? When would you not add it?

## Working on this

Do the work on a branch of your own, commit under your own name, and open a pull request.
CI runs `check.py`, so a wrong answer fails the build, and an exercise not attempted yet does
not. `build_demo_db.sh` rebuilds the database after a model changes (maintainers only; it
changes the answers).

## How this page was checked

Verified on the files in this folder:
- the table and column rules, by `SQLStoreShapeTests`, including that the test fails when one
  rule is wrong;
- the storage types, with `typeof`;
- the 18 `ANSCK` tables, from the table names of a simulator store of the real app (names
  only, no data);
- every exercise's reference answer, by the checker;
- the lab's numbers, by running it.

Not verified here:
- Core Data's SQL debug argument;
- how large data in an external-storage column (`ZPHOTODATA`) is kept (the demo has none);
- Apple's CloudKit rules, which are stated from Apple's guide and the app's code comments.
