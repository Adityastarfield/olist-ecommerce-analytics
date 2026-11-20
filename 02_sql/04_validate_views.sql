/* ============================================================
   04_validate_views.sql
   
   Purpose: row-count, distinct-key, and orphan-key validation
   for every fact/dimension view. Run this after creating the
   views in 03_views.sql.
   ============================================================ */

-- ------------------------------------------------------------
-- Section 1: vw_fact_orders validation
-- ------------------------------------------------------------

-- Row count should match distinct delivered order_id count exactly
-- (one row per delivered order, no fan-out)
SELECT COUNT(*) AS fact_rows
FROM vw_fact_orders;

SELECT COUNT(DISTINCT order_id) AS distinct_orders
FROM vw_fact_orders;

SELECT COUNT(DISTINCT order_id)
FROM orders_clean
WHERE order_status = 'delivered';


-- ------------------------------------------------------------
-- Section 2: vw_fact_order_items validation
-- ------------------------------------------------------------

-- Row count should match delivered order_items rows exactly
-- (confirms the customer join in the view doesn't fan out or drop rows)
SELECT COUNT(*) AS fact_rows
FROM vw_fact_order_items;

SELECT COUNT(*) AS distinct_order_items
FROM (
    SELECT DISTINCT order_id, order_item_id
    FROM vw_fact_order_items
) x;

SELECT COUNT(*) AS delivered_item_count
FROM order_items_clean oi
INNER JOIN orders_clean o ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered';


-- ------------------------------------------------------------
-- Section 3: vw_dim_customer validation
-- ------------------------------------------------------------

-- Confirm customer_unique_id never maps to more than one state
-- (would break the 1-row-per-customer assumption in the dimension)
SELECT customer_unique_id
FROM customers_clean
GROUP BY customer_unique_id
HAVING COUNT(DISTINCT customer_state) > 1;

SELECT COUNT(*) AS customer_dimension_rows
FROM vw_dim_customer;

SELECT COUNT(DISTINCT customer_unique_id) AS distinct_customers
FROM vw_dim_customer;

-- Should return zero rows: one row per customer_unique_id, no duplicates
SELECT
    customer_unique_id,
    COUNT(*) AS row_count
FROM vw_dim_customer
GROUP BY customer_unique_id
HAVING COUNT(*) > 1;


-- ------------------------------------------------------------
-- Section 4: vw_dim_product validation
-- ------------------------------------------------------------

-- Confirm category_translation has no duplicate category names
SELECT product_category_name, COUNT(*) AS cnt
FROM category_translation
GROUP BY product_category_name
HAVING COUNT(*) > 1;

SELECT COUNT(*) AS product_dimension_rows
FROM vw_dim_product;

SELECT COUNT(DISTINCT product_id) AS distinct_products
FROM vw_dim_product;

SELECT COUNT(*) AS products_without_category
FROM vw_dim_product
WHERE product_category IS NULL;

-- Known gap: products whose category name has no match in category_translation
-- (see 01_data_cleaning/01_eda.ipynb — a handful of category names, e.g.
-- pc_gamer, don't exist in the translation table)
SELECT COUNT(*) AS missing_translation
FROM products_clean p
LEFT JOIN category_translation ct
    ON p.product_category_name = ct.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND ct.product_category_name_english IS NULL;


-- ------------------------------------------------------------
-- Section 5: vw_dim_seller validation
-- ------------------------------------------------------------

SELECT seller_id, COUNT(DISTINCT seller_state) AS state_count
FROM sellers_clean
GROUP BY seller_id
HAVING COUNT(DISTINCT seller_state) > 1;

SELECT seller_id, COUNT(*) AS row_count
FROM sellers_clean
GROUP BY seller_id
HAVING COUNT(*) > 1;

SELECT COUNT(*) FROM vw_dim_seller;
SELECT COUNT(DISTINCT seller_id) FROM sellers_clean;


-- ------------------------------------------------------------
-- Section 6: vw_fact_payments validation
-- ------------------------------------------------------------

-- Confirm orders can have multiple payment rows (installments/split payments)
-- so this is expected, not a data quality issue
SELECT order_id, COUNT(*) AS payment_rows
FROM payments_clean
GROUP BY order_id
HAVING COUNT(*) > 1;

SELECT COUNT(*) FROM vw_fact_payments;
SELECT COUNT(DISTINCT order_id) FROM vw_fact_payments;


-- ------------------------------------------------------------
-- Section 7: vw_seller_delivery_performance — small-sample check
-- ------------------------------------------------------------

-- Confirm each seller appears exactly once in the performance view
SELECT seller_id, COUNT(*)
FROM vw_seller_delivery_performance
GROUP BY seller_id
HAVING COUNT(*) > 1;

-- AM state case study: a single seller with very few orders can dominate
-- a state-level average and make it look far worse than it really is.
-- This is why the Delivery & Operations dashboard page filters state-level
-- delivery metrics to states with >= 15 delivered orders.
SELECT seller_state, COUNT(*) AS order_count, AVG(avg_delay_days) AS avg_delay
FROM vw_seller_delivery_performance v
JOIN sellers_clean s ON v.seller_id = s.seller_id
WHERE s.seller_state = 'AM'
GROUP BY seller_state;

SELECT s.seller_state,
    SUM(v.total_delivered_orders) AS total_orders,
    SUM(v.total_delayed_orders) AS total_delayed,
    AVG(v.avg_delay_days) AS avg_delay_days_unweighted
FROM vw_seller_delivery_performance v
JOIN sellers_clean s ON v.seller_id = s.seller_id
WHERE s.seller_state = 'AM'
GROUP BY s.seller_state;


-- ------------------------------------------------------------
-- Section 8: revenue reconciliation
-- ------------------------------------------------------------

-- vw_fact_order_items total revenue should equal the raw source total
-- exactly. Confirmed match: 13,221,498.11 both sides.
SELECT SUM(oi.price) AS raw_total
FROM order_items_clean oi
INNER JOIN orders_clean o ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered';

SELECT SUM(price) AS view_total
FROM vw_fact_order_items;
