-- ============================================
-- 1. CREAR STAGING MATERIAL
-- ============================================

CREATE TABLE staging.material (
    plant_id INT,
    material_code VARCHAR(30),
    material_name VARCHAR(100),
    product_family VARCHAR(30),
    unit_price DECIMAL(12,2),
    safety_stock DECIMAL(14,3)
);
GO


-- ============================================
-- 2. CARGAR CSV DESDE BLOB
-- ============================================

BULK INSERT staging.material
FROM 'master/materials.csv'
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
FROM staging.material;
GO


-- ============================================
-- 4. INSERTAR EN TABLA FINAL
-- ============================================

INSERT INTO master.material (
    plant_id,
    material_code,
    material_name,
    product_family,
    unit_price,
    safety_stock
)
SELECT
    plant_id,
    material_code,
    material_name,
    product_family,
    unit_price,
    safety_stock
FROM staging.material;
GO


-- ============================================
-- 5. COMPROBAR TABLA FINAL
-- ============================================

SELECT *
FROM master.material;
GO


-- ============================================
-- 6. LIMPIAR STAGING
-- ============================================

TRUNCATE TABLE staging.material;
GO