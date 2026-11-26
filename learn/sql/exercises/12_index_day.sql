-- 12 · An index for a range (performance)
--
-- Today's food is a range of dates:
--     SELECT ZNAME, ZCALORIES FROM ZFOODENTRY WHERE ZDATE >= 817286400 AND ZDATE < 817372800
-- (2026-11-25 00:00 to 2026-11-26 00:00 in Los Angeles, in seconds since 2001.) Write the
-- CREATE INDEX statement after which its plan reads only that range instead of the table.
--
-- Your answer below. Run:  python3 learn/sql/check.py 12

