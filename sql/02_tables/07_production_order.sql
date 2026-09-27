CREATE TABLE production.production_order (
    production_order_id BIGINT IDENTITY(1,1) PRIMARY KEY,

    material_id INT NOT NULL,
    production_line_id INT NOT NULL,

    planned_quantity DECIMAL(14,3) NOT NULL,
    order_status VARCHAR(20) NOT NULL,

    CONSTRAINT FK_production_order_material
        FOREIGN KEY (material_id)
        REFERENCES master.material(material_id),

    CONSTRAINT FK_production_order_line
        FOREIGN KEY (production_line_id)
        REFERENCES master.production_line(production_line_id)
);