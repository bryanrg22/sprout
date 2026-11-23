#!/usr/bin/env python3
"""Read-only verification report for a Sprout SwiftData store.

    python3 tooling/verify_store.py <path/to/default.store> [--tz America/Los_Angeles]
                                    [--today 2026-11-22] [--days 14]
    python3 tooling/verify_store.py --self-test

The store is opened with SQLite's `mode=ro`; nothing is written. In the simulator it is at
  ~/Library/Developer/CoreSimulator/Devices/<udid>/data/Containers/Shared/AppGroup/<id>/
      Library/Application Support/default.store
(keep `default.store-wal` and `default.store-shm` beside it: recent rows live in the WAL).

The report has three parts:
  1. every entity table (`Z*`, without Core Data's own `Z_*` tables) and its row count;
  2. per-day totals of food, water, steps and weigh-ins for the last --days days;
  3. consistency checks. Any violation makes the exit status 1:
       null-id        a row whose ZID is NULL, in a table whose model defines `id`
       negative       a negative calorie, macro, weight, ounce or step value
       duplicate-day  two rows on one calendar day in a one-row-per-day table
                      (steps, sleep, vitals)
       schema         a table or column these checks need is missing, so a check
                      could not run (a rename must not turn a check off silently)
Warnings (more than one profile, a repeated HealthKit id) are printed and do not change
the exit status.

Core Data stores a date as seconds since 2001-01-01 00:00:00 UTC; add 978307200 for Unix
time. Rows are stored at the device's local midnight, so days are counted in --tz (default:
this machine's zone). Exit status: 0 clean, 1 violations, 2 the store could not be read.
"""
import argparse
import datetime as dt
import os
import sqlite3
import sys
import tempfile
import unittest
import urllib.parse
from zoneinfo import ZoneInfo

APPLE_EPOCH = 978307200  # seconds from 1970-01-01 to 2001-01-01, both UTC

# Columns that can never be negative. `ZBUDDYSNAPSHOT.ZWEEKLYRATELBS` is signed on purpose
# and is not listed.
NON_NEGATIVE = {
    "ZFOODENTRY": ["ZCALORIES", "ZPROTEING", "ZCARBSG", "ZFATG", "ZQUANTITY", "ZCALORIESLOW", "ZCALORIESHIGH"],
    "ZWEIGHTENTRY": ["ZWEIGHTLBS"],
    "ZWATERENTRY": ["ZAMOUNTOZ"],
    "ZSTEPSENTRY": ["ZCOUNT"],
    "ZEXERCISEENTRY": ["ZWEIGHTLBS"],
    "ZUSERPROFILE": ["ZSTARTWEIGHTLBS", "ZGOALWEIGHTLBS", "ZWATERGOALOZOVERRIDE", "ZWATERCONTAINEROZ",
                     "ZDAILYSTEPGOAL", "ZCALORIETARGETOVERRIDE", "ZCALORIEMAXOVERRIDE", "ZPROTEINTARGETOVERRIDE"],
    "ZCOACHPLAN": ["ZCALORIEMIN", "ZCALORIEMAX", "ZPROTEINTARGET"],
    "ZBUDDYSNAPSHOT": ["ZSTEPSTODAY", "ZSTEPGOAL", "ZWATERTODAY", "ZWATERGOAL", "ZTRENDWEIGHTLBS", "ZGOALWEIGHTLBS",
                       "ZCALORIESEATEN", "ZCALORIETARGET", "ZPROTEINEATEN", "ZPROTEINTARGET",
                       "ZCARBSEATEN", "ZCARBTARGET", "ZFATEATEN", "ZFATTARGET"],
    "ZDETECTEDWORKOUT": ["ZCALORIESBURNED"],
    "ZWORKOUTENTRY": ["ZCALORIESBURNED"],
}
# Tables that hold one row per calendar day, keyed by ZDATE at local midnight.
ONE_ROW_PER_DAY = ["ZSTEPSENTRY", "ZSLEEPENTRY", "ZVITALSENTRY"]
# Tables whose HealthKit id is the import's dedup key.
UNIQUE_HEALTHKIT_ID = ["ZDETECTEDWORKOUT", "ZWEIGHTENTRY"]


def open_read_only(path):
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    uri = "file:" + urllib.parse.quote(os.path.abspath(path)) + "?mode=ro"
    con = sqlite3.connect(uri, uri=True)
    try:
        con.execute("SELECT count(*) FROM sqlite_master").fetchone()  # fails here if it is not a database
    except sqlite3.Error:
        con.close()
        raise
    return con


def machine_zone():
    try:
        target = os.path.realpath("/etc/localtime")
        if "zoneinfo/" in target:
            return ZoneInfo(target.split("zoneinfo/", 1)[1])
    except Exception:
        pass
    return ZoneInfo("UTC")


def entity_tables(con):
    """Core Data entity tables: Z-prefixed, without the Z_ bookkeeping tables."""
    rows = con.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").fetchall()
    return [name for (name,) in rows if name.startswith("Z") and not name.startswith("Z_")]


def columns(con, table):
    return [row[1] for row in con.execute(f'PRAGMA table_info("{table}")')]


def local_day(core_data_seconds, zone):
    """The calendar day, in `zone`, of a Core Data timestamp."""
    return dt.datetime.fromtimestamp(core_data_seconds + APPLE_EPOCH, zone).date()


def examine(con, zone, today, days=14):
    """Everything the report prints, as plain data."""
    tables = entity_tables(con)
    cols = {t: columns(con, t) for t in tables}
    report = {"zone": str(zone), "today": today, "days": days, "tables": [], "daily": [],
              "violations": [], "warnings": [], "checked": {"null-id": [], "negative": [], "duplicate-day": []}}

    names = {}
    if "Z_PRIMARYKEY" in [r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")]:
        names = {"Z" + n.upper(): n for (n,) in con.execute("SELECT Z_NAME FROM Z_PRIMARYKEY")}
    for t in tables:
        count = con.execute(f'SELECT count(*) FROM "{t}"').fetchone()[0]
        report["tables"].append((t, names.get(t, "?"), count))

    def violation(rule, table, detail):
        report["violations"].append((rule, table, detail))

    def has(table, column, needed_by):
        if table not in cols:
            violation("schema", table, f"table not found; {needed_by} could not run")
            return False
        if column not in cols[table]:
            violation("schema", table, f"column {column} not found; {needed_by} could not run")
            return False
        return True

    # --- null-id: every table whose model defines `id` has a ZID column.
    for t in tables:
        if "ZID" in cols[t]:
            report["checked"]["null-id"].append(t)
            n = con.execute(f'SELECT count(*) FROM "{t}" WHERE ZID IS NULL').fetchone()[0]
            if n:
                pks = [str(r[0]) for r in con.execute(f'SELECT Z_PK FROM "{t}" WHERE ZID IS NULL ORDER BY Z_PK LIMIT 5')]
                violation("null-id", t, f"{n} row(s) with a NULL id (Z_PK {', '.join(pks)})")

    # --- negative values.
    for t, wanted in NON_NEGATIVE.items():
        for c in wanted:
            if not has(t, c, "the negative-value check"):
                continue
            report["checked"]["negative"].append(f"{t}.{c}")
            n = con.execute(f'SELECT count(*) FROM "{t}" WHERE "{c}" < 0').fetchone()[0]
            if n:
                worst = con.execute(f'SELECT Z_PK, "{c}" FROM "{t}" WHERE "{c}" < 0 ORDER BY "{c}" LIMIT 1').fetchone()
                violation("negative", t, f"{n} row(s) with {c} < 0 (lowest {worst[1]} at Z_PK {worst[0]})")

    # --- one row per calendar day.
    for t in ONE_ROW_PER_DAY:
        if not has(t, "ZDATE", "the one-row-per-day check"):
            continue
        report["checked"]["duplicate-day"].append(t)
        per_day = {}
        for pk, z in con.execute(f'SELECT Z_PK, ZDATE FROM "{t}" WHERE ZDATE IS NOT NULL ORDER BY ZDATE, Z_PK'):
            per_day.setdefault(local_day(z, zone), []).append(pk)
        for day, pks in sorted(per_day.items()):
            if len(pks) > 1:
                violation("duplicate-day", t, f"{len(pks)} rows on {day} (Z_PK {', '.join(map(str, pks))})")

    # --- warnings: reported, not failed.
    if "ZUSERPROFILE" in cols:
        n = con.execute('SELECT count(*) FROM "ZUSERPROFILE"').fetchone()[0]
        if n > 1:
            report["warnings"].append(f"ZUSERPROFILE holds {n} profiles; the app reads the first one only")
    for t in UNIQUE_HEALTHKIT_ID:
        if t in cols and "ZHEALTHKITUUID" in cols[t]:
            for uuid, n in con.execute(f'SELECT ZHEALTHKITUUID, count(*) FROM "{t}" WHERE ZHEALTHKITUUID IS NOT NULL '
                                       f"AND ZHEALTHKITUUID != '' GROUP BY 1 HAVING count(*) > 1"):
                report["warnings"].append(f"{t}: HealthKit id {uuid} is on {n} rows")

    # --- per-day totals for the window that ends on `today`.
    window = [today - dt.timedelta(days=i) for i in range(days - 1, -1, -1)]
    daily = {d: {"food_n": 0, "kcal": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0,
                 "water_n": 0, "oz": 0.0, "steps_n": 0, "steps": 0, "weight_n": 0, "weight_sum": 0.0}
             for d in window}

    def rows_in_window(table, select):
        if table not in cols or "ZDATE" not in cols[table] or any(c not in cols[table] for c in select):
            violation("schema", table, "per-day totals could not be computed: table or column not found")
            return
        for row in con.execute(f'SELECT ZDATE, {", ".join(select)} FROM "{table}" WHERE ZDATE IS NOT NULL'):
            day = local_day(row[0], zone)
            if day in daily:
                yield daily[day], row[1:]

    # Food totals are per-serving values x servings, as the app sums them (FoodEntry.total*).
    for d, (kcal, protein, carbs, fat, quantity) in rows_in_window(
            "ZFOODENTRY", ["ZCALORIES", "ZPROTEING", "ZCARBSG", "ZFATG", "ZQUANTITY"]):
        q = 1.0 if quantity is None else quantity
        d["food_n"] += 1
        d["kcal"] += (kcal or 0) * q
        d["protein"] += (protein or 0) * q
        d["carbs"] += (carbs or 0) * q
        d["fat"] += (fat or 0) * q
    for d, (oz,) in rows_in_window("ZWATERENTRY", ["ZAMOUNTOZ"]):
        d["water_n"] += 1
        d["oz"] += oz or 0
    for d, (count,) in rows_in_window("ZSTEPSENTRY", ["ZCOUNT"]):
        d["steps_n"] += 1
        d["steps"] += count or 0
    for d, (lbs,) in rows_in_window("ZWEIGHTENTRY", ["ZWEIGHTLBS"]):
        d["weight_n"] += 1
        d["weight_sum"] += lbs or 0
    report["daily"] = [(day, daily[day]) for day in window]
    return report


def render(report, path):
    out = [f"Store: {path}", f"Days counted in {report['zone']}; window ends {report['today']}", ""]
    out.append(f"1. Entity tables ({len(report['tables'])})")
    out.append(f"   {'table':<20} {'entity':<18} {'rows':>6}")
    for table, entity, count in report["tables"]:
        out.append(f"   {table:<20} {entity:<18} {count:>6}")
    out.append("")
    out.append(f"2. Per-day totals, last {report['days']} days (food = per-serving value x servings)")
    out.append(f"   {'day':<10} | {'food':>4} {'kcal':>7} {'prot g':>7} {'carb g':>7} {'fat g':>7} | "
               f"{'water':>5} {'oz':>6} | {'rows':>4} {'steps':>6} | {'wts':>3} {'avg lb':>7}")
    for day, d in report["daily"]:
        avg = f"{d['weight_sum'] / d['weight_n']:.1f}" if d["weight_n"] else "-"
        out.append(f"   {day} | {d['food_n']:>4} {d['kcal']:>7.0f} {d['protein']:>7.1f} {d['carbs']:>7.1f} "
                   f"{d['fat']:>7.1f} | {d['water_n']:>5} {d['oz']:>6.1f} | {d['steps_n']:>4} {d['steps']:>6} | "
                   f"{d['weight_n']:>3} {avg:>7}")
    out.append("")
    out.append("3. Consistency checks")
    checked = report["checked"]
    out.append(f"   null-id        {len(checked['null-id'])} tables with an id column")
    out.append(f"   negative       {len(checked['negative'])} columns")
    out.append(f"   duplicate-day  {', '.join(checked['duplicate-day']) or 'none'}")
    for warning in report["warnings"]:
        out.append(f"   WARNING  {warning}")
    for rule, table, detail in report["violations"]:
        out.append(f"   VIOLATION [{rule}] {table}: {detail}")
    out.append("")
    n = len(report["violations"])
    out.append("RESULT: OK, no violations" if n == 0 else f"RESULT: FAILED, {n} violation(s)")
    return "\n".join(out)


def run(path, zone, today, days, stream=sys.stdout):
    try:
        con = open_read_only(path)
    except (FileNotFoundError, sqlite3.Error) as error:
        print(f"cannot read the store at {path}: {error}", file=sys.stderr)
        return 2
    try:
        report = examine(con, zone, today, days)
    except sqlite3.Error as error:
        print(f"cannot read the store at {path}: {error}", file=sys.stderr)
        return 2
    finally:
        con.close()
    print(render(report, path), file=stream)
    return 1 if report["violations"] else 0


# ----------------------------------------------------------------------------------------
# Self-test: temporary stores with the real table and column names, one violation each.

LA = ZoneInfo("America/Los_Angeles")


def core_data_time(year, month, day, hour=0, minute=0, second=0, zone=LA):
    return dt.datetime(year, month, day, hour, minute, second, tzinfo=zone).timestamp() - APPLE_EPOCH


SELF_TEST_SCHEMA = """
CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER);
CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID VARCHAR(255), Z_PLIST BLOB);
CREATE TABLE ZFOODENTRY (Z_PK INTEGER PRIMARY KEY, ZCALORIES FLOAT, ZCALORIESHIGH FLOAT, ZCALORIESLOW FLOAT,
  ZCARBSG FLOAT, ZDATE TIMESTAMP, ZFATG FLOAT, ZPROTEING FLOAT, ZQUANTITY FLOAT, ZNAME VARCHAR, ZID BLOB);
CREATE TABLE ZWEIGHTENTRY (Z_PK INTEGER PRIMARY KEY, ZDATE TIMESTAMP, ZWEIGHTLBS FLOAT, ZHEALTHKITUUID VARCHAR, ZID BLOB);
CREATE TABLE ZWATERENTRY (Z_PK INTEGER PRIMARY KEY, ZAMOUNTOZ FLOAT, ZDATE TIMESTAMP, ZID BLOB);
CREATE TABLE ZSTEPSENTRY (Z_PK INTEGER PRIMARY KEY, ZCOUNT INTEGER, ZDATE TIMESTAMP, ZID BLOB);
CREATE TABLE ZSLEEPENTRY (Z_PK INTEGER PRIMARY KEY, ZASLEEPMINUTES INTEGER, ZDATE TIMESTAMP, ZID BLOB);
CREATE TABLE ZVITALSENTRY (Z_PK INTEGER PRIMARY KEY, ZDATE TIMESTAMP, ZHRVMS FLOAT, ZRESTINGHEARTRATE FLOAT, ZID BLOB);
CREATE TABLE ZEXERCISEENTRY (Z_PK INTEGER PRIMARY KEY, ZDATE TIMESTAMP, ZWEIGHTLBS FLOAT, ZID BLOB);
CREATE TABLE ZUSERPROFILE (Z_PK INTEGER PRIMARY KEY, ZSTARTWEIGHTLBS FLOAT, ZGOALWEIGHTLBS FLOAT,
  ZWATERGOALOZOVERRIDE FLOAT, ZWATERCONTAINEROZ FLOAT, ZDAILYSTEPGOAL INTEGER, ZCALORIETARGETOVERRIDE FLOAT,
  ZCALORIEMAXOVERRIDE FLOAT, ZPROTEINTARGETOVERRIDE FLOAT, ZID BLOB);
CREATE TABLE ZCOACHPLAN (Z_PK INTEGER PRIMARY KEY, ZCALORIEMIN FLOAT, ZCALORIEMAX FLOAT, ZPROTEINTARGET FLOAT, ZID BLOB);
CREATE TABLE ZBUDDYSNAPSHOT (Z_PK INTEGER PRIMARY KEY, ZSTEPSTODAY INTEGER, ZSTEPGOAL INTEGER, ZWATERTODAY FLOAT,
  ZWATERGOAL FLOAT, ZTRENDWEIGHTLBS FLOAT, ZGOALWEIGHTLBS FLOAT, ZWEEKLYRATELBS FLOAT, ZCALORIESEATEN FLOAT,
  ZCALORIETARGET FLOAT, ZPROTEINEATEN FLOAT, ZPROTEINTARGET FLOAT, ZCARBSEATEN FLOAT, ZCARBTARGET FLOAT,
  ZFATEATEN FLOAT, ZFATTARGET FLOAT);
CREATE TABLE ZDETECTEDWORKOUT (Z_PK INTEGER PRIMARY KEY, ZCALORIESBURNED FLOAT, ZDATE TIMESTAMP,
  ZHEALTHKITUUID VARCHAR, ZID BLOB);
CREATE TABLE ZWORKOUTENTRY (Z_PK INTEGER PRIMARY KEY, ZCALORIESBURNED FLOAT, ZDATE TIMESTAMP, ZID BLOB);
CREATE TABLE ZACHIEVEMENTUNLOCK (Z_PK INTEGER PRIMARY KEY, ZUNLOCKEDAT TIMESTAMP, ZACHIEVEMENTID VARCHAR);
"""


def build_clean_store(path):
    """A small consistent store. "Today" is 20 February 2026 in Los Angeles."""
    con = sqlite3.connect(path)
    con.executescript(SELF_TEST_SCHEMA)
    ident = b"\x01" * 16
    con.executemany("INSERT INTO Z_PRIMARYKEY VALUES (?,?,0,0)",
                    [(1, "AchievementUnlock"), (2, "FoodEntry"), (3, "StepsEntry"), (4, "WaterEntry"), (5, "WeightEntry")])
    con.executemany(
        "INSERT INTO ZFOODENTRY (ZDATE, ZNAME, ZQUANTITY, ZCALORIES, ZPROTEING, ZCARBSG, ZFATG, ZID) VALUES (?,?,?,?,?,?,?,?)",
        [(core_data_time(2026, 2, 20, 0, 0, 0), "Midnight tea", 1, 5, 0, 1, 0, ident),
         (core_data_time(2026, 2, 20, 12, 45), "Chicken bowl", 1.5, 480, 40, 50, 12, ident),
         (core_data_time(2026, 2, 20, 23, 59, 59), "Yogurt", 2, 90, 9, 7, 2.5, ident),
         (core_data_time(2026, 2, 19, 23, 59, 59), "Pasta", 1, 650, 22, 90, 18, ident),
         (core_data_time(2026, 2, 21, 0, 0, 0), "Tomorrow", 1, 300, 10, 50, 5, ident),
         (core_data_time(2026, 2, 6, 12), "Too old", 1, 999, 9, 9, 9, ident)])
    con.executemany("INSERT INTO ZWATERENTRY (ZDATE, ZAMOUNTOZ, ZID) VALUES (?,?,?)",
                    [(core_data_time(2026, 2, 20, 9), 16.5, ident), (core_data_time(2026, 2, 20, 15, 30), 12, ident),
                     (core_data_time(2026, 2, 19, 8), 20, ident)])
    con.executemany("INSERT INTO ZSTEPSENTRY (ZDATE, ZCOUNT, ZID) VALUES (?,?,?)",
                    [(core_data_time(2026, 2, 19), 10250, ident), (core_data_time(2026, 2, 20), 4321, ident)])
    con.executemany("INSERT INTO ZSLEEPENTRY (ZDATE, ZASLEEPMINUTES, ZID) VALUES (?,?,?)",
                    [(core_data_time(2026, 2, 19), 432, ident), (core_data_time(2026, 2, 20), 401, ident)])
    con.executemany("INSERT INTO ZVITALSENTRY (ZDATE, ZRESTINGHEARTRATE, ZHRVMS, ZID) VALUES (?,?,?,?)",
                    [(core_data_time(2026, 2, 19), 58, 46.5, ident), (core_data_time(2026, 2, 20), 60.5, 44, ident)])
    con.executemany("INSERT INTO ZWEIGHTENTRY (ZDATE, ZWEIGHTLBS, ZHEALTHKITUUID, ZID) VALUES (?,?,?,?)",
                    [(core_data_time(2026, 2, 20, 7), 179, None, ident), (core_data_time(2026, 2, 20, 21), 181, None, ident),
                     (core_data_time(2026, 2, 13, 7), 180, "HK-1", ident)])
    con.execute("INSERT INTO ZUSERPROFILE (ZSTARTWEIGHTLBS, ZGOALWEIGHTLBS, ZDAILYSTEPGOAL, ZID) VALUES (158, 172, 8000, ?)", (ident,))
    con.execute("INSERT INTO ZBUDDYSNAPSHOT (ZSTEPSTODAY, ZWEEKLYRATELBS) VALUES (4321, -0.45)")  # a signed rate is fine
    con.execute("INSERT INTO ZACHIEVEMENTUNLOCK (ZUNLOCKEDAT, ZACHIEVEMENTID) VALUES (?, 'streak_7')",
                (core_data_time(2026, 2, 14, 20),))
    con.commit()
    con.close()


class SelfTest(unittest.TestCase):
    TODAY = dt.date(2026, 2, 20)

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "default.store")
        build_clean_store(self.path)

    def tearDown(self):
        self.dir.cleanup()

    def rebuild(self):
        """A new clean store, for a test that breaks the store more than once."""
        self.tearDown()
        self.setUp()

    def break_store(self, *statements):
        con = sqlite3.connect(self.path)
        for sql in statements:
            con.execute(sql)
        con.commit()
        con.close()

    def examine(self, zone=LA):
        con = open_read_only(self.path)
        try:
            return examine(con, zone, self.TODAY, 14)
        finally:
            con.close()

    def status(self):
        with open(os.devnull, "w") as quiet:
            return run(self.path, LA, self.TODAY, 14, stream=quiet)

    def rules(self):
        return [(rule, table) for rule, table, _ in self.examine()["violations"]]

    # -- the clean store
    def test_clean_store_has_no_violations_and_exits_0(self):
        report = self.examine()
        self.assertEqual(report["violations"], [])
        self.assertEqual(report["warnings"], [])
        self.assertEqual(self.status(), 0)

    def test_every_entity_table_is_listed_with_its_row_count_and_bookkeeping_tables_are_not(self):
        tables = {t: (entity, n) for t, entity, n in self.examine()["tables"]}
        self.assertEqual(len(tables), 13)
        self.assertNotIn("Z_PRIMARYKEY", tables)
        self.assertNotIn("Z_METADATA", tables)
        self.assertEqual(tables["ZFOODENTRY"], ("FoodEntry", 6))
        self.assertEqual(tables["ZWEIGHTENTRY"], ("WeightEntry", 3))
        self.assertEqual(tables["ZACHIEVEMENTUNLOCK"], ("AchievementUnlock", 1))
        self.assertEqual(tables["ZCOACHPLAN"], ("?", 0))

    def test_per_day_totals(self):
        daily = dict(self.examine()["daily"])
        self.assertEqual(list(daily)[0], dt.date(2026, 2, 7))    # 14 days, oldest first
        self.assertEqual(list(daily)[-1], self.TODAY)
        self.assertEqual(len(daily), 14)
        today = daily[self.TODAY]
        # 5x1 + 480x1.5 + 90x2 = 905 kcal; protein 0 + 60 + 18 = 78; carbs 1 + 75 + 14 = 90; fat 0 + 18 + 5 = 23
        self.assertEqual((today["food_n"], today["kcal"], today["protein"], today["carbs"], today["fat"]),
                         (3, 905, 78, 90, 23))
        self.assertEqual((today["water_n"], today["oz"]), (2, 28.5))           # 16.5 + 12
        self.assertEqual((today["steps_n"], today["steps"]), (1, 4321))
        self.assertEqual((today["weight_n"], today["weight_sum"]), (2, 360))   # 179 + 181
        yesterday = daily[dt.date(2026, 2, 19)]
        self.assertEqual((yesterday["food_n"], yesterday["kcal"]), (1, 650))   # 23:59:59 belongs to the 19th
        self.assertEqual(yesterday["steps"], 10250)
        # 6 February is one day before the window; 21 February is after it.
        self.assertEqual(sum(d["food_n"] for d in daily.values()), 4)

    def test_dates_use_the_2001_epoch_and_the_given_zone(self):
        self.assertEqual(APPLE_EPOCH, int(dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc).timestamp()))
        self.assertEqual(local_day(0, dt.timezone.utc), dt.date(2001, 1, 1))
        # 23:59:59 on the 19th in Los Angeles is already the 20th in UTC: the pasta moves a day.
        utc = dict(self.examine(zone=ZoneInfo("UTC"))["daily"])
        self.assertEqual(utc[dt.date(2026, 2, 19)]["food_n"], 0)
        self.assertEqual(utc[dt.date(2026, 2, 20)]["kcal"], 5 + 720 + 650)

    def test_the_store_is_opened_read_only_and_left_untouched(self):
        with open(self.path, "rb") as f:
            before = f.read()
        con = open_read_only(self.path)
        with self.assertRaises(sqlite3.OperationalError):
            con.execute("DELETE FROM ZFOODENTRY")
        con.close()
        self.status()
        with open(self.path, "rb") as f:
            self.assertEqual(f.read(), before)

    def test_unreadable_store_exits_2(self):
        with open(os.devnull, "w") as quiet:
            stderr, sys.stderr = sys.stderr, quiet
            try:
                self.assertEqual(run(os.path.join(self.dir.name, "missing.store"), LA, self.TODAY, 14, quiet), 2)
                with open(self.path, "wb") as f:
                    f.write(b"this is not a database" * 100)
                self.assertEqual(run(self.path, LA, self.TODAY, 14, quiet), 2)
            finally:
                sys.stderr = stderr

    # -- one violation per rule
    def test_null_id_is_caught(self):
        self.break_store("UPDATE ZWATERENTRY SET ZID = NULL WHERE Z_PK = 2")
        self.assertEqual(self.rules(), [("null-id", "ZWATERENTRY")])
        self.assertEqual(self.status(), 1)

    def test_a_table_without_an_id_column_is_not_checked_for_null_ids(self):
        self.assertNotIn("ZACHIEVEMENTUNLOCK", self.examine()["checked"]["null-id"])
        self.assertIn("ZWATERENTRY", self.examine()["checked"]["null-id"])

    def test_negative_calories_and_each_negative_macro_are_caught(self):
        for column in ["ZCALORIES", "ZPROTEING", "ZCARBSG", "ZFATG"]:
            with self.subTest(column=column):
                self.rebuild()
                self.break_store(f"UPDATE ZFOODENTRY SET {column} = -1 WHERE Z_PK = 2")
                violations = self.examine()["violations"]
                self.assertEqual([(r, t) for r, t, _ in violations], [("negative", "ZFOODENTRY")])
                self.assertIn(column, violations[0][2])
                self.assertEqual(self.status(), 1)

    def test_negative_weight_is_caught(self):
        self.break_store("UPDATE ZWEIGHTENTRY SET ZWEIGHTLBS = -179 WHERE Z_PK = 1")
        self.assertEqual(self.rules(), [("negative", "ZWEIGHTENTRY")])
        self.assertEqual(self.status(), 1)

    def test_negative_ounces_are_caught(self):
        self.break_store("UPDATE ZWATERENTRY SET ZAMOUNTOZ = -12 WHERE Z_PK = 1")
        self.assertEqual(self.rules(), [("negative", "ZWATERENTRY")])
        self.assertEqual(self.status(), 1)

    def test_negative_steps_are_caught(self):
        self.break_store("UPDATE ZSTEPSENTRY SET ZCOUNT = -1 WHERE Z_PK = 1")
        self.assertEqual(self.rules(), [("negative", "ZSTEPSENTRY")])
        self.assertEqual(self.status(), 1)

    def test_a_signed_weekly_rate_and_a_zero_are_not_violations(self):
        self.break_store("UPDATE ZFOODENTRY SET ZCALORIES = 0, ZFATG = 0", "UPDATE ZSTEPSENTRY SET ZCOUNT = 0 WHERE Z_PK = 1",
                         "UPDATE ZBUDDYSNAPSHOT SET ZWEEKLYRATELBS = -3")
        self.assertEqual(self.rules(), [])

    def test_duplicate_day_is_caught_in_steps_sleep_and_vitals(self):
        for table, insert in [
            ("ZSTEPSENTRY", "INSERT INTO ZSTEPSENTRY (ZDATE, ZCOUNT, ZID) VALUES ({z}, 99, x'02')"),
            ("ZSLEEPENTRY", "INSERT INTO ZSLEEPENTRY (ZDATE, ZASLEEPMINUTES, ZID) VALUES ({z}, 30, x'02')"),
            ("ZVITALSENTRY", "INSERT INTO ZVITALSENTRY (ZDATE, ZRESTINGHEARTRATE, ZHRVMS, ZID) VALUES ({z}, 61, 40, x'02')"),
        ]:
            with self.subTest(table=table):
                self.rebuild()
                # A second row at 21:00 on the 19th: the same Los Angeles day as the midnight row.
                self.break_store(insert.format(z=core_data_time(2026, 2, 19, 21)))
                violations = self.examine()["violations"]
                self.assertEqual([(r, t) for r, t, _ in violations], [("duplicate-day", table)])
                self.assertIn("2026-02-19", violations[0][2])
                self.assertEqual(self.status(), 1)

    def test_rows_on_adjacent_days_are_not_duplicates(self):
        self.break_store(f"INSERT INTO ZSTEPSENTRY (ZDATE, ZCOUNT, ZID) VALUES ({core_data_time(2026, 2, 18, 23, 59, 59)}, 7, x'02')",
                         f"INSERT INTO ZSTEPSENTRY (ZDATE, ZCOUNT, ZID) VALUES ({core_data_time(2026, 2, 21)}, 8, x'02')")
        self.assertEqual(self.rules(), [])

    def test_a_missing_table_or_column_is_a_violation_not_a_silent_pass(self):
        # One column only the negative check reads, one table only the one-row-per-day check
        # reads, one column the per-day totals read.
        for sql, table, needed_by in [
            ("ALTER TABLE ZCOACHPLAN RENAME COLUMN ZCALORIEMIN TO ZFLOOR", "ZCOACHPLAN", "negative-value check"),
            ("DROP TABLE ZSLEEPENTRY", "ZSLEEPENTRY", "one-row-per-day check"),
            ("ALTER TABLE ZWATERENTRY RENAME COLUMN ZDATE TO ZWHEN", "ZWATERENTRY", "per-day totals"),
        ]:
            with self.subTest(table=table):
                self.rebuild()
                self.break_store(sql)
                violations = self.examine()["violations"]
                self.assertEqual([(r, t) for r, t, _ in violations], [("schema", table)])
                self.assertIn(needed_by, violations[0][2])
                self.assertEqual(self.status(), 1)

    def test_warnings_do_not_change_the_exit_status(self):
        self.break_store("INSERT INTO ZUSERPROFILE (ZSTARTWEIGHTLBS, ZID) VALUES (150, x'03')",
                         "INSERT INTO ZDETECTEDWORKOUT (ZHEALTHKITUUID, ZCALORIESBURNED, ZID) VALUES ('A', 1, x'04')",
                         "INSERT INTO ZDETECTEDWORKOUT (ZHEALTHKITUUID, ZCALORIESBURNED, ZID) VALUES ('A', 1, x'05')")
        report = self.examine()
        self.assertEqual(report["violations"], [])
        self.assertEqual(len(report["warnings"]), 2)
        self.assertEqual(self.status(), 0)

    def test_the_report_prints_every_part(self):
        self.break_store("UPDATE ZSTEPSENTRY SET ZCOUNT = -1 WHERE Z_PK = 1")
        text = render(self.examine(), self.path)
        for expected in ["ZFOODENTRY", "FoodEntry", "2026-02-20", "905", "VIOLATION [negative] ZSTEPSENTRY",
                         "RESULT: FAILED, 1 violation(s)"]:
            self.assertIn(expected, text)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Read-only verification report for a Sprout SwiftData store.")
    parser.add_argument("store", nargs="?", help="path to default.store")
    parser.add_argument("--tz", help="IANA zone the device was in (default: this machine's zone)")
    parser.add_argument("--today", help="last day of the window, YYYY-MM-DD (default: today in --tz)")
    parser.add_argument("--days", type=int, default=14, help="days of per-day totals (default 14)")
    parser.add_argument("--self-test", action="store_true", help="build temporary stores and check every rule fires")
    args = parser.parse_args(argv)

    if args.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(SelfTest)
        result = unittest.TextTestRunner(verbosity=1).run(suite)
        return 0 if result.wasSuccessful() and result.testsRun > 0 else 1
    if not args.store:
        parser.error("give the path to default.store, or --self-test")
    zone = ZoneInfo(args.tz) if args.tz else machine_zone()
    today = dt.date.fromisoformat(args.today) if args.today else dt.datetime.now(zone).date()
    return run(args.store, zone, today, max(1, args.days))


if __name__ == "__main__":
    sys.exit(main())
