-- ============================================
-- 1. CREAR STAGING CUSTOMER
-- ============================================

CREATE TABLE staging.customer (
    customer_code VARCHAR(20),
    customer_name VARCHAR(100)
);
GO


-- ============================================
-- 2. CARGAR CSV DESDE BLOB
-- ============================================

BULK INSERT staging.customer
FROM 'master/customers.csv'
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
FROM staging.customer;
GO


-- ============================================
-- 4. PASAR A TABLA FINAL
-- ============================================

INSERT INTO master.customer (
    customer_code,
    customer_name
)
SELECT
    customer_code,
    customer_name
FROM staging.customer;
GO


-- ============================================
-- 5. COMPROBAR TABLA FINAL
-- ============================================

SELECT *
FROM master.customer;
GO


-- ============================================
-- 6. LIMPIAR STAGING
-- ============================================

TRUNCATE TABLE staging.customer;
GO