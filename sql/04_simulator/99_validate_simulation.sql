-- =====================================================================
-- 04_simulator / 99_validate_simulation.sql
-- Pruebas de calidad de datos después de correr el simulador.
-- Cada consulta marcada "debe devolver 0 filas" es una prueba:
-- si devuelve algo, hay una incoherencia.
-- =====================================================================

-- 0. Resumen de ejecuciones del simulador
SELECT * FROM simulator.run_log ORDER BY run_id;

-- 1. Volumen por tabla
SELECT 'sales_order' AS tabla, COUNT(*) AS filas FROM sales.sales_order
UNION ALL SELECT 'sales_order_line',   COUNT(*) FROM sales.sales_order_line
UNION ALL SELECT 'production_order',   COUNT(*) FROM production.production_order
UNION ALL SELECT 'production_event',   COUNT(*) FROM production.production_event
UNION ALL SELECT 'inventory_movement', COUNT(*) FROM inventory.inventory_movement;

-- 2. El stock nunca puede ser negativo en ningún momento (debe devolver 0 filas)
WITH running AS (
    SELECT material_id, movement_timestamp,
           SUM(quantity) OVER (PARTITION BY material_id
                               ORDER BY movement_timestamp, inventory_movement_id
                               ROWS UNBOUNDED PRECEDING) AS stock_after
    FROM inventory.inventory_movement
)
SELECT * FROM running WHERE stock_after < 0;

-- 3. Entradas de producción = cantidad buena de los eventos, por orden (0 filas)
WITH good AS (
    SELECT production_order_id, SUM(produced_quantity - rejected_quantity) AS good_qty
    FROM production.production_event
    GROUP BY production_order_id
), receipts AS (
    SELECT CAST(REPLACE(reference_order, 'PO-', '') AS BIGINT) AS production_order_id,
           SUM(quantity) AS receipt_qty
    FROM inventory.inventory_movement
    WHERE movement_type = 'PRODUCTION_RECEIPT'
    GROUP BY reference_order
)
SELECT g.production_order_id, g.good_qty, r.receipt_qty
FROM good g
FULL JOIN receipts r ON r.production_order_id = g.production_order_id
WHERE ISNULL(g.good_qty, 0) <> ISNULL(r.receipt_qty, 0);

-- 4. Salidas de inventario = cantidad entregada, por pedido y material (0 filas)
WITH delivered AS (
    SELECT o.order_number, l.material_id, SUM(l.delivered_quantity) AS delivered_qty
    FROM sales.sales_order o
    JOIN sales.sales_order_line l ON l.sales_order_id = o.sales_order_id
    GROUP BY o.order_number, l.material_id
), shipped AS (
    SELECT reference_order AS order_number, material_id, -SUM(quantity) AS shipped_qty
    FROM inventory.inventory_movement
    WHERE movement_type = 'CUSTOMER_SHIPMENT'
    GROUP BY reference_order, material_id
)
SELECT d.order_number, d.material_id, d.delivered_qty, s.shipped_qty
FROM delivered d
FULL JOIN shipped s ON s.order_number = d.order_number AND s.material_id = d.material_id
WHERE ISNULL(d.delivered_qty, 0) <> ISNULL(s.shipped_qty, 0);

-- 5. La familia y planta de la línea coinciden con las del material (0 filas)
SELECT po.production_order_id, m.material_code, m.plant_id AS material_plant,
       pl.plant_id AS line_plant, m.product_family, pl.product_family AS line_family
FROM production.production_order po
JOIN master.material m         ON m.material_id = po.material_id
JOIN master.production_line pl ON pl.production_line_id = po.production_line_id
WHERE m.product_family <> pl.product_family OR m.plant_id <> pl.plant_id;

-- 6. Estado de la orden de producción coherente con lo producido (0 filas)
WITH progress AS (
    SELECT po.production_order_id, po.order_status, po.planned_quantity,
           ISNULL(SUM(e.produced_quantity - e.rejected_quantity), 0) AS good_qty,
           COUNT(e.production_event_id) AS n_events
    FROM production.production_order po
    LEFT JOIN production.production_event e ON e.production_order_id = po.production_order_id
    GROUP BY po.production_order_id, po.order_status, po.planned_quantity
)
SELECT * FROM progress
WHERE (order_status = 'COMPLETED'   AND good_qty <  planned_quantity)
   OR (order_status = 'IN_PROGRESS' AND (good_qty >= planned_quantity OR n_events = 0))
   OR (order_status = 'PLANNED'     AND n_events > 0);

-- 7. Estado del pedido de venta coherente con lo entregado (0 filas)
WITH progress AS (
    SELECT o.sales_order_id, o.order_number, o.order_status,
           SUM(l.ordered_quantity) AS ordered_qty, SUM(l.delivered_quantity) AS delivered_qty
    FROM sales.sales_order o
    JOIN sales.sales_order_line l ON l.sales_order_id = o.sales_order_id
    GROUP BY o.sales_order_id, o.order_number, o.order_status
)
SELECT * FROM progress
WHERE (order_status = 'COMPLETED'           AND delivered_qty <  ordered_qty)
   OR (order_status = 'CREATED'             AND delivered_qty <> 0)
   OR (order_status = 'PARTIALLY_DELIVERED' AND (delivered_qty = 0 OR delivered_qty >= ordered_qty));

-- 8. Stock actual frente a safety stock
SELECT p.plant_code, m.material_code, m.product_family, m.safety_stock,
       SUM(im.quantity) AS current_stock,
       SUM(im.quantity) - m.safety_stock AS stock_gap
FROM master.material m
JOIN master.plant p ON p.plant_id = m.plant_id
LEFT JOIN inventory.inventory_movement im ON im.material_id = m.material_id
GROUP BY p.plant_code, m.material_code, m.product_family, m.safety_stock
ORDER BY p.plant_code, m.material_code;
