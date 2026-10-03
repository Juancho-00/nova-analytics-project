from connection import engine
from sqlalchemy import text


with engine.begin() as connection:

    connection.execute(
        text("""
            INSERT INTO inventory.inventory_movement (
                material_id,
                plant_id,
                movement_timestamp,
                movement_type,
                quantity
            )
            VALUES (
                1,
                1,
                GETDATE(),
                'PRODUCTION_RECEIPT',
                97
            )
        """)
    )

    print("Entrada de inventario creada")