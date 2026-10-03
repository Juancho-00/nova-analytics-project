"""
Nova Components — Simulador ERP
================================

Reemplaza a 01_generate_sales.py, 02_generate_production.py,
03_update_inventory.py y 04_generate_production_events.py.

Simula la operación de la empresa DÍA A DÍA, siguiendo el flujo de negocio
del README:

    1. Pedidos de clientes      -> sales.sales_order / sales_order_line
    2. Producción por turnos    -> production.production_event
                                   + inventory PRODUCTION_RECEIPT (+)
    3. Entregas a clientes      -> inventory CUSTOMER_SHIPMENT (-)
                                   + delivered_quantity / estado del pedido
    4. Planificación (MRP)      -> production.production_order cuando
                                   stock proyectado < safety stock

Toda la simulación se calcula en memoria y se escribe en Azure SQL al final,
en UNA sola transacción con inserciones masivas (fast_executemany). Si algo
falla, no queda nada a medias.

Uso (desde la raíz del proyecto):
    python python/erp_simulator.py --dry-run          # simula sin escribir
    python python/erp_simulator.py                    # simula hasta hoy y guarda
    python python/erp_simulator.py --end 2026-06-30   # hasta una fecha concreta
    python python/erp_simulator.py --days 1           # solo el día siguiente

La fecha de inicio es automática: el día siguiente a la última ejecución
registrada en simulator.run_log (o al stock inicial si es la primera vez).
"""

from __future__ import annotations

import argparse
import math
from collections import defaultdict, deque
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta

import numpy as np

# =============================================================================
# CONFIGURACIÓN DE LA SIMULACIÓN
# =============================================================================

# --- Demanda ---------------------------------------------------------------
ORDERS_PER_PLANT_PER_DAY = 3.0          # pedidos promedio por planta y día hábil
LINES_PER_ORDER_P = {1: 0.35, 2: 0.45, 3: 0.20}
FAMILY_BASE_QTY = {"INJECTION": 1400, "PAINTED": 850, "ASSEMBLY": 600}
QTY_NOISE_SIGMA = 0.35                  # ruido lognormal de la cantidad pedida
ANNUAL_GROWTH = 0.08                    # tendencia de crecimiento anual
TREND_BASE_DATE = date(2026, 1, 1)

# Estacionalidad mensual (industria automotriz en España: agosto y diciembre bajos)
MONTH_FACTOR = {
    1: 0.90, 2: 1.00, 3: 1.10, 4: 1.05, 5: 1.10, 6: 1.05,
    7: 0.95, 8: 0.60, 9: 1.05, 10: 1.10, 11: 1.10, 12: 0.75,
}

# Segmentos de cliente según su nombre: (factor tamaño, descuento, peso de frecuencia)
CUSTOMER_SEGMENTS = {
    "Automotive":   (1.40, 0.06, 1.3),
    "Industrial":   (1.00, 0.03, 1.0),
    "Distribution": (1.20, 0.04, 1.0),
    "Aftermarket":  (0.60, 0.00, 0.8),
}
DEFAULT_SEGMENT = (1.00, 0.00, 1.0)

LEAD_TIME_DAYS = (7, 21)                # días entre pedido y fecha solicitada
SHIP_WINDOW_DAYS = 3                    # se despacha como máximo N días antes de lo solicitado
MIN_PARTIAL_SHIPMENT = 0.20             # no se despachan parciales < 20% de la línea

# --- Producción ------------------------------------------------------------
SHIFTS = [(6, 14), (14, 22)]            # dos turnos por día
OEE_RANGE = (0.75, 0.95)                # disponibilidad efectiva de la línea por turno
BREAKDOWN_PROB = 0.04                   # probabilidad de avería en un turno
FAMILY_REJECT_RATE = {"INJECTION": 0.020, "PAINTED": 0.045, "ASSEMBLY": 0.015}
REJECT_NOISE_SIGMA = 0.25
REJECT_ANOMALY_PROB = 0.015             # turnos con problema de calidad (útil para ML)
REJECT_ANOMALY_FACTOR = (3.0, 6.0)
MAX_REJECT_RATE = 0.40

# --- Planificación (MRP) ---------------------------------------------------
COVER_DAYS = 5                          # días de demanda extra que cubre cada orden
LOT_ROUNDING = 50                       # tamaño de lote múltiplo de 50
PRODUCTION_LEAD_DAYS = 2                # días hábiles de plazo para terminar la orden
DEMAND_WINDOW = 20                      # días hábiles para el promedio móvil de demanda

# Festivos nacionales fijos (mes, día). Fines de semana tampoco se trabaja.
HOLIDAYS = {(1, 1), (1, 6), (5, 1), (8, 15), (10, 12), (11, 1), (12, 6), (12, 8), (12, 25)}

# Estados válidos (iguales a los CHECK constraints de la base)
SO_CREATED, SO_PARTIAL, SO_COMPLETED = "CREATED", "PARTIALLY_DELIVERED", "COMPLETED"
SO_CLOSED = {"COMPLETED", "CANCELLED"}
PO_PLANNED, PO_IN_PROGRESS, PO_COMPLETED = "PLANNED", "IN_PROGRESS", "COMPLETED"
PO_OPEN = {PO_PLANNED, PO_IN_PROGRESS}


# =============================================================================
# MODELO DE DATOS EN MEMORIA
# =============================================================================

@dataclass
class Material:
    material_id: int
    plant_id: int
    code: str
    family: str
    unit_price: float
    safety_stock: float


@dataclass
class ProductionLine:
    line_id: int
    plant_id: int
    family: str
    daily_capacity: float


@dataclass
class Customer:
    customer_id: int
    name: str
    size_factor: float
    discount: float
    weight: float


@dataclass
class SalesLine:
    line_id: int
    material_id: int
    ordered: float
    delivered: float
    unit_price: float
    is_new: bool
    changed: bool = False

    @property
    def pending(self) -> float:
        return max(self.ordered - self.delivered, 0.0)


@dataclass
class SalesOrder:
    order_id: int
    order_number: str
    customer_id: int
    plant_id: int
    order_date: date
    requested_date: date
    status: str
    lines: list[SalesLine]
    is_new: bool
    changed: bool = False

    def refresh_status(self) -> None:
        ordered = sum(l.ordered for l in self.lines)
        delivered = sum(l.delivered for l in self.lines)
        if delivered <= 0:
            new_status = SO_CREATED
        elif delivered >= ordered:
            new_status = SO_COMPLETED
        else:
            new_status = SO_PARTIAL
        if new_status != self.status:
            self.status = new_status
            self.changed = True


@dataclass
class ProductionOrder:
    po_id: int
    material_id: int
    line_id: int
    planned: float
    good: float
    status: str
    created_at: datetime | None
    start_date: date
    due_date: date | None
    is_new: bool
    changed: bool = False

    @property
    def remaining(self) -> float:
        return max(self.planned - self.good, 0.0)


@dataclass
class State:
    """Foto de la base de datos al inicio de la simulación."""
    materials: dict[int, Material]
    lines: dict[int, ProductionLine]
    customers: list[Customer]
    stock: dict[int, float]
    sales_orders: list[SalesOrder]
    production_orders: list[ProductionOrder]
    next_sales_order_id: int
    next_sales_line_id: int
    next_production_order_id: int
    watermark: date                                   # último día ya simulado
    demand_history: dict[int, deque] = field(default_factory=dict)


# =============================================================================
# CALENDARIO
# =============================================================================

def is_working_day(d: date) -> bool:
    return d.weekday() < 5 and (d.month, d.day) not in HOLIDAYS


def next_working_day(d: date) -> date:
    d += timedelta(days=1)
    while not is_working_day(d):
        d += timedelta(days=1)
    return d


def add_working_days(d: date, n: int) -> date:
    for _ in range(n):
        d = next_working_day(d)
    return d


def segment_for(customer_name: str) -> tuple[float, float, float]:
    for keyword, params in CUSTOMER_SEGMENTS.items():
        if keyword.lower() in customer_name.lower():
            return params
    return DEFAULT_SEGMENT


# =============================================================================
# SIMULADOR (lógica pura, no toca la base de datos)
# =============================================================================

class Simulator:

    def __init__(self, state: State, rng: np.random.Generator):
        self.s = state
        self.rng = rng
        self.events: list[dict] = []
        self.movements: list[dict] = []
        self.stats: dict[str, float] = defaultdict(float)

        self.line_for = {(l.plant_id, l.family): l for l in state.lines.values()}
        self.materials_by_plant: dict[int, list[Material]] = defaultdict(list)
        for m in sorted(state.materials.values(), key=lambda m: m.material_id):
            self.materials_by_plant[m.plant_id].append(m)

        weights = np.array([c.weight for c in state.customers], dtype=float)
        self.customer_p = weights / weights.sum()

        for m in state.materials.values():
            state.demand_history.setdefault(m.material_id, deque(maxlen=DEMAND_WINDOW))
            state.stock.setdefault(m.material_id, 0.0)

        # Validación: cada material debe tener una línea compatible
        missing = [m.code for m in state.materials.values()
                   if (m.plant_id, m.family) not in self.line_for]
        if missing:
            raise ValueError(f"Materiales sin línea compatible (planta+familia): {missing}")

    # ------------------------------------------------------------------ run
    def run(self, start: date, end: date) -> None:
        d = start
        while d <= end:
            if is_working_day(d):
                self.simulate_day(d)
            d += timedelta(days=1)

    def simulate_day(self, d: date) -> None:
        demand_today = self._generate_orders(d)
        # El orden respeta los timestamps: turno 1 (06-14) -> despachos (16h) -> turno 2 (14-22)
        self._run_shift(d, 0)
        self._ship_orders(d)
        for shift_idx in range(1, len(SHIFTS)):
            self._run_shift(d, shift_idx)
        self._plan_production(d)
        for m_id, hist in self.s.demand_history.items():
            hist.append(demand_today.get(m_id, 0.0))
        self.stats["working_days"] += 1

    # ------------------------------------------------------- 1. demanda
    def _generate_orders(self, d: date) -> dict[int, float]:
        demand: dict[int, float] = defaultdict(float)

        # Pedidos ya existentes en la base (histórico CSV) que "llegan" hoy
        for so in self.s.sales_orders:
            if not so.is_new and so.order_date == d:
                for ln in so.lines:
                    demand[ln.material_id] += ln.ordered

        years = (d - TREND_BASE_DATE).days / 365.25
        level = MONTH_FACTOR[d.month] * (1 + ANNUAL_GROWTH) ** years
        seq = 0

        for plant_id, mats in self.materials_by_plant.items():
            n_orders = self.rng.poisson(ORDERS_PER_PLANT_PER_DAY * level)
            for _ in range(n_orders):
                seq += 1
                cust = self.s.customers[self.rng.choice(len(self.s.customers), p=self.customer_p)]
                n_lines = int(self.rng.choice(list(LINES_PER_ORDER_P), p=list(LINES_PER_ORDER_P.values())))
                n_lines = min(n_lines, len(mats))
                picked = self.rng.choice(len(mats), size=n_lines, replace=False)

                order = SalesOrder(
                    order_id=self.s.next_sales_order_id,
                    order_number=f"SO-{d:%Y%m%d}-{seq:03d}",
                    customer_id=cust.customer_id,
                    plant_id=plant_id,
                    order_date=d,
                    requested_date=d + timedelta(days=int(self.rng.integers(LEAD_TIME_DAYS[0], LEAD_TIME_DAYS[1] + 1))),
                    status=SO_CREATED,
                    lines=[],
                    is_new=True,
                )
                self.s.next_sales_order_id += 1

                for idx in sorted(picked):
                    m = mats[idx]
                    raw = FAMILY_BASE_QTY[m.family] * cust.size_factor * self.rng.lognormal(0, QTY_NOISE_SIGMA)
                    qty = float(max(10, round(raw / 10) * 10))
                    order.lines.append(SalesLine(
                        line_id=self.s.next_sales_line_id,
                        material_id=m.material_id,
                        ordered=qty,
                        delivered=0.0,
                        unit_price=round(m.unit_price * (1 - cust.discount), 2),
                        is_new=True,
                    ))
                    self.s.next_sales_line_id += 1
                    demand[m.material_id] += qty
                    self.stats["units_ordered"] += qty

                self.s.sales_orders.append(order)
                self.stats["sales_orders"] += 1
                self.stats["sales_lines"] += len(order.lines)
        return demand

    # ----------------------------------------------------- 2. producción
    def _run_shift(self, d: date, shift_idx: int) -> None:
        _, shift_end = SHIFTS[shift_idx]
        for line in self.s.lines.values():
            queue = sorted(
                (po for po in self.s.production_orders
                 if po.line_id == line.line_id and po.status in PO_OPEN and po.start_date <= d),
                key=lambda po: (po.due_date or d, po.po_id),
            )
            if queue:
                po = queue[0]                                    # una orden por turno (cambio de referencia)
                material = self.s.materials[po.material_id]
                base_rate = FAMILY_REJECT_RATE[material.family]

                capacity = line.daily_capacity / len(SHIFTS) * self.rng.uniform(*OEE_RANGE)
                if self.rng.random() < BREAKDOWN_PROB:
                    capacity *= self.rng.uniform(0.0, 0.3)
                    self.stats["breakdowns"] += 1

                reject_rate = base_rate * self.rng.lognormal(0, REJECT_NOISE_SIGMA)
                if self.rng.random() < REJECT_ANOMALY_PROB:
                    reject_rate *= self.rng.uniform(*REJECT_ANOMALY_FACTOR)
                    self.stats["quality_anomalies"] += 1
                reject_rate = min(reject_rate, MAX_REJECT_RATE)

                # Se fabrica lo que falta + margen por rechazo esperado, limitado por capacidad
                target = math.ceil(po.remaining / (1 - base_rate))
                produced = int(min(target, math.floor(capacity)))
                if produced <= 0:
                    continue  # siguiente línea
                rejected = int(self.rng.binomial(produced, reject_rate))
                good = produced - rejected

                ts = datetime.combine(d, time(shift_end - 1, int(self.rng.integers(0, 60))))
                self.events.append({
                    "production_order_id": po.po_id,
                    "event_timestamp": ts,
                    "produced_quantity": float(produced),
                    "rejected_quantity": float(rejected),
                })
                if good > 0:
                    self.movements.append({
                        "material_id": material.material_id,
                        "plant_id": material.plant_id,
                        "movement_timestamp": ts,
                        "movement_type": "PRODUCTION_RECEIPT",
                        "quantity": float(good),
                        "reference_order": f"PO-{po.po_id}",
                    })
                    self.s.stock[material.material_id] += good

                po.good += good
                po.status = PO_COMPLETED if po.good >= po.planned else PO_IN_PROGRESS
                po.changed = True
                self.stats["production_events"] += 1
                self.stats["units_produced"] += produced
                self.stats["units_rejected"] += rejected

    # ------------------------------------------------------ 3. entregas
    def _ship_orders(self, d: date) -> None:
        candidates = [
            (so, ln)
            for so in self.s.sales_orders
            if so.status not in SO_CLOSED
            and so.order_date < d                                        # se despacha desde el día siguiente
            and (so.requested_date - d).days <= SHIP_WINDOW_DAYS
            for ln in so.lines if ln.pending > 0
        ]
        candidates.sort(key=lambda x: (x[0].requested_date, x[0].order_id, x[1].line_id))  # FIFO por fecha solicitada

        touched: set[int] = set()
        for so, ln in candidates:
            available = self.s.stock[ln.material_id]
            qty = math.floor(min(ln.pending, available))
            if qty <= 0:
                continue
            if qty < ln.pending and qty < MIN_PARTIAL_SHIPMENT * ln.ordered:
                continue

            material = self.s.materials[ln.material_id]
            self.movements.append({
                "material_id": material.material_id,
                "plant_id": material.plant_id,
                "movement_timestamp": datetime.combine(d, time(16, int(self.rng.integers(0, 60)))),
                "movement_type": "CUSTOMER_SHIPMENT",
                "quantity": -float(qty),
                "reference_order": so.order_number,
            })
            self.s.stock[ln.material_id] -= qty
            ln.delivered += qty
            ln.changed = True
            touched.add(id(so))
            self.stats["shipments"] += 1
            self.stats["units_shipped"] += qty
            if d > so.requested_date:
                self.stats["late_shipments"] += 1

        for so in self.s.sales_orders:
            if id(so) in touched:
                so.refresh_status()

    # ---------------------------------------------------- 4. planificación
    def _avg_daily_demand(self, m: Material) -> float:
        hist = self.s.demand_history[m.material_id]
        if len(hist) >= 5:
            return float(np.mean(hist))
        # Sin historia suficiente: demanda esperada teórica
        n_mats = len(self.materials_by_plant[m.plant_id])
        avg_lines = sum(k * p for k, p in LINES_PER_ORDER_P.items())
        return ORDERS_PER_PLANT_PER_DAY * avg_lines / n_mats * FAMILY_BASE_QTY[m.family]

    def _plan_production(self, d: date) -> None:
        pending: dict[int, float] = defaultdict(float)
        for so in self.s.sales_orders:
            if so.status not in SO_CLOSED and so.order_date <= d:
                for ln in so.lines:
                    pending[ln.material_id] += ln.pending

        in_production: dict[int, float] = defaultdict(float)
        for po in self.s.production_orders:
            if po.status in PO_OPEN:
                in_production[po.material_id] += po.remaining

        for m in sorted(self.s.materials.values(), key=lambda m: m.material_id):
            projected = self.s.stock[m.material_id] + in_production[m.material_id] - pending[m.material_id]
            if projected >= m.safety_stock:
                continue

            need = m.safety_stock - projected + self._avg_daily_demand(m) * COVER_DAYS
            qty = float(math.ceil(need / LOT_ROUNDING) * LOT_ROUNDING)
            start = next_working_day(d)
            line = self.line_for[(m.plant_id, m.family)]
            self.s.production_orders.append(ProductionOrder(
                po_id=self.s.next_production_order_id,
                material_id=m.material_id,
                line_id=line.line_id,
                planned=qty,
                good=0.0,
                status=PO_PLANNED,
                created_at=datetime.combine(d, time(18, 0)),
                start_date=start,
                due_date=add_working_days(start, PRODUCTION_LEAD_DAYS - 1),
                is_new=True,
            ))
            self.s.next_production_order_id += 1
            self.stats["production_orders"] += 1


# =============================================================================
# LECTURA Y ESCRITURA EN AZURE SQL
# =============================================================================

def load_state(conn) -> State:
    from sqlalchemy import text

    def rows(sql, **params):
        return conn.execute(text(sql), params).mappings().all()

    materials = {
        r["material_id"]: Material(r["material_id"], r["plant_id"], r["material_code"],
                                   r["product_family"], float(r["unit_price"]), float(r["safety_stock"]))
        for r in rows("SELECT material_id, plant_id, material_code, product_family, unit_price, safety_stock "
                      "FROM master.material")
    }
    lines = {
        r["production_line_id"]: ProductionLine(r["production_line_id"], r["plant_id"],
                                                r["product_family"], float(r["daily_capacity"]))
        for r in rows("SELECT production_line_id, plant_id, product_family, daily_capacity "
                      "FROM master.production_line")
    }
    customers = []
    for r in rows("SELECT customer_id, customer_name FROM master.customer ORDER BY customer_id"):
        size, discount, weight = segment_for(r["customer_name"])
        customers.append(Customer(r["customer_id"], r["customer_name"], size, discount, weight))

    stock = {r["material_id"]: float(r["qty"]) for r in rows(
        "SELECT material_id, SUM(quantity) AS qty FROM inventory.inventory_movement GROUP BY material_id")}

    # Watermark: última fecha simulada (o fecha del stock inicial si es la primera vez)
    wm = conn.execute(text("SELECT MAX(end_date) FROM simulator.run_log")).scalar()
    if wm is None:
        wm = conn.execute(text(
            "SELECT CAST(MAX(movement_timestamp) AS DATE) FROM inventory.inventory_movement "
            "WHERE movement_type = 'INITIAL_STOCK'")).scalar()
    if wm is None:
        raise RuntimeError("No hay stock inicial ni ejecuciones previas: carga primero initial_inventory.csv")

    # Pedidos abiertos con sus líneas
    orders: dict[int, SalesOrder] = {}
    for r in rows("""
        SELECT o.sales_order_id, o.order_number, o.customer_id, o.plant_id, o.order_date,
               o.requested_delivery_date, o.order_status,
               l.sales_order_line_id, l.material_id, l.ordered_quantity, l.delivered_quantity, l.unit_price
        FROM sales.sales_order o
        JOIN sales.sales_order_line l ON l.sales_order_id = o.sales_order_id
        WHERE o.order_status NOT IN ('COMPLETED', 'CANCELLED')
        ORDER BY o.sales_order_id, l.sales_order_line_id
    """):
        so = orders.get(r["sales_order_id"])
        if so is None:
            so = SalesOrder(r["sales_order_id"], r["order_number"], r["customer_id"], r["plant_id"],
                            r["order_date"], r["requested_delivery_date"], r["order_status"], [], is_new=False)
            orders[so.order_id] = so
        so.lines.append(SalesLine(r["sales_order_line_id"], r["material_id"], float(r["ordered_quantity"]),
                                  float(r["delivered_quantity"]), float(r["unit_price"]), is_new=False))

    # Órdenes de producción abiertas con lo ya producido
    pos = []
    for r in rows("""
        SELECT po.production_order_id, po.material_id, po.production_line_id, po.planned_quantity,
               po.order_status, po.created_at, po.due_date,
               ISNULL(SUM(e.produced_quantity - e.rejected_quantity), 0) AS good_qty
        FROM production.production_order po
        LEFT JOIN production.production_event e ON e.production_order_id = po.production_order_id
        WHERE po.order_status IN ('PLANNED', 'IN_PROGRESS')
        GROUP BY po.production_order_id, po.material_id, po.production_line_id, po.planned_quantity,
                 po.order_status, po.created_at, po.due_date
    """):
        created = r["created_at"]
        start = next_working_day(created.date()) if created else next_working_day(wm)
        pos.append(ProductionOrder(r["production_order_id"], r["material_id"], r["production_line_id"],
                                   float(r["planned_quantity"]), float(r["good_qty"]), r["order_status"],
                                   created, start, r["due_date"], is_new=False))

    def next_id(table, col):
        return int(conn.execute(text(f"SELECT ISNULL(MAX({col}), 0) + 1 FROM {table}")).scalar())

    state = State(
        materials=materials, lines=lines, customers=customers, stock=stock,
        sales_orders=list(orders.values()), production_orders=pos,
        next_sales_order_id=next_id("sales.sales_order", "sales_order_id"),
        next_sales_line_id=next_id("sales.sales_order_line", "sales_order_line_id"),
        next_production_order_id=next_id("production.production_order", "production_order_id"),
        watermark=wm,
    )

    # Historia de demanda reciente para el promedio móvil del MRP
    window_start = wm - timedelta(days=DEMAND_WINDOW * 2)
    daily = defaultdict(float)
    for r in rows("""
        SELECT l.material_id, o.order_date, SUM(l.ordered_quantity) AS qty
        FROM sales.sales_order o
        JOIN sales.sales_order_line l ON l.sales_order_id = o.sales_order_id
        WHERE o.order_date > :a AND o.order_date <= :b
        GROUP BY l.material_id, o.order_date
    """, a=window_start, b=wm):
        daily[(r["material_id"], r["order_date"])] = float(r["qty"])
    working_days = [window_start + timedelta(days=i) for i in range(1, (wm - window_start).days + 1)]
    working_days = [d for d in working_days if is_working_day(d)]
    for m_id in materials:
        state.demand_history[m_id] = deque((daily[(m_id, d)] for d in working_days), maxlen=DEMAND_WINDOW)
    return state


def _executemany(conn, sql: str, rows: list[dict], chunk: int = 2000) -> None:
    from sqlalchemy import text
    for i in range(0, len(rows), chunk):
        conn.execute(text(sql), rows[i:i + chunk])


def _insert_with_identity(conn, table: str, sql: str, rows: list[dict]) -> None:
    """Inserta filas con IDs calculados por el simulador (necesario para las FK)."""
    if not rows:
        return
    conn.exec_driver_sql(f"SET IDENTITY_INSERT {table} ON")
    try:
        _executemany(conn, sql, rows)
    finally:
        conn.exec_driver_sql(f"SET IDENTITY_INSERT {table} OFF")


def persist(conn, sim: Simulator, start: date, end: date, seed: int) -> dict[str, int]:
    from sqlalchemy import text
    s = sim.s

    new_orders = [so for so in s.sales_orders if so.is_new]
    new_lines = [(so, ln) for so in new_orders for ln in so.lines]
    upd_orders = [so for so in s.sales_orders if not so.is_new and so.changed]
    upd_lines = [ln for so in s.sales_orders if not so.is_new for ln in so.lines if ln.changed]
    new_pos = [po for po in s.production_orders if po.is_new]
    upd_pos = [po for po in s.production_orders if not po.is_new and po.changed]

    _insert_with_identity(conn, "sales.sales_order", """
        INSERT INTO sales.sales_order (sales_order_id, order_number, customer_id, plant_id,
                                       order_date, requested_delivery_date, order_status)
        VALUES (:id, :num, :cust, :plant, :od, :rd, :st)""",
        [{"id": so.order_id, "num": so.order_number, "cust": so.customer_id, "plant": so.plant_id,
          "od": so.order_date, "rd": so.requested_date, "st": so.status} for so in new_orders])

    _insert_with_identity(conn, "sales.sales_order_line", """
        INSERT INTO sales.sales_order_line (sales_order_line_id, sales_order_id, material_id,
                                            ordered_quantity, delivered_quantity, unit_price)
        VALUES (:id, :so, :mat, :oq, :dq, :price)""",
        [{"id": ln.line_id, "so": so.order_id, "mat": ln.material_id, "oq": ln.ordered,
          "dq": ln.delivered, "price": ln.unit_price} for so, ln in new_lines])

    if upd_lines:
        _executemany(conn, "UPDATE sales.sales_order_line SET delivered_quantity = :dq "
                           "WHERE sales_order_line_id = :id",
                     [{"dq": ln.delivered, "id": ln.line_id} for ln in upd_lines])
    if upd_orders:
        _executemany(conn, "UPDATE sales.sales_order SET order_status = :st WHERE sales_order_id = :id",
                     [{"st": so.status, "id": so.order_id} for so in upd_orders])

    _insert_with_identity(conn, "production.production_order", """
        INSERT INTO production.production_order (production_order_id, material_id, production_line_id,
                                                 planned_quantity, order_status, created_at, due_date)
        VALUES (:id, :mat, :line, :qty, :st, :created, :due)""",
        [{"id": po.po_id, "mat": po.material_id, "line": po.line_id, "qty": po.planned,
          "st": po.status, "created": po.created_at, "due": po.due_date} for po in new_pos])

    if upd_pos:
        _executemany(conn, "UPDATE production.production_order SET order_status = :st "
                           "WHERE production_order_id = :id",
                     [{"st": po.status, "id": po.po_id} for po in upd_pos])

    if sim.events:
        _executemany(conn, """
            INSERT INTO production.production_event (production_order_id, event_timestamp,
                                                     produced_quantity, rejected_quantity)
            VALUES (:production_order_id, :event_timestamp, :produced_quantity, :rejected_quantity)""",
            sim.events)

    if sim.movements:
        _executemany(conn, """
            INSERT INTO inventory.inventory_movement (material_id, plant_id, movement_timestamp,
                                                      movement_type, quantity, reference_order)
            VALUES (:material_id, :plant_id, :movement_timestamp, :movement_type, :quantity, :reference_order)""",
            sim.movements)

    counts = {
        "sales_orders": len(new_orders), "sales_order_lines": len(new_lines),
        "production_orders": len(new_pos), "production_events": len(sim.events),
        "inventory_movements": len(sim.movements),
    }
    conn.execute(text("""
        INSERT INTO simulator.run_log (start_date, end_date, seed, sales_orders, sales_order_lines,
                                       production_orders, production_events, inventory_movements)
        VALUES (:start, :end, :seed, :sales_orders, :sales_order_lines,
                :production_orders, :production_events, :inventory_movements)"""),
        {"start": start, "end": end, "seed": seed, **counts})
    return counts


# =============================================================================
# CLI
# =============================================================================

def print_summary(sim: Simulator, start: date, end: date) -> None:
    st = sim.stats
    produced = st["units_produced"] or 1
    print("\n" + "=" * 64)
    print(f" Simulación {start} -> {end}  ({int(st['working_days'])} días hábiles)")
    print("=" * 64)
    print(f" Pedidos nuevos ............ {int(st['sales_orders']):>8}  ({int(st['sales_lines'])} líneas)")
    print(f" Unidades pedidas .......... {st['units_ordered']:>8,.0f}")
    print(f" Despachos ................. {int(st['shipments']):>8}  ({int(st['late_shipments'])} tarde)")
    print(f" Unidades despachadas ...... {st['units_shipped']:>8,.0f}")
    print(f" Órdenes de producción ..... {int(st['production_orders']):>8}")
    print(f" Eventos de producción ..... {int(st['production_events']):>8}")
    print(f" Unidades producidas ....... {st['units_produced']:>8,.0f}")
    print(f" Tasa de rechazo ........... {st['units_rejected'] / produced:>8.2%}")
    print(f" Averías / anomalías calidad {int(st['breakdowns']):>4} / {int(st['quality_anomalies'])}")
    print(f" Movimientos de inventario . {len(sim.movements):>8}")
    backlog = sum(ln.pending for so in sim.s.sales_orders if so.status not in SO_CLOSED for ln in so.lines)
    print(f" Backlog al cierre (unid.) . {backlog:>8,.0f}")
    below = [m.code + f"/P{m.plant_id}" for m in sim.s.materials.values()
             if sim.s.stock[m.material_id] < m.safety_stock]
    print(f" Materiales bajo safety stock al cierre: {len(below)} {below if below else ''}")
    print("=" * 64)


def main() -> None:
    parser = argparse.ArgumentParser(description="Simulador ERP de Nova Components")
    parser.add_argument("--end", type=date.fromisoformat, help="Última fecha a simular (AAAA-MM-DD). Por defecto: hoy")
    parser.add_argument("--days", type=int, help="Simular N días calendario desde la última ejecución")
    parser.add_argument("--seed", type=int, default=42, help="Semilla para reproducibilidad (por defecto 42)")
    parser.add_argument("--dry-run", action="store_true", help="Simula y muestra el resumen sin escribir en la base")
    args = parser.parse_args()

    from connection import engine

    with engine.begin() as conn:
        state = load_state(conn)
        start = state.watermark + timedelta(days=1)
        end = args.end or (state.watermark + timedelta(days=args.days) if args.days else date.today())
        if end < start:
            print(f"Nada que simular: la base ya está simulada hasta {state.watermark}.")
            return

        rng = np.random.default_rng([args.seed, start.toordinal()])
        sim = Simulator(state, rng)
        sim.run(start, end)
        print_summary(sim, start, end)

        if args.dry_run:
            print("\n--dry-run: no se escribió nada en la base.")
            return

        print("\nEscribiendo en Azure SQL (una sola transacción)...")
        counts = persist(conn, sim, start, end, args.seed)
        print("✅ Guardado:", ", ".join(f"{k}={v}" for k, v in counts.items()))


if __name__ == "__main__":
    main()
