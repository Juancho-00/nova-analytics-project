CREATE TABLE sales.sales_order_line (
    sales_order_line_id BIGINT IDENTITY(1,1) PRIMARY KEY,

    sales_order_id BIGINT NOT NULL,
    material_id INT NOT NULL,

    ordered_quantity DECIMAL(14,3) NOT NULL,
    delivered_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,

    unit_price DECIMAL(12,2) NOT NULL,

    CONSTRAINT FK_sales_order_line_order
        FOREIGN KEY (sales_order_id)
        REFERENCES sales.sales_order(sales_order_id),

    CONSTRAINT FK_sales_order_line_material
        FOREIGN KEY (material_id)
        REFERENCES master.material(material_id)
);