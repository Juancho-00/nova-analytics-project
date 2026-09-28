-- ============================================
-- 1. CREAR STAGING SALES ORDER LINE
-- ============================================

CREATE TABLE staging.sales_order_line (
    sales_order_id BIGINT,
    material_id INT,
    ordered_quantity DECIMAL(14,3),
    delivered_quantity DECIMAL(14,3),
    unit_price DECIMAL(12,2)
);
GO


-- ============================================
-- 2. CARGAR CSV DESDE BLOB
-- ============================================

BULK INSERT staging.sales_order_line
FROM 'historical/historical_sales_order_lines.csv'
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
FROM staging.sales_order_line;
GO


-- ============================================
-- 4. INSERTAR EN TABLA FINAL
-- ============================================

INSERT INTO sales.sales_order_line (
    sales_order_id,
    material_id,
    ordered_quantity,
    delivered_quantity,
    unit_price
)
SELECT
    sales_order_id,
    material_id,
    ordered_quantity,
    delivered_quantity,
    unit_price
FROM staging.sales_order_line;
GO


-- ============================================
-- 5. COMPROBAR TABLA FINAL
-- ============================================

SELECT *
FROM sales.sales_order_line;
GO


-- ============================================
-- 6. LIMPIAR STAGING
-- ============================================

TRUNCATE TABLE staging.sales_order_line;
GO