SELECT date(ZDATE + 978307200, 'unixepoch', 'localtime') AS day
FROM ZSTEPSENTRY
GROUP BY day
HAVING COUNT(*) > 1;
