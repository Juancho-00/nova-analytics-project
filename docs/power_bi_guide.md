# Guía Power BI — Nova Components

## 1. Conexión

1. Power BI Desktop → **Obtener datos → Azure SQL Database**.
2. Servidor: `sql-nova-analyticsserver.database.windows.net` · Base: `free-sql-db-9377179`.
3. Autenticación: **Base de datos** → usuario `powerbi_reader` (solo lectura sobre `analytics`).
4. En el Navegador selecciona solo las vistas del esquema `analytics`.
5. **Transformar datos**: renombra las consultas quitando el prefijo (`analytics dim_date` → `dim_date`).

## 2. Modo de almacenamiento (modelo compuesto)

| Tabla | Modo | Motivo |
|---|---|---|
| `fact_production_event` | **DirectQuery** | Datos operativos "casi en tiempo real" |
| `dim_material`, `dim_production_line`, `dim_date` | **Dual** | Sirven a tablas Import y DirectQuery sin consultas cruzadas lentas |
| Resto de tablas | **Import** | Datos analíticos en caché, rápidos |

> Azure SQL gratuito: DirectQuery consulta la base en cada interacción y consume vCore-segundos del mes. Úsalo para la demo y vuelve a Import si se acerca el límite.

## 3. Relaciones (esquema estrella)

Todas 1 → * con filtro en una sola dirección.

| Dimensión | Tabla de hechos | Columna en el hecho |
|---|---|---|
| `dim_date[date]` | `fact_sales` | `order_date` (activa) |
| `dim_date[date]` | `fact_sales` | `requested_delivery_date` (**inactiva**, se usa con `USERELATIONSHIP`) |
| `dim_date[date]` | `fact_shipment` | `shipment_date` |
| `dim_date[date]` | `fact_production_event` | `event_date` |
| `dim_date[date]` | `fact_production_order` | `created_date` |
| `dim_date[date]` | `fact_inventory_daily` | `date` |
| `dim_material[material_id]` | los 5 hechos | `material_id` |
| `dim_customer[customer_id]` | `fact_sales`, `fact_shipment` | `customer_id` |
| `dim_production_line[production_line_id]` | `fact_production_order`, `fact_production_event` | `production_line_id` |

No se relacionan hechos entre sí. La planta se filtra a través de `dim_material` (y `dim_production_line` para la vista de líneas).

## 4. Configuración del modelo

- `dim_date` → **Marcar como tabla de fechas** (columna `date`).
- `dim_date[month_name]` → **Ordenar por columna** `month_number`; `day_name` por `day_of_week`.
- Oculta las columnas de ID y claves en la vista de informe.
- Crea la tabla `_Medidas` y pega las medidas de `powerbi/measures.dax`.
- Formatos: `%` con 1 decimal; valores en `€` (las plantas están en España).

## 5. Páginas del reporte

1. **Resumen ejecutivo** — tarjetas: Valor Pedidos, Backlog Valor, Despachos a Tiempo %, Tasa Rechazo %, Materiales Bajo Safety Stock. Línea mensual de Valor Pedidos vs Valor Despachado.
2. **Ventas y backlog** — Valor Pedidos por mes y segmento; top clientes; Backlog Vencido; OTIF % por planta; matriz pedido → líneas.
3. **Producción y calidad** — Unidades Buenas vs Rechazadas por día; Tasa Rechazo % por línea y turno (DirectQuery); Cumplimiento Plan %; Utilización Capacidad %; Órdenes Pendientes.
4. **Inventario** — Stock Actual vs Safety Stock por material (barras + línea); evolución diaria del stock; Días de Cobertura; Valor Inventario.

Slicers comunes: fecha (rango), planta (`dim_material[plant_name]`), familia de producto.

## 6. Guardar como PBIP

**Archivo → Guardar como → Proyecto de Power BI (.pbip)** en `powerbi/nova_pbi.pbip`.
Si está disponible, activa en Opciones → Características de vista previa el **formato TMDL** para el modelo semántico: los cambios del modelo quedan legibles en los diffs de git.
El `.gitignore` ya excluye `localSettings.json` y la caché `.abf`.
