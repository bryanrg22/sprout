#!/usr/bin/env python3
"""Checks the SQL exercises in learn/sql/exercises against the demo database.

    python3 learn/sql/check.py                 # every exercise
    python3 learn/sql/check.py 07 11           # just these
    python3 learn/sql/check.py --answers DIR   # another folder of answers (the reference: solutions/)
    python3 learn/sql/check.py --all           # an exercise not attempted yet counts as a failure
    python3 learn/sql/check.py --record        # maintainers: rewrite expected.json from solutions/
    python3 learn/sql/check.py --self-test     # the checker's own tests

An exercise file holding only comments is "todo", not a failure. Exit status: 0 when nothing
failed (with --all: when everything passed), 1 otherwise, 2 on a usage error.

How each kind of exercise is checked:
  rows     Your query runs on a read-only copy. Its rows are compared with the reference
           answer's, by value (column names don't matter, 600 equals 600.0, floats to four
           places). Order matters only where the exercise asks for one. expected.json holds
           a hash of the answer, never the answer itself, so a failure says how yours
           differs in size or order, not what the answer is.
  index    Your CREATE INDEX statements run on a scratch copy; then a fixed query's plan
           (EXPLAIN QUERY PLAN) must no longer read the whole table or sort afterwards, and
           the query must still return the same rows.
  detects  Your query is a data check. On the clean database it must return nothing. On a
           copy with one planted defect (a different one each run) it must return exactly
           the planted row.

Every query runs with TZ=America/Los_Angeles, where the demo was recorded, so SQLite's
'localtime' modifier gives Los Angeles time on any machine, daylight saving included.
Standard library only.
"""
import argparse
import hashlib
import json
import os
import random
import re
import shutil
import sqlite3
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATABASE = HERE / "sprout-demo.sqlite"
EXPECTED = HERE / "expected.json"
SOLUTIONS = HERE / "solutions"
EXERCISES_DIR = HERE / "exercises"
APPLE_EPOCH = 978307200  # seconds from 1970-01-01 to 2001-01-01, both UTC
ZONE = "America/Los_Angeles"

# 2026-11-25 00:00 and 2026-11-26 00:00 in Los Angeles (UTC-8 in November), in Core Data's
# seconds since 2001. The demo's "today".
TODAY_START = 1795593600 - APPLE_EPOCH
TODAY_END = TODAY_START + 86400

EXERCISES = [
    {"id": "01", "file": "01_tables.sql", "kind": "rows", "ordered": True},
    {"id": "02", "file": "02_keys.sql", "kind": "rows", "ordered": True},
    {"id": "03", "file": "03_dates.sql", "kind": "rows", "ordered": True},
    {"id": "04", "file": "04_timezone_trap.sql", "kind": "rows", "ordered": False},
    {"id": "05", "file": "05_calories_by_meal.sql", "kind": "rows", "ordered": True},
    {"id": "06", "file": "06_average_sleep.sql", "kind": "rows", "ordered": False},
    {"id": "07", "file": "07_sessions_join.sql", "kind": "rows", "ordered": True},
    {"id": "08", "file": "08_best_per_machine.sql", "kind": "rows", "ordered": True},
    {"id": "09", "file": "09_moving_average.sql", "kind": "rows", "ordered": True},
    {"id": "10", "file": "10_good_days.sql", "kind": "rows", "ordered": True},
    {"id": "11", "file": "11_index_machine.sql", "kind": "index", "table": "ZEXERCISEENTRY",
     "query": "SELECT ZWEIGHTLBS, ZDATE FROM ZEXERCISEENTRY WHERE ZMACHINEKEY = 'leg_press' ORDER BY ZDATE"},
    {"id": "12", "file": "12_index_day.sql", "kind": "index", "table": "ZFOODENTRY",
     "query": f"SELECT ZNAME, ZCALORIES FROM ZFOODENTRY WHERE ZDATE >= {TODAY_START} AND ZDATE < {TODAY_END}"},
    {"id": "13", "file": "13_orphans.sql", "kind": "detects", "plant": "orphan_exercise"},
    {"id": "14", "file": "14_duplicate_days.sql", "kind": "detects", "plant": "duplicate_steps_day"},
]
BY_ID = {e["id"]: e for e in EXERCISES}


def use_demo_zone():
    os.environ["TZ"] = ZONE
    time.tzset()


def strip_comments(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    return "\n".join(line.split("--", 1)[0] for line in sql.splitlines()).strip()


def normalize(value):
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        number = round(float(value), 4)
        return 0.0 if number == 0 else number
    if isinstance(value, bytes):
        return value.hex().upper()
    return value


def normalized_rows(rows):
    return [[normalize(v) for v in row] for row in rows]


def digest(rows):
    return hashlib.sha256(json.dumps(rows, separators=(",", ":")).encode()).hexdigest()


def sort_key(row):
    return json.dumps(row)


def fingerprint(rows, ordered):
    """What expected.json stores for an answer: its shape and a hash, never its values."""
    rows = normalized_rows(rows)
    return {
        "rows": len(rows),
        "columns": len(rows[0]) if rows else 0,
        "ordered": ordered,
        "sha256": digest(rows if ordered else sorted(rows, key=sort_key)),
        "sha256_any_order": digest(sorted(rows, key=sort_key)),
    }


def read_only(path):
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True)


def run_query(connection, sql):
    """Runs exactly one statement and returns its rows."""
    try:
        return connection.execute(sql).fetchall()
    except sqlite3.ProgrammingError as error:
        if "one statement" in str(error):
            raise ValueError("write exactly one statement (a single SELECT)") from error
        raise


class Result:
    def __init__(self, status, message=""):
        self.status, self.message = status, message  # "pass" | "fail" | "todo"


def check_rows(exercise, sql, database, expected):
    want = expected[exercise["id"]]
    connection = read_only(database)
    try:
        rows = run_query(connection, sql)
    except (sqlite3.Error, ValueError) as error:
        return Result("fail", f"the query did not run: {error}")
    finally:
        connection.close()
    got = fingerprint(rows, want["ordered"])
    if got["columns"] != want["columns"] and got["rows"]:
        return Result("fail", f"{got['columns']} columns; the answer has {want['columns']}")
    if got["rows"] != want["rows"]:
        return Result("fail", f"{got['rows']} rows; the answer has {want['rows']}")
    if got["sha256"] == want["sha256"]:
        return Result("pass")
    if want["ordered"] and got["sha256_any_order"] == want["sha256_any_order"]:
        return Result("fail", "the right rows in the wrong order; this one asks for an order")
    return Result("fail", "the right number of rows, but some values differ")


def statements(sql):
    return [s.strip() for s in strip_comments(sql).split(";") if s.strip()]


def plan(connection, query):
    return [row[-1] for row in connection.execute("EXPLAIN QUERY PLAN " + query)]


def check_index(exercise, sql, database):
    for statement in statements(sql):
        if re.match(r"(?i)CREATE\s+UNIQUE\s+INDEX\b", statement):
            return Result("fail", "no UNIQUE index: the app's store syncs through CloudKit, which can't "
                                  "keep a uniqueness rule (see the README)")
        if not re.match(r"(?i)CREATE\s+INDEX\b", statement):
            return Result("fail", "only CREATE INDEX statements belong in this answer")
    with tempfile.TemporaryDirectory() as folder:
        scratch = Path(folder) / "scratch.sqlite"
        shutil.copyfile(database, scratch)
        connection = sqlite3.connect(scratch)
        try:
            before = sorted(normalized_rows(connection.execute(exercise["query"]).fetchall()), key=sort_key)
            connection.executescript(sql)
            steps = plan(connection, exercise["query"])
            after = sorted(normalized_rows(connection.execute(exercise["query"]).fetchall()), key=sort_key)
        except sqlite3.Error as error:
            return Result("fail", f"the statements did not run: {error}")
        finally:
            connection.close()
    shown = "; ".join(steps)
    if any(re.match(rf"SCAN (TABLE )?{exercise['table']}\b", step) for step in steps):
        return Result("fail", f"the query still reads all of {exercise['table']}: {shown}")
    if any("TEMP B-TREE" in step for step in steps):
        return Result("fail", f"the query still sorts after reading: {shown}")
    if before != after:
        return Result("fail", "the query's rows changed")
    return Result("pass", shown)


def plant(kind, connection, rng, decoy_last):
    """Adds one defect to a scratch copy and returns what a correct check must report."""
    # Each defect comes with a decoy: a new row that is fine. The check runs once with the decoy
    # added after the bad row and once before it, so "the newest row" or "a key above the old
    # maximum" is never a working check.
    if kind == "orphan_exercise":
        low, high = sorted(rng.sample(range(5000, 9999), 2))
        bad, decoy = (low, high) if decoy_last else (high, low)
        connection.execute(
            "INSERT INTO ZEXERCISEENTRY (Z_PK, Z_ENT, Z_OPT, ZREPS, ZSETS, ZDATE, ZWEIGHTLBS, ZMACHINEKEY, ZID, ZSESSIONID) "
            "SELECT ?, Z_ENT, 1, 10, 3, ZDATE, 100, ZMACHINEKEY, randomblob(16), randomblob(16) "
            "FROM ZEXERCISEENTRY LIMIT 1", (bad,))
        connection.execute(
            "INSERT INTO ZEXERCISEENTRY (Z_PK, Z_ENT, Z_OPT, ZREPS, ZSETS, ZDATE, ZWEIGHTLBS, ZMACHINEKEY, ZID, ZSESSIONID) "
            "SELECT ?, Z_ENT, 1, 8, 3, ZDATE, 90, ZMACHINEKEY, randomblob(16), ZSESSIONID "
            "FROM ZEXERCISEENTRY WHERE Z_PK < 5000 LIMIT 1", (decoy,))
        return {normalize(bad)}
    if kind == "duplicate_steps_day":
        days = [row[0] for row in connection.execute("SELECT ZDATE FROM ZSTEPSENTRY ORDER BY ZDATE")]
        day = rng.choice(days)
        new_day = days[-1] + 86400  # the day after the last one: a new day, not a duplicate
        for when in ((day, new_day) if decoy_last else (new_day, day)):
            connection.execute(
                "INSERT INTO ZSTEPSENTRY (Z_PK, Z_ENT, Z_OPT, ZCOUNT, ZCREATEDAT, ZDATE, ZID) "
                "SELECT MAX(Z_PK) + 1, Z_ENT, 1, ?, ZCREATEDAT, ?, randomblob(16) FROM ZSTEPSENTRY",
                (rng.randint(2000, 15000), when))
        label = connection.execute("SELECT date(? + 978307200, 'unixepoch', 'localtime')", (day,)).fetchone()[0]
        return {label}
    raise KeyError(kind)


def check_detects(exercise, sql, database, rng):
    connection = read_only(database)
    try:
        clean = run_query(connection, sql)
    except (sqlite3.Error, ValueError) as error:
        return Result("fail", f"the query did not run: {error}")
    finally:
        connection.close()
    if clean:
        return Result("fail", f"it reports {len(clean)} rows on the clean database, which has no such defect")
    for decoy_last in (True, False):
        with tempfile.TemporaryDirectory() as folder:
            scratch = Path(folder) / "scratch.sqlite"
            shutil.copyfile(database, scratch)
            connection = sqlite3.connect(scratch)
            try:
                want = plant(exercise["plant"], connection, rng, decoy_last)
                connection.commit()
                got = {normalize(row[0]) for row in run_query(connection, sql) if row}
            except (sqlite3.Error, ValueError) as error:
                return Result("fail", f"the query did not run on the planted copy: {error}")
            finally:
                connection.close()
        if got != want:
            return Result("fail", f"with one planted defect it reported {len(got)} rows, not the one bad "
                                  f"row (its first column should identify the bad row or day)")
    return Result("pass")


def check(exercise, folder, database=DATABASE, expected=None, rng=None):
    path = Path(folder) / exercise["file"]
    if not path.exists():
        return Result("todo", f"no file {path.name}")
    sql = path.read_text()
    if not strip_comments(sql):
        return Result("todo")
    if exercise["kind"] == "rows":
        return check_rows(exercise, sql, database, expected or load_expected())
    if exercise["kind"] == "index":
        return check_index(exercise, sql, database)
    return check_detects(exercise, sql, database, rng or random.Random())


def load_expected():
    return json.loads(EXPECTED.read_text())


def record(database=DATABASE, solutions=SOLUTIONS):
    expected = {}
    for exercise in EXERCISES:
        if exercise["kind"] != "rows":
            continue
        connection = read_only(database)
        rows = run_query(connection, (Path(solutions) / exercise["file"]).read_text())
        connection.close()
        expected[exercise["id"]] = fingerprint(rows, exercise["ordered"])
    return expected


def run(ids, folder, require_all):
    use_demo_zone()
    expected = load_expected()
    counts = {"pass": 0, "fail": 0, "todo": 0}
    for exercise in [BY_ID[i] for i in ids]:
        result = check(exercise, folder, expected=expected)
        counts[result.status] += 1
        note = f"  {result.message}" if result.message and result.status != "pass" else ""
        print(f"{exercise['id']}  {result.status.upper():4}  {exercise['file']}{note}")
    print(f"\n{counts['pass']} passed, {counts['fail']} failed, {counts['todo']} to do")
    if counts["fail"] or (require_all and counts["todo"]):
        return 1
    return 0


class CheckerTests(unittest.TestCase):
    """The checker must pass the reference answers and catch each kind of wrong answer."""

    def setUp(self):
        use_demo_zone()
        self.folder = Path(tempfile.mkdtemp())
        self.expected = load_expected()

    def tearDown(self):
        shutil.rmtree(self.folder)

    def answer(self, exercise_id, sql):
        exercise = BY_ID[exercise_id]
        (self.folder / exercise["file"]).write_text(sql)
        return check(exercise, self.folder, expected=self.expected, rng=random.Random(7))

    def solution(self, exercise_id):
        return (SOLUTIONS / BY_ID[exercise_id]["file"]).read_text()

    def test_every_reference_answer_passes(self):
        for exercise in EXERCISES:
            for seed in (1, 2, 3):  # the planted defects differ by seed
                result = check(exercise, SOLUTIONS, expected=self.expected, rng=random.Random(seed))
                self.assertEqual(result.status, "pass", f"{exercise['id']}: {result.message}")

    def test_expected_json_is_what_the_reference_answers_produce(self):
        self.assertEqual(record(), self.expected)

    def test_every_exercise_has_a_question_and_starts_unanswered(self):
        for exercise in EXERCISES:
            text = (EXERCISES_DIR / exercise["file"]).read_text()
            self.assertTrue(text.lstrip().startswith("--"), exercise["file"])
            result = check(exercise, EXERCISES_DIR, expected=self.expected)
            self.assertEqual(result.status, "todo", exercise["file"])

    def test_a_missing_or_comment_only_file_is_todo_not_a_failure(self):
        self.assertEqual(check(BY_ID["01"], self.folder, expected=self.expected).status, "todo")
        self.assertEqual(self.answer("01", "-- thinking...\n/* later */\n").status, "todo")

    def test_wrong_order_is_reported_as_order(self):
        sql = self.solution("01").replace("ORDER BY name", "ORDER BY name DESC")
        result = self.answer("01", sql)
        self.assertEqual(result.status, "fail")
        self.assertIn("wrong order", result.message)

    def test_order_does_not_matter_where_none_is_asked(self):
        sql = self.solution("04").rstrip().rstrip(";") + " ORDER BY ZNAME DESC;"
        self.assertEqual(self.answer("04", sql).status, "pass")

    def test_a_wrong_count_and_wrong_values_are_reported(self):
        self.assertIn("rows", self.answer("01", "SELECT name FROM sqlite_master WHERE type = 'table'").message)
        fixed_offset = self.solution("03").replace("'localtime'", "'-8 hours'")
        result = self.answer("03", fixed_offset)  # wrong before daylight saving ended on 1 November
        self.assertEqual(result.status, "fail")
        self.assertIn("values differ", result.message)

    def test_column_names_and_integer_or_float_do_not_matter(self):
        sql = "SELECT CAST(ROUND(AVG(ZASLEEPMINUTES) / 60.0, 2) AS TEXT) * 1 AS hours FROM ZSLEEPENTRY"
        self.assertEqual(self.answer("06", sql).status, "pass")

    def test_the_database_cannot_be_changed(self):
        before = hashlib.sha256(DATABASE.read_bytes()).hexdigest()
        result = self.answer("01", "DELETE FROM ZFOODENTRY")
        self.assertEqual(result.status, "fail")
        self.assertIn("readonly", result.message.replace("-", ""))
        self.assertEqual(hashlib.sha256(DATABASE.read_bytes()).hexdigest(), before)

    def test_two_statements_are_refused(self):
        result = self.answer("06", "SELECT 1; SELECT 2;")
        self.assertIn("one statement", result.message)

    def test_index_answers_must_be_plain_create_index(self):
        self.assertIn("UNIQUE", self.answer("11", "CREATE UNIQUE INDEX x ON ZEXERCISEENTRY (ZID);").message)
        self.assertIn("only CREATE INDEX", self.answer("11", "DROP TABLE ZEXERCISEENTRY;").message)

    def test_an_index_on_the_wrong_column_still_scans_or_sorts(self):
        self.assertIn("reads all", self.answer("11", "CREATE INDEX x ON ZEXERCISEENTRY (ZREPS);").message)
        self.assertIn("sorts", self.answer("11", "CREATE INDEX x ON ZEXERCISEENTRY (ZMACHINEKEY);").message)
        self.assertEqual(self.answer("12", "CREATE INDEX x ON ZFOODENTRY (ZNAME);").status, "fail")

    def test_the_reference_database_has_no_indexes_to_start_with(self):
        connection = read_only(DATABASE)
        plan_11 = plan(connection, BY_ID["11"]["query"])
        connection.close()
        self.assertTrue(any(step.startswith("SCAN") for step in plan_11), plan_11)

    def test_a_check_that_reports_everything_or_a_fixed_row_fails(self):
        self.assertIn("clean database", self.answer("13", "SELECT Z_PK FROM ZEXERCISEENTRY").message)
        self.assertEqual(self.answer("13", "SELECT Z_PK FROM ZEXERCISEENTRY WHERE Z_PK = 7777").status, "fail")
        self.assertEqual(self.answer("14", "SELECT '2026-11-23' WHERE 0").status, "fail")

    def test_newest_row_shortcuts_do_not_pass(self):
        for seed in range(1, 6):
            rng = random.Random(seed)
            for exercise_id, sql in [
                    ("13", "SELECT Z_PK FROM ZEXERCISEENTRY WHERE Z_PK > 11"),
                    ("14", "SELECT date(ZDATE + 978307200, 'unixepoch', 'localtime') FROM ZSTEPSENTRY "
                           "WHERE Z_PK = (SELECT MAX(Z_PK) FROM ZSTEPSENTRY) AND Z_PK > 7")]:
                exercise = BY_ID[exercise_id]
                (self.folder / exercise["file"]).write_text(sql)
                result = check(exercise, self.folder, expected=self.expected, rng=rng)
                self.assertEqual(result.status, "fail", f"{exercise_id} seed {seed}")

    def test_the_zone_is_set_whatever_the_machine_uses(self):
        os.environ["TZ"] = "Pacific/Honolulu"  # Los Angeles midnight is 22:00 the day before there
        time.tzset()
        try:
            self.assertEqual(check(BY_ID["03"], SOLUTIONS, expected=self.expected).status, "fail")
            use_demo_zone()
            self.assertEqual(check(BY_ID["03"], SOLUTIONS, expected=self.expected).status, "pass")
        finally:
            use_demo_zone()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("ids", nargs="*", help="exercise numbers, e.g. 03 07 (default: all)")
    parser.add_argument("--answers", default=str(EXERCISES_DIR), help="folder of answer files")
    parser.add_argument("--all", action="store_true", help="an exercise not attempted counts as a failure")
    parser.add_argument("--record", action="store_true", help="rewrite expected.json from solutions/")
    parser.add_argument("--self-test", action="store_true", help="run the checker's own tests")
    args = parser.parse_args(argv)
    if args.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(CheckerTests)
        return 0 if unittest.TextTestRunner(verbosity=1).run(suite).wasSuccessful() else 1
    if args.record:
        use_demo_zone()
        EXPECTED.write_text(json.dumps(record(), indent=2, sort_keys=True) + "\n")
        print(f"wrote {EXPECTED.relative_to(HERE.parent.parent)}")
        return 0
    ids = [i.zfill(2) for i in args.ids] or [e["id"] for e in EXERCISES]
    unknown = [i for i in ids if i not in BY_ID]
    if unknown:
        print(f"no exercise {', '.join(unknown)}; there are {EXERCISES[0]['id']} to {EXERCISES[-1]['id']}")
        return 2
    return run(ids, args.answers, args.all)


if __name__ == "__main__":
    sys.exit(main())
