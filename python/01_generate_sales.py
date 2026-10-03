from connection import engine
from sqlalchemy import text


with engine.begin() as connection:

    result = connection.execute(
        text("""
            INSERT INTO sales.sales_order (
                order_number,
                customer_id,
                plant_id,
                order_date,
                requested_delivery_date,
                order_status
            )
            OUTPUT INSERTED.sales_order_id
            VALUES (
                'SO-PY-001',
                1,
                1,
                GETDATE(),
                DATEADD(day, 10, GETDATE()),
                'CREATED'
            )
        """)
    )

    sales_order_id = result.scalar()

    print("Pedido creado:", sales_order_id)


    connection.execute(
        text("""
            INSERT INTO sales.sales_order_line (
                sales_order_id,
                material_id,
                ordered_quantity,
                delivered_quantity,
                unit_price
            )
            VALUES (
                :sales_order_id,
                1,
                300,
                0,
                12.50
            )
        """),
        {
            "sales_order_id": sales_order_id
        }
    )

    print("Línea de pedido creada")