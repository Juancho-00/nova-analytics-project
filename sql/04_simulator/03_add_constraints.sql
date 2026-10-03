-- =====================================================================
-- 04_simulator / 03_add_constraints.sql
-- Reglas de negocio del diccionario de datos llevadas a la base como
-- CHECK constraints: si Python (o cualquiera) intenta insertar un dato
-- incoherente, la base lo rechaza. Ejecutar DESPUÉS del reset.
-- Idempotente.
-- =====================================================================

-- Estados de pedido de venta
IF OBJECT_ID('sales.CK_sales_order_status', 'C') IS NULL
ALTER TABLE sales.sales_order ADD CONSTRAINT CK_sales_order_status
    CHECK (order_status IN ('CREATED', 'IN_PROGRESS', 'PARTIALLY_DELIVERED', 'COMPLETED', 'CANCELLED'));
GO

-- Entregado entre 0 y lo pedido
IF OBJECT_ID('sales.CK_sales_order_line_qty', 'C') IS NULL
ALTER TABLE sales.sales_order_line ADD CONSTRAINT CK_sales_order_line_qty
    CHECK (ordered_quantity > 0 AND delivered_quantity >= 0 AND delivered_quantity <= ordered_quantity);
GO

-- Estados de orden de producción
IF OBJECT_ID('production.CK_production_order_status', 'C') IS NULL
ALTER TABLE production.production_order ADD CONSTRAINT CK_production_order_status
    CHECK (order_status IN ('PLANNED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'));
GO

IF OBJECT_ID('production.CK_production_order_qty', 'C') IS NULL
ALTER TABLE production.production_order ADD CONSTRAINT CK_production_order_qty
    CHECK (planned_quantity > 0);
GO

-- Rechazo nunca mayor que lo producido
IF OBJECT_ID('production.CK_production_event_qty', 'C') IS NULL
ALTER TABLE production.production_event ADD CONSTRAINT CK_production_event_qty
    CHECK (produced_quantity >= 0 AND rejected_quantity >= 0 AND rejected_quantity <= produced_quantity);
GO

-- Tipo de movimiento y signo coherentes
IF OBJECT_ID('inventory.CK_inventory_movement_type_sign', 'C') IS NULL
ALTER TABLE inventory.inventory_movement ADD CONSTRAINT CK_inventory_movement_type_sign
    CHECK (
        (movement_type IN ('INITIAL_STOCK', 'PRODUCTION_RECEIPT') AND quantity > 0)
     OR (movement_type = 'CUSTOMER_SHIPMENT' AND quantity < 0)
    );
GO

-- Comprobación
SELECT OBJECT_SCHEMA_NAME(parent_object_id) AS esquema,
       OBJECT_NAME(parent_object_id)        AS tabla,
       name                                 AS constraint_name
FROM sys.check_constraints
ORDER BY esquema, tabla;
GO
