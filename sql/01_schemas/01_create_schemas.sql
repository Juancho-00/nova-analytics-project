CREATE SCHEMA master;
GO

CREATE SCHEMA sales;
GO

CREATE SCHEMA inventory;
GO

CREATE SCHEMA production;
GO

SELECT name
FROM sys.schemas
WHERE name IN ('master', 'sales', 'inventory', 'production');