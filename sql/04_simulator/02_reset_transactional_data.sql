-- =====================================================================
-- 04_simulator / 02_reset_transactional_data.sql
--
-- Deja la base en un punto de partida coherente para el simulador:
--   * Se CONSERVAN los maestros (plant, customer, material, production_line).
--   * Se CONSERVA el stock inicial (INITIAL_STOCK del 2026-01-01).
--   * Se CONSERVAN los 20 pedidos históricos cargados desde Blob
--     (SO-2026-0001 ... SO-2026-0020), pero se reinicia su cumplimiento
--     (delivered_quantity = 0, estado CREATED). El simulador los entregará
--     en su fecha, generando los movimientos de inventario que faltaban.
--   * Se ELIMINA todo lo generado por los scripts de prueba anteriores
--     (SO-PY-001, órdenes y eventos de producción, movimientos sueltos).
--
-- ¿Por qué? En el histórico del CSV hay ~10.000 unidades entregadas sin
-- ninguna salida de inventario ni producción que las respalde, así que el
-- stock "actual" no cuadraba con nada.
--
-- ⚠ Destructivo: ejecútalo solo cuando quieras reiniciar la simulación.
-- =====================================================================

SET XACT_ABORT ON;
BEGIN TRANSACTION;

    -- 1. Producción (todo fue generado por Python)
    DELETE FROM production.production_event;
    DELETE FROM production.production_order;

    -- 2. Inventario: solo queda el stock inicial
    DELETE FROM inventory.inventory_movement
    WHERE movement_type <> 'INITIAL_STOCK';

    -- 3. Ventas: eliminar pedidos que no son el histórico del CSV
    DELETE l
    FROM sales.sales_order_line AS l
    JOIN sales.sales_order AS o
        ON o.sales_order_id = l.sales_order_id
    WHERE o.order_number NOT LIKE 'SO-2026-[0-9][0-9][0-9][0-9]';

    DELETE FROM sales.sales_order
    WHERE order_number NOT LIKE 'SO-2026-[0-9][0-9][0-9][0-9]';

    -- 4. Reiniciar el cumplimiento del histórico
    UPDATE sales.sales_order_line SET delivered_quantity = 0;
    UPDATE sales.sales_order      SET order_status = 'CREATED';

    -- 5. Reiniciar el control del simulador
    IF OBJECT_ID('simulator.run_log', 'U') IS NOT NULL
        DELETE FROM simulator.run_log;

COMMIT TRANSACTION;
GO

-- Comprobación: deben quedar 20 pedidos, 39 líneas, 12 movimientos, 0 producción
SELECT 'sales_order'        AS tabla, COUNT(*) AS filas FROM sales.sales_order
UNION ALL SELECT 'sales_order_line',   COUNT(*) FROM sales.sales_order_line
UNION ALL SELECT 'inventory_movement', COUNT(*) FROM inventory.inventory_movement
UNION ALL SELECT 'production_order',   COUNT(*) FROM production.production_order
UNION ALL SELECT 'production_event',   COUNT(*) FROM production.production_event;
GO
