-- Database and schema for the project
USE DATABASE COFFEE_SHOP_DW;
USE SCHEMA PUBLIC;

-- Creating a file format for CSV files with header skipping and error handling
CREATE OR REPLACE FILE FORMAT csv_format
TYPE = 'CSV'
SKIP_HEADER = 1
FIELD_OPTIONALLY_ENCLOSED_BY = '"'
ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

-- Creating a staging area for data loading
CREATE OR REPLACE STAGE coffee_shop_stage;

-- Listing files currently in the stage to verify uploaded data
LIST @coffee_shop_stage;

-- Creating the dimension table for customer information
CREATE OR REPLACE TABLE dim_customer (
    customer_id BIGINT PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone_number TEXT,
    loyalty_member_yn TEXT,
    birth_date DATE,
    gender TEXT
);

-- Creating the dimension table for product details
CREATE OR REPLACE TABLE dim_product (
    product_id BIGINT PRIMARY KEY,
    product_group TEXT,
    product_category TEXT,
    product_type TEXT,
    product TEXT,
    product_description TEXT,
    unit_of_measure TEXT,
    current_wholesale_price DECIMAL(10,2),
    current_retail_price DECIMAL(10,2),
    tax_exempt_yn TEXT,
    promo_yn TEXT,
    new_product_yn TEXT
);

-- Creating the dimension table for store details
CREATE OR REPLACE TABLE dim_store (
    store_id BIGINT PRIMARY KEY,
    store_name TEXT,
    location TEXT,
    store_manager TEXT
);

-- Creating the dimension table for staff details
CREATE OR REPLACE TABLE dim_staff (
    staff_id BIGINT PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    position TEXT,
    start_date DATE,
    assigned_store_id BIGINT
);

-- Creating the dimension table for date information
CREATE OR REPLACE TABLE dim_date (
    date_id BIGINT PRIMARY KEY,
    full_date DATE,
    year INT,
    month INT,
    day INT,
    weekday TEXT
);

-- Creating a staging table for processing date information
CREATE OR REPLACE TABLE stage_dim_date (
    full_date DATE
);

-- Loading date data from the staged CSV file into the staging table
COPY INTO stage_dim_date (full_date)
FROM (
    SELECT TO_DATE($1, 'MM/DD/YYYY') AS full_date
    FROM @coffee_shop_stage/Dates.csv
)
FILE_FORMAT = csv_format
ON_ERROR = 'CONTINUE';

-- Inserting transformed date records into the main date dimension table
INSERT INTO dim_date (date_id, full_date, year, month, day, weekday)
SELECT 
    ROW_NUMBER() OVER (ORDER BY full_date) AS date_id,
    full_date,
    YEAR(full_date),
    MONTH(full_date),
    DAY(full_date),
    DAYNAME(full_date)
FROM stage_dim_date;

-- Creating the dimension table for location details
CREATE OR REPLACE TABLE dim_location (
    location_id BIGINT PRIMARY KEY,
    location_name TEXT
);

-- Creating the fact table for sales transactions
CREATE OR REPLACE TABLE fact_sales (
    transaction_id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    product_id BIGINT,
    store_id BIGINT,
    date_id BIGINT,
    staff_id BIGINT,
    quantity_sold INT,
    total_sales_amount DECIMAL(10,2)
);

-- Loading customer data from staged CSV file into customer dimension
COPY INTO dim_customer 
FROM @coffee_shop_stage/customer.csv
FILE_FORMAT = csv_format;

-- Loading product data with price transformations into product dimension
COPY INTO dim_product
FROM (
    SELECT 
        $1, $2, $3, $4, $5, $6, $7,
        TO_NUMBER(REPLACE($8, '$', '')) AS current_wholesale_price,
        TO_NUMBER(REPLACE($9, '$', '')) AS current_retail_price,
        $10, $11, $12
    FROM @coffee_shop_stage/product.csv
)
FILE_FORMAT = csv_format
ON_ERROR = 'CONTINUE';

-- Loading store data from staged CSV file into store dimension
COPY INTO dim_store 
FROM @coffee_shop_stage/sales_outlet.csv
FILE_FORMAT = csv_format;

-- Inserting predefined location details for warehouse and headquarters
INSERT INTO dim_location (location_id, location_name) VALUES 
(999, 'Headquarters'),
(888, 'Warehouse'),
(3, 'Store 3'),
(4, 'Store 4'),
(5, 'Store 5'),
(6, 'Store 6'),
(7, 'Store 7'),
(9, 'Store 9'),
(10, 'Store 10');

-- Loading staff data with store ID transformation into staff dimension
COPY INTO dim_staff
FROM (
    SELECT 
        $1, $2, $3, $4, $5,
        CASE 
            WHEN $6 = 'HQ' THEN 999
            WHEN $6 = 'WH' THEN 888
            ELSE $6::BIGINT
        END
    FROM @coffee_shop_stage/staff.csv
)
FILE_FORMAT = csv_format
ON_ERROR = 'CONTINUE';

-- Ensuring staff dimension has location_id column
ALTER TABLE dim_staff ADD COLUMN location_id BIGINT;

-- Assigning location IDs correctly in staff table
UPDATE dim_staff
SET location_id = 
    CASE 
        WHEN assigned_store_id IS NULL AND first_name = 'HQ' THEN 999  
        WHEN assigned_store_id IS NULL AND first_name = 'WH' THEN 888  
        ELSE assigned_store_id
    END;

-- Loading fact sales data with transformed date IDs into sales fact table
COPY INTO fact_sales (
    TRANSACTION_ID, CUSTOMER_ID, PRODUCT_ID, STORE_ID, DATE_ID, STAFF_ID, QUANTITY_SOLD, TOTAL_SALES_AMOUNT
)
FROM (
    SELECT
        $1, $6, $10, $4,
        TO_NUMBER(TO_CHAR(TO_DATE($2, 'YYYY-MM-DD'), 'YYYYMMDD')),
        $5, $11, $12
    FROM @coffee_shop_stage/sales_receipts.csv
)
FILE_FORMAT = csv_format
ON_ERROR = 'CONTINUE';

-- Inserting missing date records into dim_date
INSERT INTO dim_date (date_id, full_date, year, month, day, weekday)
SELECT 
    DATE_ID, 
    TO_DATE(DATE_ID::STRING, 'YYYYMMDD'), 
    YEAR(TO_DATE(DATE_ID::STRING, 'YYYYMMDD')), 
    MONTH(TO_DATE(DATE_ID::STRING, 'YYYYMMDD')), 
    DAY(TO_DATE(DATE_ID::STRING, 'YYYYMMDD')), 
    DAYNAME(TO_DATE(DATE_ID::STRING, 'YYYYMMDD'))
FROM fact_sales
WHERE DATE_ID NOT IN (SELECT DATE_ID FROM dim_date);

-- Validating that all dates in fact_sales exist in dim_date
SELECT DISTINCT DATE_ID 
FROM fact_sales
WHERE DATE_ID NOT IN (SELECT DATE_ID FROM dim_date);

-- Getting min and max transaction dates from fact_sales
SELECT MIN(DATE_ID), MAX(DATE_ID)
FROM fact_sales;

-- Validating that fact_sales has no orphaned DATE_IDs
SELECT COUNT(*) FROM fact_sales f
LEFT JOIN dim_date d ON f.date_id = d.date_id
WHERE d.date_id IS NULL;


-- Total Revenue by Product Category
SELECT 
    p.product_category, 
    SUM(f.total_sales_amount) AS total_revenue
FROM fact_sales f
JOIN dim_product p ON f.product_id = p.product_id
GROUP BY p.product_category
ORDER BY total_revenue DESC;

-- Revenue by Weekday
SELECT 
    s.store_name,
    d.weekday,
    SUM(DISTINCT f.total_sales_amount) AS total_revenue
FROM fact_sales f
JOIN dim_date d ON f.date_id = d.date_id
JOIN dim_store s ON f.store_id = s.store_id
GROUP BY s.store_name, d.weekday
ORDER BY total_revenue DESC;

-- High-value customers
SELECT 
    c.customer_id, 
    COUNT(f.transaction_id) AS total_purchases,
    SUM(f.total_sales_amount) AS total_spent
FROM fact_sales f
JOIN dim_customer c ON f.customer_id = c.customer_id
GROUP BY c.customer_id
ORDER BY total_spent DESC
LIMIT 10;



SHOW TABLES IN COFFEE_SHOP_DW.PUBLIC;






