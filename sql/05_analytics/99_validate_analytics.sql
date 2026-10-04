-- =====================================================================
-- 05_analytics / 99_validate_analytics.sql
-- Reconciliación: la capa analítica debe cuadrar EXACTAMENTE con las
-- tablas operacionales. La columna "diferencia" debe ser 0 en todas.
-- =====================================================================

WITH controles AS (
SELECT 'Unidades pedidas' AS control,
       (SELECT SUM(ordered_qty) FROM analytics.fact_sales)              AS analytics,
       (SELECT SUM(ordered_quantity) FROM sales.sales_order_line)       AS operacional
UNION ALL
SELECT 'Unidades despachadas',
       (SELECT SUM(shipped_qty) FROM analytics.fact_shipment),
       (SELECT -SUM(quantity) FROM inventory.inventory_movement WHERE movement_type = 'CUSTOMER_SHIPMENT')
UNION ALL
SELECT 'Entregado (ventas) vs despachado',
       (SELECT SUM(delivered_qty) FROM analytics.fact_sales),
       (SELECT SUM(shipped_qty) FROM analytics.fact_shipment)
UNION ALL
SELECT 'Unidades producidas',
       (SELECT SUM(produced_qty) FROM analytics.fact_production_event),
       (SELECT SUM(produced_quantity) FROM production.production_event)
UNION ALL
SELECT 'Buenas (órdenes) vs buenas (eventos)',
       (SELECT SUM(good_qty) FROM analytics.fact_production_order),
       (SELECT SUM(good_qty) FROM analytics.fact_production_event)
UNION ALL
SELECT 'Stock final (último día)',
       (SELECT SUM(closing_stock) FROM analytics.fact_inventory_daily
         WHERE [date] = (SELECT MAX([date]) FROM analytics.fact_inventory_daily)),
       (SELECT SUM(quantity) FROM inventory.inventory_movement)
UNION ALL
SELECT 'Filas inventario diario = días x materiales',
       (SELECT COUNT(*) FROM analytics.fact_inventory_daily),
       (SELECT COUNT(DISTINCT [date]) FROM analytics.fact_inventory_daily) * (SELECT COUNT(*) FROM master.material)
)
SELECT control, analytics, operacional, analytics - operacional AS diferencia
FROM controles;

-- Integridad referencial de los hechos contra las dimensiones (0 filas)
SELECT 'fact_sales sin material' AS problema, COUNT(*) AS filas
FROM analytics.fact_sales f LEFT JOIN analytics.dim_material d ON d.material_id = f.material_id
WHERE d.material_id IS NULL
UNION ALL
SELECT 'fact_sales sin cliente', COUNT(*)
FROM analytics.fact_sales f LEFT JOIN analytics.dim_customer d ON d.customer_id = f.customer_id
WHERE d.customer_id IS NULL
UNION ALL
SELECT 'fact_sales con fecha fuera de dim_date', COUNT(*)
FROM analytics.fact_sales f LEFT JOIN analytics.dim_date d ON d.[date] = f.order_date
WHERE d.[date] IS NULL
UNION ALL
SELECT 'fact_production_event sin línea', COUNT(*)
FROM analytics.fact_production_event f
LEFT JOIN analytics.dim_production_line d ON d.production_line_id = f.production_line_id
WHERE d.production_line_id IS NULL;

-- Vista previa de KPIs principales
SELECT
    (SELECT SUM(order_value)   FROM analytics.fact_sales)                       AS ventas_valor,
    (SELECT SUM(pending_value) FROM analytics.fact_sales)                       AS backlog_valor,
    (SELECT CAST(AVG(CAST(is_on_time AS FLOAT)) AS DECIMAL(5,4)) FROM analytics.fact_shipment) AS despachos_a_tiempo,
    (SELECT CAST(SUM(rejected_qty) / NULLIF(SUM(produced_qty), 0) AS DECIMAL(5,4))
       FROM analytics.fact_production_event)                                    AS tasa_rechazo,
    (SELECT COUNT(*) FROM analytics.fact_inventory_daily
      WHERE [date] = (SELECT MAX([date]) FROM analytics.fact_inventory_daily)
        AND is_below_safety_stock = 1)                                          AS materiales_bajo_safety;
