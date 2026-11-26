SELECT ZNAME,
       date(ZDATE + 978307200, 'unixepoch', 'localtime') AS la_day,
       date(ZDATE + 978307200, 'unixepoch') AS utc_day
FROM ZFOODENTRY
WHERE date(ZDATE + 978307200, 'unixepoch', 'localtime') <> date(ZDATE + 978307200, 'unixepoch');
