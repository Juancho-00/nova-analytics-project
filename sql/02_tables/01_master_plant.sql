CREATE TABLE master.plant (
    plant_id INT IDENTITY(1,1) PRIMARY KEY,
    plant_code VARCHAR(10) NOT NULL UNIQUE,
    plant_name VARCHAR(100) NOT NULL,
    city VARCHAR(50) NOT NULL
);