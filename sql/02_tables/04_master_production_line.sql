CREATE TABLE master.production_line (
    production_line_id INT IDENTITY(1,1) PRIMARY KEY,

    plant_id INT NOT NULL,

    line_code VARCHAR(20) NOT NULL,
    line_name VARCHAR(100) NOT NULL,

    product_family VARCHAR(30) NOT NULL,
    daily_capacity DECIMAL(14,3) NOT NULL,

    CONSTRAINT FK_production_line_plant
        FOREIGN KEY (plant_id)
        REFERENCES master.plant(plant_id),

    CONSTRAINT UQ_production_line
        UNIQUE (plant_id, line_code)
);