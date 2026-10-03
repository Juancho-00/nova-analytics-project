-- ============================================
-- CONEXIÓN AZURE SQL -> BLOB STORAGE
-- IMPORTANTE: los valores entre <...> son marcadores.
-- Reemplázalos SOLO al ejecutar en Azure; nunca guardes
-- el SAS token ni la contraseña reales en este archivo.
-- ============================================

-- ============================================
-- 1. MASTER KEY
-- Solo se crea una vez
-- ============================================
CREATE MASTER KEY
ENCRYPTION BY PASSWORD = '<MASTER_KEY_PASSWORD>';

-- ============================================
-- 2. CREDENTIAL
-- SAS token SIN el ? inicial
-- Recomendado: permisos solo de lectura/listado (sp=rl)
-- y una fecha de expiración corta (se=...)
-- ============================================
CREATE DATABASE SCOPED CREDENTIAL AzureBlobStorageCredential
WITH
    IDENTITY = 'SHARED ACCESS SIGNATURE',
    SECRET = '<SAS_TOKEN_SIN_SIGNO_DE_INTERROGACION>';

-- Si el SAS vence, no recrees la credencial: actualízala
-- ALTER DATABASE SCOPED CREDENTIAL AzureBlobStorageCredential
-- WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
--      SECRET = '<NUEVO_SAS_TOKEN>';

-- ============================================
-- 3. EXTERNAL DATA SOURCE
-- Conexión con nuestro container
-- ============================================
CREATE EXTERNAL DATA SOURCE AzureBlobStorage
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://novastoragejuancho.blob.core.windows.net/nova-data',
    CREDENTIAL = AzureBlobStorageCredential
);

-- ============================================
-- 4. STAGING SCHEMA
-- Solo se crea una vez
-- ============================================
CREATE SCHEMA staging;
GO
