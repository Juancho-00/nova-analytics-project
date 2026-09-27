CREATE TABLE inventory.inventory_movement (
    inventory_movement_id BIGINT IDENTITY(1,1) PRIMARY KEY,

    material_id INT NOT NULL,
    plant_id INT NOT NULL,

    movement_timestamp DATETIME2 NOT NULL,
    movement_type VARCHAR(30) NOT NULL,

    quantity DECIMAL(14,3) NOT NULL,

    CONSTRAINT FK_inventory_movement_material
        FOREIGN KEY (material_id)
        REFERENCES master.material(material_id),

    CONSTRAINT FK_inventory_movement_plant
        FOREIGN KEY (plant_id)
        REFERENCES master.plant(plant_id)
);