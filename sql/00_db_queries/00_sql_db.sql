-- Queries iniciales para obtener información de la base de datos

-- 1. En qué base de datos estamos trabajando?
SELECT DB_NAME() AS current_database;

-- 2. Con qué identidad estoy conectado?
-- Esta consulta diferencia la identidad con la que nos autenticamos del usuario que representa esa conexión dentro de la base.
SELECT SUSER_NAME() AS [login name], USER_NAME() AS [database user];    

-- 3. Ver usuarios existentes en la base de datos
SELECT name, type_desc
FROM sys.database_principals
WHERE type NOT IN ('A', 'R') -- Excluir roles y aplicaciones
ORDER BY name;

-- 4. Ver roles existentes en la base de datos
SELECT name, type_desc 
FROM sys.database_principals 
WHERE type = 'R'
ORDER BY name;

-- 5. Ver qué usuarios pertenecen a qué roles
SELECT 
    role_principal.name AS role_name,
    member_principal.name AS member_name 
FROM sys.database_role_members drm 
JOIN sys.database_principals role_principal 
    ON drm.role_principal_id = role_principal.principal_id 
JOIN sys.database_principals member_principal
    ON drm.member_principal_id = member_principal.principal_id 
ORDER BY role_name, member_name;