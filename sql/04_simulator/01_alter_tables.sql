-- =====================================================================
-- 04_simulator / 01_alter_tables.sql
-- Ajustes de esquema que necesita el simulador ERP.
-- Script idempotente: se puede ejecutar varias veces sin error.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. production_order: fechas para análisis temporal y cumplimiento
--    created_at : cuándo se planificó la orden
--    due_date   : fecha comprometida de terminación
-- ---------------------------------------------------------------------
IF COL_LENGTH('production.production_order', 'created_at') IS NULL
    ALTER TABLE production.production_order ADD created_at DATETIME2 NULL;
GO

IF COL_LENGTH('production.production_order', 'due_date') IS NULL
    ALTER TABLE production.production_order ADD due_date DATE NULL;
GO

-- ---------------------------------------------------------------------
-- 2. inventory_movement: trazabilidad del movimiento
--    PO-<id> para entradas de producción, número de pedido para entregas
-- ---------------------------------------------------------------------
IF COL_LENGTH('inventory.inventory_movement', 'reference_order') IS NULL
    ALTER TABLE inventory.inventory_movement ADD reference_order VARCHAR(30) NULL;
GO

-- ---------------------------------------------------------------------
-- 3. Esquema y tabla de control del simulador (watermark / auditoría)
--    Cada ejecución registra el rango de fechas simulado. La siguiente
--    ejecución continúa desde MAX(end_date) + 1, evitando duplicados.
-- ---------------------------------------------------------------------
IF SCHEMA_ID('simulator') IS NULL
    EXEC('CREATE SCHEMA simulator');
GO

IF OBJECT_ID('simulator.run_log', 'U') IS NULL
CREATE TABLE simulator.run_log (
    run_id              INT IDENTITY(1,1) PRIMARY KEY,
    executed_at         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    start_date          DATE NOT NULL,
    end_date            DATE NOT NULL,
    seed                INT NOT NULL,
    sales_orders        INT NOT NULL,
    sales_order_lines   INT NOT NULL,
    production_orders   INT NOT NULL,
    production_events   INT NOT NULL,
    inventory_movements INT NOT NULL
);
GO

-- Comprobación
SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE (TABLE_SCHEMA = 'production' AND TABLE_NAME = 'production_order')
   OR (TABLE_SCHEMA = 'inventory'  AND TABLE_NAME = 'inventory_movement')
   OR (TABLE_SCHEMA = 'simulator')
ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION;
GO
