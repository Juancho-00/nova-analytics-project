-- ============================================
-- 1. CREAR STAGING SALES ORDER
-- ============================================

CREATE TABLE staging.sales_order (
    order_number VARCHAR(30),
    customer_id INT,
    plant_id INT,
    order_date DATE,
    requested_delivery_date DATE,
    order_status VARCHAR(30)
);
GO


-- ============================================
-- 2. CARGAR CSV DESDE BLOB
-- ============================================

BULK INSERT staging.sales_order
FROM 'historical/historical_sales_orders.csv'
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
FROM staging.sales_order;
GO


-- ============================================
-- 4. INSERTAR EN TABLA FINAL
-- ============================================

INSERT INTO sales.sales_order (
    order_number,
    customer_id,
    plant_id,
    order_date,
    requested_delivery_date,
    order_status
)
SELECT
    order_number,
    customer_id,
    plant_id,
    order_date,
    requested_delivery_date,
    order_status
FROM staging.sales_order;
GO


-- ============================================
-- 5. COMPROBAR TABLA FINAL
-- ============================================

SELECT *
FROM sales.sales_order;
GO


-- ============================================
-- 6. LIMPIAR STAGING
-- ============================================

TRUNCATE TABLE staging.sales_order;
GO