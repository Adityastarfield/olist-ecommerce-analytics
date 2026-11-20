/* ============================================================
   01_check_and_convert_datetimes.sql
   
   Purpose: all date/timestamp columns arrive from the CSV import
   as VARCHAR. This checks their current type and converts the
   ones used in date-logic queries (delivery timing, review timing,
   MoM revenue trends) to DATETIME.
   
   Note: converting these to datetime in pandas first does not
   carry through the CSV round-trip (CSV has no dtype metadata),
   so this conversion has to happen here regardless of what was
   already done in 01_data_cleaning/02_cleaning.ipynb.
   ============================================================ */


-- ------------------------------------------------------------
-- Check current data types before converting
-- ------------------------------------------------------------

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'orders_clean';

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'reviews_clean';

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'order_items_clean';


-- ------------------------------------------------------------
-- Convert orders_clean date columns
-- ------------------------------------------------------------

ALTER TABLE orders_clean
ALTER COLUMN order_purchase_timestamp DATETIME NULL;

ALTER TABLE orders_clean
ALTER COLUMN order_approved_at DATETIME NULL;

ALTER TABLE orders_clean
ALTER COLUMN order_delivered_carrier_date DATETIME NULL;

ALTER TABLE orders_clean
ALTER COLUMN order_delivered_customer_date DATETIME NULL;

ALTER TABLE orders_clean
ALTER COLUMN order_estimated_delivery_date DATETIME NULL;


-- ------------------------------------------------------------
-- Convert reviews_clean date columns
-- ------------------------------------------------------------

ALTER TABLE reviews_clean
ALTER COLUMN review_creation_date DATETIME NULL;

ALTER TABLE reviews_clean
ALTER COLUMN review_answer_timestamp DATETIME NULL;


-- ------------------------------------------------------------
-- Convert order_items_clean date column
-- ------------------------------------------------------------

ALTER TABLE order_items_clean
ALTER COLUMN shipping_limit_date DATETIME NULL;


-- ------------------------------------------------------------
-- Verify conversion
-- ------------------------------------------------------------

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'orders_clean'
  AND COLUMN_NAME IN (
      'order_purchase_timestamp', 'order_approved_at',
      'order_delivered_carrier_date', 'order_delivered_customer_date',
      'order_estimated_delivery_date'
  );

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'reviews_clean'
  AND COLUMN_NAME IN ('review_creation_date', 'review_answer_timestamp');

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'order_items_clean'
  AND COLUMN_NAME = 'shipping_limit_date';
