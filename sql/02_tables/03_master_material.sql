CREATE TABLE master.material (
    material_id INT IDENTITY(1,1) PRIMARY KEY,

    plant_id INT NOT NULL,

    material_code VARCHAR(30) NOT NULL,
    material_name VARCHAR(100) NOT NULL,
    product_family VARCHAR(30) NOT NULL,

    unit_price DECIMAL(12,2) NOT NULL,
    safety_stock DECIMAL(14,3) NOT NULL,

    CONSTRAINT FK_material_plant
        FOREIGN KEY (plant_id)
        REFERENCES master.plant(plant_id),

    CONSTRAINT UQ_material_plant
        UNIQUE (plant_id, material_code)
);