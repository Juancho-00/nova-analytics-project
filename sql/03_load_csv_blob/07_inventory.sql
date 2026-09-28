-- ============================================
-- 1. CREAR TABLA STAGING
-- ============================================

CREATE TABLE staging.inventory_movement (
    material_id INT,
    plant_id INT,
    movement_timestamp DATETIME2,
    movement_type VARCHAR(30),
    quantity DECIMAL(14,3)
);
GO


-- ============================================
-- 2. CARGAR CSV DESDE AZURE BLOB STORAGE
-- Ruta:
-- novo-data/initial/initial_inventory.csv
-- ============================================

BULK INSERT staging.inventory_movement
FROM 'initial/initial_inventory.csv'
WITH (
    DATA_SOURCE = 'AzureBlobStorage',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001'
);
GO


-- ============================================
-- 3. COMPROBAR QUE EL CSV SE HA CARGADO
-- ============================================

SELECT *
FROM staging.inventory_movement;
GO


-- ============================================
-- 4. INSERTAR EN LA TABLA FINAL
-- ============================================

INSERT INTO inventory.inventory_movement (
    material_id,
    plant_id,
    movement_timestamp,
    movement_type,
    quantity
)
SELECT
    material_id,
    plant_id,
    movement_timestamp,
    movement_type,
    quantity
FROM staging.inventory_movement;
GO


-- ============================================
-- 5. COMPROBAR TABLA FINAL
-- ============================================

SELECT *
FROM inventory.inventory_movement;
GO


-- ============================================
-- 6. COMPROBAR NÚMERO DE REGISTROS
-- ============================================

SELECT COUNT(*) AS inventory_movements
FROM inventory.inventory_movement;
GO


-- ============================================
-- 7. COMPROBAR STOCK ACTUAL POR MATERIAL
-- ============================================

SELECT
    plant_id,
    material_id,
    SUM(quantity) AS current_stock
FROM inventory.inventory_movement
GROUP BY
    plant_id,
    material_id
ORDER BY
    plant_id,
    material_id;
GO


-- ============================================
-- 8. LIMPIAR STAGING
-- La tabla permanece, solo eliminamos sus datos
-- ============================================

TRUNCATE TABLE staging.inventory_movement;
GO