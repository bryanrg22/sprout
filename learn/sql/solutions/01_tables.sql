SELECT name FROM sqlite_master
WHERE type = 'table' AND name GLOB 'Z[A-Z]*'
ORDER BY name;
