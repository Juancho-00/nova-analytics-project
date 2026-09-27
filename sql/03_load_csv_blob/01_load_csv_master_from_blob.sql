
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


-- ============================================
-- 5. STAGING TABLE
-- Misma estructura que plants.csv
-- ============================================

CREATE TABLE staging.plant (
    plant_code VARCHAR(10),
    plant_name VARCHAR(100),
    city VARCHAR(100)
);
GO


-- ============================================
-- 6. CARGAR CSV DESDE BLOB
-- ============================================

BULK INSERT staging.plant
FROM 'master/plants.csv'
WITH (
    DATA_SOURCE = 'AzureBlobStorage',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a', 
    CODEPAGE = '65001'
);
GO

-- ============================================
-- 7. COMPROBAR STAGING
-- ============================================

SELECT *
FROM staging.plant;
GO


-- ============================================
-- 8. INSERTAR EN TABLA FINAL
-- ============================================

INSERT INTO master.plant (
    plant_code,
    plant_name,
    city
)
SELECT
    plant_code,
    plant_name,
    city
FROM staging.plant;
GO


-- ============================================
-- 9. COMPROBAR TABLA FINAL
-- ============================================

SELECT *
FROM master.plant;
GO


-- ============================================
-- 10. LIMPIAR STAGING
-- ============================================

TRUNCATE TABLE staging.plant;
GO