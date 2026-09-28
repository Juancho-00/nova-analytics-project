-- ============================================
-- 1. MASTER KEY
-- Solo se crea una vez
-- ============================================
CREATE MASTER KEY 
ENCRYPTION BY PASSWORD = '***REMOVED***';

-- ============================================
-- 2. CREDENTIAL
-- SAS token SIN el ?
-- ============================================
CREATE DATABASE SCOPED CREDENTIAL AzureBlobStorageCredential
WITH 
    IDENTITY = 'SHARED ACCESS SIGNATURE',
    SECRET = '***REMOVED***'
;

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