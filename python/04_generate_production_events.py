"""
Script para generar órdenes de producción y eventos del mes de agosto 2026.
Recupera IDs válidos de la base de datos y genera datos consistentes.
"""

from connection import engine
from sqlalchemy import text
from datetime import datetime, timedelta
import random

# Configuración de agosto 2026
AUGUST_START = datetime(2026, 8, 1)
AUGUST_END = datetime(2026, 8, 31)

# Estados posibles para las órdenes
ORDER_STATUSES = ['CREATED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED']


def get_available_ids():
    """Consulta la base de datos para obtener IDs válidos de materiales y líneas de producción."""
    with engine.begin() as connection:
        # Obtener IDs de materiales (diferentes plantas)
        materials_result = connection.execute(
            text("SELECT DISTINCT material_id FROM master.material ORDER BY material_id")
        )
        materials = [row[0] for row in materials_result.fetchall()]

        # Obtener IDs de líneas de producción
        lines_result = connection.execute(
            text("SELECT production_line_id FROM master.production_line ORDER BY production_line_id")
        )
        production_lines = [row[0] for row in lines_result.fetchall()]

        print(f"✓ Materiales disponibles (plantas diferentes): {materials}")
        print(f"✓ Líneas de producción disponibles: {production_lines}")

        return materials, production_lines


def generate_random_date_in_august():
    """Genera una fecha aleatoria en agosto 2026."""
    days_in_august = (AUGUST_END - AUGUST_START).days
    random_day = random.randint(0, days_in_august)
    random_hour = random.randint(6, 22)  # Entre 6 AM y 10 PM
    random_minute = random.randint(0, 59)
    
    return AUGUST_START + timedelta(days=random_day, hours=random_hour, minutes=random_minute)


def insert_production_orders_and_events(num_orders=10):
    """
    Inserta órdenes de producción y sus eventos para agosto 2026.
    
    Args:
        num_orders: Número de órdenes a generar (por defecto 10)
    """
    
    # Obtener IDs válidos
    materials, production_lines = get_available_ids()
    
    if not materials or not production_lines:
        print("❌ Error: No hay materiales o líneas de producción disponibles en la BD")
        return
    
    print(f"\n📋 Generando {num_orders} órdenes de producción para agosto 2026...\n")
    
    orders_created = []
    events_created = []
    
    try:
        with engine.begin() as connection:
            
            for order_idx in range(1, num_orders + 1):
                try:
                    # Seleccionar IDs aleatorios
                    material_id = random.choice(materials)
                    production_line_id = random.choice(production_lines)
                    planned_quantity = random.randint(100, 1000)
                    order_date = generate_random_date_in_august()
                    
                    # Determinar estado según si hay eventos
                    num_events = random.randint(1, 5)
                    if num_events > 3:
                        order_status = 'COMPLETED'
                    elif num_events > 1:
                        order_status = 'IN_PROGRESS'
                    else:
                        order_status = 'CREATED'
                    
                    # Insertar orden de producción
                    result = connection.execute(
                        text("""
                            INSERT INTO production.production_order (
                                material_id,
                                production_line_id,
                                planned_quantity,
                                order_status
                            )
                            OUTPUT INSERTED.production_order_id
                            VALUES (
                                :material_id,
                                :production_line_id,
                                :planned_quantity,
                                :order_status
                            )
                        """),
                        {
                            "material_id": material_id,
                            "production_line_id": production_line_id,
                            "planned_quantity": planned_quantity,
                            "order_status": order_status
                        }
                    )
                    
                    production_order_id = result.scalar()
                    orders_created.append(production_order_id)
                    
                    print(f"  Orden {order_idx}: PO-ID={production_order_id} | "
                          f"Material={material_id} | Línea={production_line_id} | "
                          f"Cantidad Planeada={planned_quantity} | Estado={order_status}")
                    
                    # Generar eventos de producción para esta orden
                    total_produced = 0
                    total_rejected = 0
                    event_date = order_date
                    
                    for event_idx in range(num_events):
                        # Calcular producción incremental sin exceder el planeado
                        remaining = planned_quantity - total_produced
                        produced = random.randint(max(10, remaining // (num_events - event_idx)), 
                                                 min(remaining, int(remaining * 0.9)))
                        
                        # Rechazo es máximo 10% de lo producido en este evento
                        rejected = random.randint(0, max(1, int(produced * 0.1)))
                        
                        total_produced += produced
                        total_rejected += rejected
                        
                        # Avanzar la fecha del evento (1 a 3 días después del anterior)
                        event_date = event_date + timedelta(
                            days=random.randint(1, 3),
                            hours=random.randint(6, 22)
                        )
                        
                        # Asegurar que no salga de agosto
                        if event_date > AUGUST_END:
                            event_date = AUGUST_END - timedelta(hours=random.randint(1, 12))
                        
                        connection.execute(
                            text("""
                                INSERT INTO production.production_event (
                                    production_order_id,
                                    event_timestamp,
                                    produced_quantity,
                                    rejected_quantity
                                )
                                VALUES (
                                    :production_order_id,
                                    :event_timestamp,
                                    :produced_quantity,
                                    :rejected_quantity
                                )
                            """),
                            {
                                "production_order_id": production_order_id,
                                "event_timestamp": event_date,
                                "produced_quantity": produced,
                                "rejected_quantity": rejected
                            }
                        )
                        
                        events_created.append(production_order_id)
                        print(f"    └─ Evento {event_idx + 1}: Producido={produced}, Rechazado={rejected}, "
                              f"Fecha={event_date.strftime('%Y-%m-%d %H:%M')} "
                              f"(Total: {total_produced} producido, {total_rejected} rechazado)")
                
                except Exception as e:
                    print(f"  ❌ Error en orden {order_idx}: {str(e)}")
                    continue
        
        # Resumen
        print(f"\n✅ Proceso completado exitosamente!")
        print(f"   • Órdenes creadas: {len(orders_created)}")
        print(f"   • Eventos creados: {len(events_created)}")
        
    except Exception as e:
        print(f"❌ Error general: {str(e)}")
        return


if __name__ == "__main__":
    print("=" * 70)
    print("GENERADOR DE ÓRDENES Y EVENTOS DE PRODUCCIÓN - AGOSTO 2026")
    print("=" * 70)
    
    # Puedes cambiar el número de órdenes aquí
    NUM_ORDERS = 10
    
    insert_production_orders_and_events(num_orders=NUM_ORDERS)