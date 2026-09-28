-- ============================================
-- 1. CREAR STAGING PRODUCTION LINE
-- ============================================

CREATE TABLE staging.production_line (
    plant_id INT,
    line_code VARCHAR(20),
    line_name VARCHAR(100),
    product_family VARCHAR(30),
    daily_capacity DECIMAL(14,3)
);
GO


-- ============================================
-- 2. CARGAR CSV DESDE BLOB
-- ============================================

BULK INSERT staging.production_line
FROM 'master/production_lines.csv'
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
FROM staging.production_line;
GO


-- ============================================
-- 4. INSERTAR EN TABLA FINAL
-- ============================================

INSERT INTO master.production_line (
    plant_id,
    line_code,
    line_name,
    product_family,
    daily_capacity
)
SELECT
    plant_id,
    line_code,
    line_name,
    product_family,
    daily_capacity
FROM staging.production_line;
GO


-- ============================================
-- 5. COMPROBAR TABLA FINAL
-- ============================================

SELECT *
FROM master.production_line;
GO


-- ============================================
-- 6. LIMPIAR STAGING
-- ============================================

TRUNCATE TABLE staging.production_line;
GO