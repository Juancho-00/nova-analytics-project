CREATE TABLE master.customer (
    customer_id INT IDENTITY(1,1) PRIMARY KEY,
    customer_code VARCHAR(10) NOT NULL UNIQUE,
    customer_name VARCHAR(100) NOT NULL
);