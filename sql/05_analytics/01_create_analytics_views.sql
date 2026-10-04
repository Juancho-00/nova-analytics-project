-- =====================================================================
-- 05_analytics / 01_create_analytics_views.sql
--
-- Capa analítica en MODELO ESTRELLA para Power BI.
-- Power BI se conecta SOLO a este esquema, nunca a las tablas operacionales.
--
--   Dimensiones                      Hechos (grano)
--   ------------------------------   -----------------------------------------
--   analytics.dim_date               analytics.fact_sales            (línea de pedido)
--   analytics.dim_customer           analytics.fact_shipment         (despacho)
--   analytics.dim_material (+planta) analytics.fact_production_order (orden de producción)
--   analytics.dim_production_line    analytics.fact_production_event (evento por turno)
--                                    analytics.fact_inventory_daily  (material x día)
--
-- La planta va dentro de dim_material y dim_production_line (desnormalizada):
-- así todas las tablas de hechos filtran por planta a través del material,
-- sin relaciones ambiguas en Power BI.
--
-- Script idempotente (CREATE OR ALTER).
-- =====================================================================

IF SCHEMA_ID('analytics') IS NULL
    EXEC('CREATE SCHEMA analytics');
GO

-- =====================================================================
-- DIMENSIONES
-- =====================================================================

-- ---------------------------------------------------------------------
-- dim_date: calendario 2025-2027 generado sin tabla física.
-- is_working_day usa los mismos festivos que el simulador.
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW analytics.dim_date AS
WITH digits AS (
    SELECT d FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS v(d)
), numbers AS (
    -- 0..9999 sin depender de tablas del sistema (funciona con cualquier usuario)
    SELECT a.d + 10 * b.d + 100 * c.d + 1000 * e.d AS n
    FROM digits a CROSS JOIN digits b CROSS JOIN digits c CROSS JOIN digits e
), dates AS (
    SELECT CAST(DATEADD(DAY, n, '2025-01-01') AS DATE) AS [date]
    FROM numbers
    WHERE n <= DATEDIFF(DAY, '2025-01-01', '2027-12-31')
), parts AS (
    SELECT [date],
           YEAR([date])  AS [year],
           MONTH([date]) AS month_number,
           DAY([date])   AS day_of_month,
           DATEDIFF(DAY, '1900-01-01', [date]) % 7 + 1 AS day_of_week   -- 1 = lunes ... 7 = domingo
    FROM dates
)
SELECT
    CAST(CONVERT(CHAR(8), [date], 112) AS INT)                        AS date_key,
    [date],
    [year],
    DATEPART(QUARTER, [date])                                         AS quarter_number,
    CONCAT('T', DATEPART(QUARTER, [date]))                            AS quarter_name,
    month_number,
    CHOOSE(month_number, 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
           'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre') AS month_name,
    CHOOSE(month_number, 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul',
           'Ago', 'Sep', 'Oct', 'Nov', 'Dic')                         AS month_short,
    [year] * 100 + month_number                                       AS year_month_key,
    CONCAT([year], '-', RIGHT(CONCAT('0', month_number), 2))          AS year_month,
    DATEPART(ISO_WEEK, [date])                                        AS iso_week,
    DATEFROMPARTS([year], month_number, 1)                            AS month_start,
    day_of_month,
    day_of_week,
    CHOOSE(day_of_week, 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo') AS day_name,
    CASE WHEN day_of_week <= 5
          AND NOT (   (month_number = 1  AND day_of_month IN (1, 6))
                   OR (month_number = 5  AND day_of_month = 1)
                   OR (month_number = 8  AND day_of_month = 15)
                   OR (month_number = 10 AND day_of_month = 12)
                   OR (month_number = 11 AND day_of_month = 1)
                   OR (month_number = 12 AND day_of_month IN (6, 8, 25)))
         THEN 1 ELSE 0 END                                            AS is_working_day
FROM parts;
GO

-- ---------------------------------------------------------------------
-- dim_customer: con segmento derivado del nombre
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW analytics.dim_customer AS
SELECT
    c.customer_id,
    c.customer_code,
    c.customer_name,
    CASE
        WHEN c.customer_name LIKE '%Automotive%'   THEN 'Automotive'
        WHEN c.customer_name LIKE '%Industrial%'   THEN 'Industrial'
        WHEN c.customer_name LIKE '%Distribution%' THEN 'Distribution'
        WHEN c.customer_name LIKE '%Aftermarket%'  THEN 'Aftermarket'
        ELSE 'Otros'
    END AS customer_segment
FROM master.customer AS c;
GO

-- ---------------------------------------------------------------------
-- dim_material: grano material x planta, con atributos de la planta
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW analytics.dim_material AS
SELECT
    m.material_id,
    m.material_code,
    m.material_name,
    CONCAT(m.material_code, ' - ', p.plant_code)  AS material_plant_label,
    m.product_family,
    m.unit_price,
    m.safety_stock,
    p.plant_id,
    p.plant_code,
    p.plant_name,
    p.city AS plant_city
FROM master.material AS m
JOIN master.plant    AS p ON p.plant_id = m.plant_id;
GO

-- ---------------------------------------------------------------------
-- dim_production_line
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW analytics.dim_production_line AS
SELECT
    pl.production_line_id,
    pl.line_code,
    pl.line_name,
    CONCAT(pl.line_name, ' - ', p.plant_code) AS line_plant_label,
    pl.product_family,
    pl.daily_capacity,
    p.plant_id,
    p.plant_code,
    p.plant_name
FROM master.production_line AS pl
JOIN master.plant           AS p ON p.plant_id = pl.plant_id;
GO

-- =====================================================================
-- HECHOS
-- =====================================================================

-- ---------------------------------------------------------------------
-- fact_sales: una fila por línea de pedido (cartera y cumplimiento)
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW analytics.fact_sales AS
WITH shipments AS (
    SELECT reference_order,
           material_id,
           MIN(CAST(movement_timestamp AS DATE)) AS first_shipment_date,
           MAX(CAST(movement_timestamp AS DATE)) AS last_shipment_date,
           COUNT(*)                              AS shipment_count
    FROM inventory.inventory_movement
    WHERE movement_type = 'CUSTOMER_SHIPMENT'
    GROUP BY reference_order, material_id
)
SELECT
    l.sales_order_line_id,
    o.sales_order_id,
    o.order_number,
    o.customer_id,
    l.material_id,
    o.order_date,
    o.requested_delivery_date,
    o.order_status,
    l.ordered_quantity                                       AS ordered_qty,
    l.delivered_quantity                                     AS delivered_qty,
    l.ordered_quantity - l.delivered_quantity                AS pending_qty,
    l.unit_price,
    l.ordered_quantity * l.unit_price                        AS order_value,
    l.delivered_quantity * l.unit_price                      AS delivered_value,
    (l.ordered_quantity - l.delivered_quantity) * l.unit_price AS pending_value,
    s.first_shipment_date,
    s.last_shipment_date,
    ISNULL(s.shipment_count, 0)                              AS shipment_count,
    DATEDIFF(DAY, o.order_date, o.requested_delivery_date)   AS requested_lead_days,
    CASE WHEN l.delivered_quantity >= l.ordered_quantity THEN 1 ELSE 0 END AS is_fully_delivered,
    -- Línea completa entregada a tiempo (OTIF a nivel de línea)
    CASE WHEN l.delivered_quantity >= l.ordered_quantity
          AND s.last_shipment_date <= o.requested_delivery_date THEN 1 ELSE 0 END AS is_otif,
    -- Pendiente con fecha solicitada ya vencida
    CASE WHEN l.delivered_quantity < l.ordered_quantity
          AND o.requested_delivery_date < CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END AS is_overdue
FROM sales.sales_order_line AS l
JOIN sales.sales_order      AS o ON o.sales_order_id = l.sales_order_id
LEFT JOIN shipments         AS s ON s.reference_order = o.order_number
                                AND s.material_id     = l.material_id;
GO

-- ---------------------------------------------------------------------
-- fact_shipment: una fila por despacho (puntualidad de entregas)
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW analytics.fact_shipment AS
SELECT
    im.inventory_movement_id                                  AS shipment_id,
    o.sales_order_id,
    o.order_number,
    o.customer_id,
    im.material_id,
    im.movement_timestamp                                     AS shipment_timestamp,
    CAST(im.movement_timestamp AS DATE)                       AS shipment_date,
    o.requested_delivery_date,
    -im.quantity                                              AS shipped_qty,
    -im.quantity * l.unit_price                               AS shipped_value,
    DATEDIFF(DAY, o.requested_delivery_date, CAST(im.movement_timestamp AS DATE)) AS days_vs_requested,
    CASE WHEN CAST(im.movement_timestamp AS DATE) <= o.requested_delivery_date THEN 1 ELSE 0 END AS is_on_time
FROM inventory.inventory_movement AS im
JOIN sales.sales_order            AS o ON o.order_number = im.reference_order
JOIN sales.sales_order_line       AS l ON l.sales_order_id = o.sales_order_id
                                      AND l.material_id    = im.material_id
WHERE im.movement_type = 'CUSTOMER_SHIPMENT';
GO

-- ---------------------------------------------------------------------
-- fact_production_event: una fila por evento (turno). Candidata a DirectQuery.
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW analytics.fact_production_event AS
SELECT
    e.production_event_id,
    e.production_order_id,
    po.material_id,
    po.production_line_id,
    e.event_timestamp,
    CAST(e.event_timestamp AS DATE)                    AS event_date,
    CASE WHEN DATEPART(HOUR, e.event_timestamp) < 14
         THEN 'Turno 1 (06-14)' ELSE 'Turno 2 (14-22)' END AS shift_name,
    e.produced_quantity                                AS produced_qty,
    e.rejected_quantity                                AS rejected_qty,
    e.produced_quantity - e.rejected_quantity          AS good_qty,
    CASE WHEN e.produced_quantity > 0
         THEN e.rejected_quantity / e.produced_quantity END AS reject_rate
FROM production.production_event AS e
JOIN production.production_order AS po ON po.production_order_id = e.production_order_id;
GO

-- ---------------------------------------------------------------------
-- fact_production_order: una fila por orden (cumplimiento del plan)
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW analytics.fact_production_order AS
WITH progress AS (
    SELECT production_order_id,
           SUM(produced_quantity)                     AS produced_qty,
           SUM(rejected_quantity)                     AS rejected_qty,
           SUM(produced_quantity - rejected_quantity) AS good_qty,
           MIN(CAST(event_timestamp AS DATE))         AS first_event_date,
           MAX(CAST(event_timestamp AS DATE))         AS last_event_date,
           COUNT(*)                                   AS event_count
    FROM production.production_event
    GROUP BY production_order_id
)
SELECT
    po.production_order_id,
    CONCAT('PO-', po.production_order_id)             AS production_order_number,
    po.material_id,
    po.production_line_id,
    po.order_status,
    CAST(po.created_at AS DATE)                       AS created_date,
    po.due_date,
    pr.first_event_date                               AS start_date,
    CASE WHEN po.order_status = 'COMPLETED' THEN pr.last_event_date END AS completion_date,
    po.planned_quantity                               AS planned_qty,
    ISNULL(pr.produced_qty, 0)                        AS produced_qty,
    ISNULL(pr.rejected_qty, 0)                        AS rejected_qty,
    ISNULL(pr.good_qty, 0)                            AS good_qty,
    ISNULL(pr.event_count, 0)                         AS event_count,
    CASE WHEN po.order_status = 'COMPLETED'
         THEN DATEDIFF(DAY, CAST(po.created_at AS DATE), pr.last_event_date) END AS lead_time_days,
    CASE WHEN po.order_status = 'COMPLETED' AND pr.last_event_date <= po.due_date THEN 1
         WHEN po.order_status = 'COMPLETED' THEN 0 END AS is_on_time
FROM production.production_order AS po
LEFT JOIN progress               AS pr ON pr.production_order_id = po.production_order_id;
GO

-- ---------------------------------------------------------------------
-- fact_inventory_daily: foto de stock al cierre de cada día, por material.
-- El stock es SEMI-ADITIVO: se suma entre materiales, pero NO entre días
-- (en DAX se toma el último día del periodo).
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW analytics.fact_inventory_daily AS
WITH daily AS (
    SELECT material_id,
           CAST(movement_timestamp AS DATE) AS [date],
           SUM(quantity)                                                              AS net_qty,
           SUM(CASE WHEN movement_type = 'PRODUCTION_RECEIPT' THEN quantity  ELSE 0 END) AS receipt_qty,
           SUM(CASE WHEN movement_type = 'CUSTOMER_SHIPMENT'  THEN -quantity ELSE 0 END) AS shipment_qty
    FROM inventory.inventory_movement
    GROUP BY material_id, CAST(movement_timestamp AS DATE)
), calendar AS (
    SELECT d.[date]
    FROM analytics.dim_date AS d
    WHERE d.[date] >= (SELECT MIN(CAST(movement_timestamp AS DATE)) FROM inventory.inventory_movement)
      AND d.[date] <= (SELECT MAX(CAST(movement_timestamp AS DATE)) FROM inventory.inventory_movement)
), grid AS (
    SELECT c.[date], m.material_id, m.safety_stock,
           ISNULL(dl.receipt_qty, 0)  AS receipt_qty,
           ISNULL(dl.shipment_qty, 0) AS shipment_qty,
           SUM(ISNULL(dl.net_qty, 0)) OVER (PARTITION BY m.material_id
                                            ORDER BY c.[date]
                                            ROWS UNBOUNDED PRECEDING) AS closing_stock
    FROM calendar        AS c
    CROSS JOIN master.material AS m
    LEFT JOIN daily      AS dl ON dl.material_id = m.material_id AND dl.[date] = c.[date]
)
SELECT
    [date],
    material_id,
    receipt_qty,
    shipment_qty,
    closing_stock,
    safety_stock,
    closing_stock - safety_stock                         AS stock_gap,
    CASE WHEN closing_stock < safety_stock THEN 1 ELSE 0 END AS is_below_safety_stock
FROM grid;
GO

-- Comprobación: vistas creadas y número de filas
SELECT 'dim_date' AS vista, COUNT(*) AS filas FROM analytics.dim_date
UNION ALL SELECT 'dim_customer',          COUNT(*) FROM analytics.dim_customer
UNION ALL SELECT 'dim_material',          COUNT(*) FROM analytics.dim_material
UNION ALL SELECT 'dim_production_line',   COUNT(*) FROM analytics.dim_production_line
UNION ALL SELECT 'fact_sales',            COUNT(*) FROM analytics.fact_sales
UNION ALL SELECT 'fact_shipment',         COUNT(*) FROM analytics.fact_shipment
UNION ALL SELECT 'fact_production_order', COUNT(*) FROM analytics.fact_production_order
UNION ALL SELECT 'fact_production_event', COUNT(*) FROM analytics.fact_production_event
UNION ALL SELECT 'fact_inventory_daily',  COUNT(*) FROM analytics.fact_inventory_daily;
GO
