Setup Instructions:

1\. Prerequisites Ensure you have access to Snowflake and a database
setup. You need:

A Snowflake Account A warehouse and database (Created in SQL) The
ability to run SQL scripts in Snowflake Worksheets

2\. Creating Database & Schema Run the following SQL commands in
Snowflake to set up the database and schema:

CREATE DATABASE COFFEE_SHOP_DW; USE DATABASE COFFEE_SHOP_DW; USE SCHEMA
PUBLIC;

3\. Creating a Snowflake Stage To load CSV files into Snowflake, create
a file stage:

CREATE OR REPLACE STAGE coffee_shop_stage; After creating the stage,
list all files:

LIST \@coffee_shop_stage;

4\. Creating File Format A file format is required for loading CSV
files:

CREATE OR REPLACE FILE FORMAT csv_format TYPE = \'CSV\' SKIP_HEADER = 1
FIELD_OPTIONALLY_ENCLOSED_BY = \'\"\' ERROR_ON_COLUMN_COUNT_MISMATCH =
FALSE;

5\. Creating Tables Run the SQL scripts in SQL_Scripts/schema.sql to
create tables:

CREATE OR REPLACE TABLE dim_customer ( customer_id BIGINT PRIMARY KEY,
first_name TEXT, last_name TEXT, email TEXT, phone_number TEXT,
loyalty_member_yn TEXT, birth_date DATE, gender TEXT ); Repeat this for
all dimension and fact tables.

6\. Loading Data into Tables Upload your CSV files to Snowflake using
the COPY INTO command:

COPY INTO dim_customer FROM \@coffee_shop_stage/customer.csv FILE_FORMAT
= csv_format; Repeat this for all tables.

7\. Running Data Integrity Checks Ensure all data is correctly loaded:

SELECT COUNT(\*) FROM fact_sales;

To verify missing date values, run:

SELECT DISTINCT DATE_ID FROM fact_sales WHERE DATE_ID NOT IN (SELECT
DATE_ID FROM dim_date);

Check for missing keys using:

SELECT COUNT(\*) FROM fact_sales f LEFT JOIN dim_date d ON f.date_id =
d.date_id WHERE d.date_id IS NULL;

8\. Running Analytical Queries Now that the data is loaded, run
analytical queries to generate insights.

8.1 Revenue by Product Category:

SELECT p.product_category, SUM(f.total_sales_amount) AS total_revenue
FROM fact_sales f JOIN dim_product p ON f.product_id = p.product_id
GROUP BY p.product_category ORDER BY total_revenue DESC;

8.2 Best Selling Products:

SELECT p.product, SUM(f.quantity_sold) AS total_sold FROM fact_sales f
JOIN dim_product p ON f.product_id = p.product_id GROUP BY p.product
ORDER BY total_sold DESC LIMIT 5;

8.3 Sales Performance by Store:

SELECT s.store_name, SUM(f.total_sales_amount) AS total_revenue FROM
fact_sales f JOIN dim_store s ON f.store_id = s.store_id GROUP BY
s.store_name ORDER BY total_revenue DESC;
