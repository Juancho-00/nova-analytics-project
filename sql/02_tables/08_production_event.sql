CREATE TABLE production.production_event (
    production_event_id BIGINT IDENTITY(1,1) PRIMARY KEY,

    production_order_id BIGINT NOT NULL,
    event_timestamp DATETIME2 NOT NULL,

    produced_quantity DECIMAL(14,3) NOT NULL,
    rejected_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,

    CONSTRAINT FK_production_event_order
        FOREIGN KEY (production_order_id)
        REFERENCES production.production_order(production_order_id)
);