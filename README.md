
# Nova Components — End-to-End Data Analytics Project

## Overview

This repository contains the complete project used in the **Nova Components End-to-End Data Analytics Masterclass**.

The objective is to build, from scratch, a simplified but realistic data solution using:

```text
Azure Blob Storage
        ↓
Azure SQL Database
        ↓
Python ERP Simulator
        ↓
Power BI
```

The project is designed for beginners and focuses on understanding how different technologies work together in a complete Data Analytics workflow.

The fictional company used throughout the project is **Nova Components**, a manufacturing company with several plants, customers, materials, production lines, sales orders, production processes and inventory movements.

---

# Project Architecture

```text
CSV Files
   ↓
Azure Blob Storage
   ↓
Azure SQL Database
   ↓
Python ERP Simulator
   ↓
Analytics Views
   ↓
Power BI PBIP
```

Each technology has a different responsibility.

### Azure Blob Storage

Stores the initial and historical files used by the project.

Examples:

```text
plants.csv
customers.csv
materials.csv
production_lines.csv
historical_sales_orders.csv
historical_sales_order_lines.csv
initial_inventory.csv
```

Blob Storage also introduces the fundamentals that can later evolve into architectures based on:

```text
Data Lake
   ↓
Delta Lake
   ↓
Lakehouse
```

---

### Azure SQL Database

Azure SQL contains the operational data model of Nova Components.

The database is divided into different SQL schemas according to the business area:

```text
master
sales
production
inventory
```

This separation makes the model easier to understand and maintain.

---

### Python ERP Simulator

Python will simulate new operational activity inside the company.

It will generate operations such as:

```text
New sales orders
Production orders
Production events
Inventory receipts
Customer deliveries
```

The idea is to simulate how an ERP or industrial application could continuously generate new data.

---

### Power BI

Power BI will be the analytical layer of the project.

The report will be developed using the **PBIP format**, allowing the Power BI project to live inside the same Git repository as the SQL and Python code.

The final analytical model will include information about:

```text
Sales
Backlog
Production
Rejects
Inventory
Stock levels
Customer deliveries
```

---

# Repository Structure

```text
nova-analytics-project/
│
├── sql/
│   ├── 00_db_queries/
│   │   └── 00_sql_db.sql
│   │
│   ├── 01_schemas/
│   │   └── 01_create_schemas.sql
│   │
│   ├── 02_tables/
│   │   ├── 01_master_plant.sql
│   │   ├── 02_master_customer.sql
│   │   ├── 03_master_material.sql
│   │   ├── 04_master_production_line.sql
│   │   ├── 05_sales_order.sql
│   │   ├── 06_sales_order_line.sql
│   │   ├── 07_production_order.sql
│   │   ├── 08_production_event.sql
│   │   └── 09_inventory.sql
│   │
│   └── 03_load_csv_blob/
│       ├── 01_load_csv_plant_from_blob.sql
│       ├── 02_load_csv_material.sql
│       ├── 03_load_csv_customers.sql
│       ├── 04_load_csv_production_lines.sql
│       ├── 05_load_csv_historical_sales_orders.sql
│       ├── 06_load_csv_order_lines.sql
│       └── 07_inventory.sql
│
├── python/
│   ├── db_connection.py
│   ├── 01_generate_sales.py
│   ├── 02_generate_production.py
│   ├── 03_update_inventory.py
│   ├── 04_generate_production_events.py
│   └── __pycache__/
│
├── data/
│
├── powerbi/
│   ├── nova_pbi.pbip
│   ├── nova_pbi.Report/
│   └── nova_pbi.SemanticModel/
│
├── docs/
│
├── .git/
├── .gitignore
├── README.md
└── (other project files)
```

---

# SQL Structure

The operational database is organized into 4 main schemas:

- `master` - Company master data (plants, customers, materials, production lines)
- `sales` - Customer orders and order lines
- `production` - Manufacturing operations (production orders and events)
- `inventory` - Stock movements

## Database Tables

### Master Schema (master)

#### master.plant

Stores the company's manufacturing plants.

```text
plant_id (INT, PK, Identity)
plant_code (VARCHAR)
plant_name (VARCHAR)
city (VARCHAR)
```

#### master.customer

Stores customer information.

```text
customer_id (INT, PK, Identity)
customer_code (VARCHAR)
customer_name (VARCHAR)
```

#### master.material

Represents products or materials managed by each plant.

```text
material_id (INT, PK, Identity)
plant_id (INT, FK)
material_code (VARCHAR)
material_name (VARCHAR)
product_family (VARCHAR)
unit_price (DECIMAL)
safety_stock (DECIMAL)
```

#### master.production_line

Represents the manufacturing lines available in each plant.

```text
production_line_id (INT, PK, Identity)
plant_id (INT, FK)
line_code (VARCHAR)
line_name (VARCHAR)
product_family (VARCHAR)
daily_capacity (DECIMAL)
```

---

### Sales Schema (sales)

#### sales.sales_order

Header of a customer order.

```text
sales_order_id (BIGINT, PK, Identity)
order_number (VARCHAR)
customer_id (INT, FK)
plant_id (INT, FK)
order_date (DATETIME2)
requested_delivery_date (DATETIME2)
order_status (VARCHAR)
```

#### sales.sales_order_line

Individual materials requested in a sales order.

```text
sales_order_line_id (BIGINT, PK, Identity)
sales_order_id (BIGINT, FK)
material_id (INT, FK)
ordered_quantity (DECIMAL)
delivered_quantity (DECIMAL)
unit_price (DECIMAL)
```

---

### Production Schema (production)

#### production.production_order

Manufacturing instruction for a specific quantity of material.

```text
production_order_id (BIGINT, PK, Identity)
material_id (INT, FK)
production_line_id (INT, FK)
planned_quantity (DECIMAL)
order_status (VARCHAR)
```

#### production.production_event

Production updates generated by the ERP simulator.

```text
production_event_id (BIGINT, PK, Identity)
production_order_id (BIGINT, FK)
event_timestamp (DATETIME2)
produced_quantity (DECIMAL)
rejected_quantity (DECIMAL)
```

---

### Inventory Schema (inventory)

#### inventory.inventory_movement

Inventory movements (not fixed stock values).

```text
inventory_movement_id (BIGINT, PK, Identity)
material_id (INT, FK)
plant_id (INT, FK)
movement_type (VARCHAR)
quantity (DECIMAL)
movement_date (DATETIME2)
reference_order (VARCHAR)
```

---

# SQL Execution Order

To set up the database, execute SQL scripts in this order:

1. `01_schemas/01_create_schemas.sql` - Creates the 4 main schemas
2. `02_tables/01_master_plant.sql` - Create master tables
3. `02_tables/02_master_customer.sql`
4. `02_tables/03_master_material.sql`
5. `02_tables/04_master_production_line.sql`
6. `02_tables/05_sales_order.sql` - Create sales tables
7. `02_tables/06_sales_order_line.sql`
8. `02_tables/07_production_order.sql` - Create production tables
9. `02_tables/08_production_event.sql`
10. `02_tables/09_inventory.sql` - Create inventory table
11. `03_load_csv_blob/*` - Load initial data from Azure Blob Storage

---

# Business Flow

The simplified business process is:

```text
CUSTOMER
   ↓
SALES ORDER
   ↓
SALES ORDER LINE
   ↓
CHECK STOCK
   ↓
Is stock available?
   │
   ├── YES
   │     ↓
   │  CUSTOMER DELIVERY
   │     ↓
   │  INVENTORY MOVEMENT (-)
   │
   └── NO
         ↓
   PRODUCTION ORDER
         ↓
   PRODUCTION EVENTS
         ↓
   GOOD QUANTITY
         ↓
   INVENTORY MOVEMENT (+)
         ↓
   STOCK AVAILABLE
         ↓
   CUSTOMER DELIVERY
         ↓
   INVENTORY MOVEMENT (-)
```

There are no specific shipment or machine tables in this MVP.

The objective is to keep the model understandable while still representing a complete manufacturing workflow.

---

# Data Ingestion Strategy

The project uses two ingestion patterns.

## CSV

CSV files represent initial and historical data.

```text
plants.csv
customers.csv
materials.csv
production_lines.csv
historical_sales_orders.csv
historical_sales_order_lines.csv
initial_inventory.csv
```

They are stored in Azure Blob Storage before being loaded into Azure SQL.

---

## Python

Python represents new ERP activity.

It will create new operational data such as:

```text
Sales orders
Sales order lines
Production orders
Production events
Inventory movements
```

Therefore:

```text
CSV
=
Initial / Historical Data

Python
=
New Operational Data
```

### Python Scripts

#### db_connection.py

Centralizes database connection configuration for all Python scripts.

**Connection Details:**

- Server: sql-nova-analyticserver.database.windows.net
- Database: free-sql-db-9377179
- Authentication: SQL Server (username/password)
- Libraries: pyodbc, SQLAlchemy

---

#### 01_generate_sales.py

Generates new sales orders with order lines.

**Functionality:**

- Creates sales orders with unique order numbers
- Links orders to existing customers and plants
- Adds order lines with materials and unit prices
- Sets order status and delivery dates

**Database Tables:**

- `sales.sales_order`
- `sales.sales_order_line`

---

#### 02_generate_production.py

Generates production orders and their first production events.

**Functionality:**

- Creates production orders for specific materials and production lines
- Associates orders with production lines
- Generates initial production events with quantities and rejects

**Database Tables:**

- `production.production_order`
- `production.production_event`

---

#### 03_update_inventory.py

Updates inventory movements based on production receipts and customer shipments.

**Functionality:**

- Records inventory movements
- Tracks movement types (INITIAL_STOCK, PRODUCTION_RECEIPT, CUSTOMER_SHIPMENT, etc.)
- Maintains stock movements for analytics

**Database Tables:**

- `inventory.inventory_movement`

---

#### 04_generate_production_events.py (NEW)

Generates multiple production orders and their events for August 2026.

**Functionality:**

- Queries database for valid material and production line IDs
- Creates 10 production orders (configurable) with realistic data
- Generates 1-5 production events per order (with dates in August 2026)
- Ensures data coherence:
  - Produced quantity never exceeds planned quantity
  - Incremental production across events
  - Rejection rate max 10% of produced quantity
  - Order status reflects progress (CREATED → IN_PROGRESS → COMPLETED)
  - All dates remain within August 2026 (6 AM - 10 PM)

**Usage:**

```bash
python 04_generate_production_events.py
```

**Output:**

- Displays all created orders and events
- Shows cumulative production totals
- Provides summary of insertions

---

# Azure Storage

The Storage Account acts as the cloud file layer of the solution.

Example structure:

```text
Storage Account
│
└── nova-data
    │
    ├── master/
    │   ├── plants.csv
    │   ├── customers.csv
    │   ├── materials.csv
    │   └── production_lines.csv
    │
    ├── historical/
    │   ├── historical_sales_orders.csv
    │   └── historical_sales_order_lines.csv
    │
    └── initial/
        └── initial_inventory.csv
```

This introduces an important Data Engineering concept:

```text
Object Storage
     ↓
Data Lake
     ↓
Delta Lake
     ↓
Lakehouse
```

The masterclass starts with simple CSV files but uses concepts that can later be applied to Microsoft Fabric, Databricks and modern Lakehouse architectures.

---

# Power BI Strategy

The final Power BI solution will combine different connectivity approaches.

### Import

Suitable for:

```text
Plants
Customers
Materials
Sales Orders
Sales Order Lines
Production Orders
Historical Inventory
```

### DirectQuery

Suitable for recent operational data such as:

```text
production.production_event
```

This allows the course to demonstrate the difference between cached analytical data and near real-time operational data.

---

# Analytics Layer

Power BI will not necessarily connect directly to every operational table.

A later step of the project will create an additional SQL schema:

```text
analytics
```

This schema will contain simplified SQL views prepared for reporting.

Example:

```text
analytics.dim_customer
analytics.dim_material
analytics.fact_sales
analytics.fact_production
analytics.fact_inventory
```

This allows the operational model and analytical model to remain separated.

---

# Main KPIs

The final Power BI report can calculate metrics such as:

```text
Ordered Quantity
Delivered Quantity
Pending Quantity
Sales Value
Backlog Value

Current Stock
Safety Stock
Materials Below Safety Stock

Produced Quantity
Good Quantity
Rejected Quantity
Rejection Rate

Production Attainment
Orders Completed
Orders Pending
```

---

# Example Stock Logic

Each material contains a safety stock value.

Example:

```text
Material: MAT001
Plant: 1

Current Stock = 320
Safety Stock = 500
```

Since:

```text
320 < 500
```

the ERP simulator can detect a shortage and generate a production requirement.

Conceptually:

```text
Current Stock
      ↓
Compare with
Safety Stock
      ↓
Stock shortage
      ↓
Production Order
```

---

# Development Workflow

The project follows this implementation order:

```text
1. Azure Resource Group
2. Azure SQL Server + Database
3. Azure Storage Account
4. SQL security
5. SQL schemas
6. Operational tables
7. Blob containers and CSV files
8. CSV ingestion into Azure SQL
9. Python ERP simulator
10. Analytics SQL views
11. Power BI PBIP
12. Final dashboard
```

---

# Git Strategy

The complete solution lives in a single repository.

This means SQL, Python, documentation and Power BI can evolve together.

Example:

```text
SQL changes
Python changes
Power BI changes
Documentation
        ↓
     Git Commit
        ↓
     Repository
```

This makes the project reproducible and easier to present as a complete Data / AI Engineering portfolio project.

---

# Security

Real credentials must never be committed to Git.

The project should use:

```text
.env
```

for local secrets.

Example:

```text
AZURE_SQL_SERVER=
AZURE_SQL_DATABASE=
AZURE_SQL_USER=
AZURE_SQL_PASSWORD=
```

The real `.env` file must be excluded using `.gitignore`.

Only an example file should be committed:

```text
.env.example
```

---

# Project Goal

The final objective is not simply to create a Power BI dashboard.

The goal is to understand the complete journey of data:

```text
SOURCE
   ↓
STORAGE
   ↓
DATABASE
   ↓
APPLICATION / PYTHON
   ↓
DATA MODEL
   ↓
ANALYTICS
   ↓
POWER BI
```

By the end of the project, the student will have built a complete cloud-based Data Analytics solution using technologies and concepts commonly found in real Data Engineering and Analytics environments.

---

## Nova Components

**End-to-End Data Analytics with Azure, SQL, Python and Power BI**
