-- =====================================================================
-- 05_analytics / 02_create_powerbi_reader.sql
-- Usuario de SOLO LECTURA para Power BI (principio de mínimo privilegio).
-- Power BI ve únicamente el esquema analytics: no puede leer las tablas
-- operacionales directamente ni modificar nada.
--
-- Reemplaza <CONTRASEÑA_SEGURA> SOLO al ejecutar; no la guardes en git.
-- Usuario "contenido" en la base: no necesita login en master.
-- =====================================================================

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'powerbi_reader')
    CREATE USER powerbi_reader WITH PASSWORD = 'MiClaveSegura2026!';
GO

GRANT SELECT ON SCHEMA::analytics TO powerbi_reader;
GO

-- Comprobación de permisos
SELECT pr.name AS usuario, pe.permission_name, pe.state_desc,
       SCHEMA_NAME(pe.major_id) AS esquema
FROM sys.database_permissions AS pe
JOIN sys.database_principals  AS pr ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name = 'powerbi_reader';
GO

-- Prueba (opcional): ejecutar como el usuario lector
-- EXECUTE AS USER = 'powerbi_reader';
--     SELECT TOP 5 * FROM analytics.fact_sales;          -- debe funcionar
--     SELECT TOP 5 * FROM sales.sales_order;             -- debe fallar (permiso denegado)
-- REVERT;
