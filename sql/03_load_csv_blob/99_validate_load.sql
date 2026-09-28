-- a) Conteo staging vs final (repite por tabla)
SELECT 'material' AS tabla,
       (SELECT COUNT(*) FROM staging.material)    AS filas_stg,
       (SELECT COUNT(*) FROM master.material) AS filas_final;

-- b) Filas de staging que no hicieron match (se "perdieron" en el JOIN)
SELECT s.*
FROM staging.material s
LEFT JOIN master.plant p 
    ON p.plant_code = s.plant_code
WHERE p.plant_id IS NULL;

-- c) Conversiones fallidas (TRY_CAST devolvió NULL)
SELECT * FROM staging.material
WHERE unit_price IS NOT NULL AND TRY_CAST(unit_price AS DECIMAL(12,2)) IS NULL;

-- Ningún material debería arrancar con stock negativo
SELECT material_id, SUM(quantity) AS stock
FROM staging.inventory_movement
GROUP BY material_id
HAVING SUM(quantity) < 0;