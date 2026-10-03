from connection import engine
from sqlalchemy import text


with engine.begin() as connection:

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
                2,
                2,
                500,
                'IN_PROGRESS'
            )
        """)
    )

    production_order_id = result.scalar()

    print("Orden de producción creada:", production_order_id)


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
                GETDATE(),
                100,
                3
            )
        """),
        {
            "production_order_id": production_order_id
        }
    )

    print("Evento de producción creado")