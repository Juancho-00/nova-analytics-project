-- ============================================
-- 1. STAGING TABLE
-- Misma estructura que plants.csv
-- ============================================

CREATE TABLE staging.plant (
    plant_code VARCHAR(10),
    plant_name VARCHAR(100),
    city VARCHAR(100)
);
GO


-- ============================================
-- 2. CARGAR CSV DESDE BLOB
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
-- 3. COMPROBAR STAGING
-- ============================================

SELECT *
FROM staging.plant;
GO


-- ============================================
-- 4. INSERTAR EN TABLA FINAL
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
-- 5. COMPROBAR TABLA FINAL
-- ============================================

SELECT *
FROM master.plant;
GO


-- ============================================
-- 6. LIMPIAR STAGING
-- ============================================

TRUNCATE TABLE staging.plant;
GO