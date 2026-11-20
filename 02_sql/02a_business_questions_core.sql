/* ============================================================
   02_business_questions_core.sql
   
   Core business questions across sales, customers, delivery,
   reviews, and sellers. See 02_business_questions_advanced.sql
   for window-function and CTE-based follow-up questions.
   ============================================================ */


-- ------------------------------------------------------------
-- Sales
-- ------------------------------------------------------------

-- Total revenue by month and year
SELECT
    ROUND(SUM(oi.price), 2) AS total_revenue,
    MONTH(o.order_purchase_timestamp) AS month,
    YEAR(o.order_purchase_timestamp) AS year
FROM order_items_clean AS oi
INNER JOIN orders_clean AS o
    ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY MONTH(o.order_purchase_timestamp), YEAR(o.order_purchase_timestamp)
ORDER BY YEAR(o.order_purchase_timestamp), MONTH(o.order_purchase_timestamp);


-- Top 10 most-sold product categories by unit count
SELECT TOP 10
    ct.product_category_name_english AS category_name_english,
    COUNT(*) AS count_by_category
FROM order_items_clean AS oi
INNER JOIN orders_clean AS o
    ON oi.order_id = o.order_id
INNER JOIN products_clean AS p
    ON oi.product_id = p.product_id
INNER JOIN category_translation AS ct
    ON p.product_category_name = ct.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY p.product_category_name, ct.product_category_name_english
ORDER BY COUNT(*) DESC;


-- ------------------------------------------------------------
-- Customers
-- ------------------------------------------------------------

-- Repeat customers vs one-time buyers: how many orders does each customer place?
SELECT
    count_id AS number_of_orders,
    COUNT(*) AS number_of_customers
FROM (
    SELECT c.customer_unique_id, COUNT(*) AS count_id
    FROM orders_clean AS oc
    INNER JOIN customers_clean AS c
        ON oc.customer_id = c.customer_id
    WHERE oc.order_status = 'delivered'
    GROUP BY c.customer_unique_id
) AS t
GROUP BY count_id
ORDER BY count_id;


-- ------------------------------------------------------------
-- Delivery
-- ------------------------------------------------------------

-- Sanity check: unavailable orders should not have a delivery date
SELECT COUNT(*)
FROM orders_clean
WHERE order_status = 'unavailable'
  AND order_delivered_customer_date IS NOT NULL;


-- Average delay for orders delivered later than estimated
SELECT
    AVG(delay_delivery_date) AS avg_delivery_delay_days,
    COUNT(*) AS total_delayed_orders
FROM (
    SELECT DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) AS delay_delivery_date
    FROM orders_clean
    WHERE order_status = 'delivered'
) AS t
WHERE delay_delivery_date > 0 AND delay_delivery_date IS NOT NULL;


-- Average days early for orders delivered ahead of estimate
SELECT
    ABS(AVG(delay_delivery_date)) AS avg_delivery_advanced_days,
    COUNT(*) AS total_advanced_orders
FROM (
    SELECT DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) AS delay_delivery_date
    FROM orders_clean
    WHERE order_status = 'delivered'
) AS t
WHERE delay_delivery_date < 0 AND delay_delivery_date IS NOT NULL;


-- Orders delivered exactly on the estimated date
SELECT
    AVG(delay_delivery_date) AS no_delay,
    COUNT(*) AS total_orders
FROM (
    SELECT DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) AS delay_delivery_date
    FROM orders_clean
    WHERE order_status = 'delivered'
) AS t
WHERE delay_delivery_date = 0 AND delay_delivery_date IS NOT NULL;


-- ------------------------------------------------------------
-- Reviews
-- ------------------------------------------------------------

-- Review score distribution
SELECT
    review_score,
    COUNT(*) AS total_reviews
FROM reviews_clean
GROUP BY review_score
ORDER BY review_score;


-- Overall average rating
SELECT ROUND(AVG(CAST(review_score AS FLOAT)), 2) AS avg_rating
FROM reviews_clean;


-- ------------------------------------------------------------
-- Sellers
-- ------------------------------------------------------------

-- Top 20 sellers by revenue
SELECT TOP 20
    s.seller_id,
    ROUND(SUM(oi.price), 2) AS total_revenue
FROM sellers_clean AS s
INNER JOIN order_items_clean AS oi
    ON s.seller_id = oi.seller_id
INNER JOIN orders_clean AS o
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id
ORDER BY SUM(oi.price) DESC;


-- Top 20 sellers by highest average freight value
SELECT TOP 20
    s.seller_id,
    ROUND(AVG(oi.freight_value), 2) AS avg_freight_value
FROM sellers_clean AS s
INNER JOIN order_items_clean AS oi
    ON s.seller_id = oi.seller_id
INNER JOIN orders_clean AS o
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id
ORDER BY AVG(oi.freight_value) DESC;


-- Top 20 sellers by lowest average freight value
SELECT TOP 20
    s.seller_id,
    ROUND(AVG(oi.freight_value), 2) AS avg_freight_value
FROM sellers_clean AS s
INNER JOIN order_items_clean AS oi
    ON s.seller_id = oi.seller_id
INNER JOIN orders_clean AS o
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id
ORDER BY AVG(oi.freight_value);


-- Top 20 sellers by highest average review rating (min 15 orders for a fair sample)
SELECT TOP 20
    s.seller_id,
    AVG(CAST(r.review_score AS FLOAT)) AS avg_review
FROM order_items_clean AS oi
INNER JOIN reviews_clean AS r
    ON oi.order_id = r.order_id
INNER JOIN orders_clean AS o
    ON o.order_id = oi.order_id
INNER JOIN sellers_clean AS s
    ON s.seller_id = oi.seller_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id
HAVING COUNT(*) >= 15
ORDER BY AVG(CAST(r.review_score AS FLOAT)) DESC;


-- Top 20 sellers by lowest average review rating (min 15 orders for a fair sample)
SELECT TOP 20
    s.seller_id,
    AVG(CAST(r.review_score AS FLOAT)) AS avg_review
FROM order_items_clean AS oi
INNER JOIN reviews_clean AS r
    ON oi.order_id = r.order_id
INNER JOIN orders_clean AS o
    ON o.order_id = oi.order_id
INNER JOIN sellers_clean AS s
    ON s.seller_id = oi.seller_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id
HAVING COUNT(*) >= 15
ORDER BY AVG(CAST(r.review_score AS FLOAT));
