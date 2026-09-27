CREATE TABLE sales.sales_order (
    sales_order_id BIGINT IDENTITY(1,1) PRIMARY KEY,

    order_number VARCHAR(30) NOT NULL UNIQUE,

    customer_id INT NOT NULL,
    plant_id INT NOT NULL,

    order_date DATE NOT NULL,
    requested_delivery_date DATE NOT NULL,

    order_status VARCHAR(30) NOT NULL,

    CONSTRAINT FK_sales_order_customer
        FOREIGN KEY (customer_id)
        REFERENCES master.customer(customer_id),

    CONSTRAINT FK_sales_order_plant
        FOREIGN KEY (plant_id)
        REFERENCES master.plant(plant_id)
);