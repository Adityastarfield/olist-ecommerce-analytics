/* ============================================================
   03_views.sql
   
   Fact and dimension views used by the Power BI model. Each
   view is followed by a GO — CREATE VIEW must be the only
   statement in its batch, so this is required for the whole
   file to run as a single script rather than one statement
   at a time.
   
   vw_category_revenue, vw_monthly_revenue, and vw_state_revenue
   were built during initial modeling but are not used in the
   final Power BI model (superseded by direct measures on the
   fact/dimension tables) and have been removed from this file.
   ============================================================ */


-- ------------------------------------------------------------
-- vw_fact_order_items
-- ------------------------------------------------------------

CREATE VIEW vw_fact_order_items AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    c.customer_unique_id,
    oi.seller_id,
    o.order_purchase_timestamp,
    oi.price,
    oi.freight_value
FROM order_items_clean AS oi
INNER JOIN orders_clean AS o
    ON oi.order_id = o.order_id
INNER JOIN customers_clean AS c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered';
GO


-- ------------------------------------------------------------
-- vw_fact_orders
--
-- One row per delivered order, with the most recent review score
-- attached (an order can technically receive more than one review
-- row in the source data; ROW_NUMBER + rn = 1 keeps exactly one).
-- ------------------------------------------------------------

CREATE VIEW vw_fact_orders AS
SELECT
    o.order_id,
    c.customer_unique_id,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    r.review_score
FROM orders_clean AS o
INNER JOIN customers_clean AS c
    ON o.customer_id = c.customer_id
LEFT JOIN (
    SELECT order_id, review_score
    FROM (
        SELECT
            order_id,
            review_score,
            ROW_NUMBER() OVER (
                PARTITION BY order_id
                ORDER BY review_creation_date DESC, review_id DESC
            ) AS rn
        FROM reviews_clean
    ) AS x
    WHERE rn = 1
) AS r
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered';
GO


-- ------------------------------------------------------------
-- vw_dim_customer
--
-- One row per customer_unique_id. A customer can appear with
-- more than one customer_id/order over time; this keeps the
-- state associated with their most recent order.
-- ------------------------------------------------------------

CREATE VIEW vw_dim_customer AS
SELECT customer_unique_id, customer_state
FROM (
    SELECT
        c.customer_unique_id,
        c.customer_state,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp DESC
        ) AS rn
    FROM customers_clean AS c
    INNER JOIN orders_clean AS o
        ON c.customer_id = o.customer_id
) AS x
WHERE rn = 1;
GO


-- ------------------------------------------------------------
-- vw_dim_product
-- ------------------------------------------------------------

CREATE VIEW vw_dim_product AS
SELECT
    p.product_id,
    ct.product_category_name_english AS product_category
FROM products_clean AS p
LEFT JOIN category_translation AS ct
    ON p.product_category_name = ct.product_category_name;
GO


-- ------------------------------------------------------------
-- vw_dim_seller
-- ------------------------------------------------------------

CREATE VIEW vw_dim_seller AS
SELECT DISTINCT
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM sellers_clean;
GO


-- ------------------------------------------------------------
-- vw_fact_payments
-- ------------------------------------------------------------

CREATE VIEW vw_fact_payments AS
SELECT
    p.order_id,
    p.payment_sequential,
    p.payment_type,
    p.payment_installments,
    p.payment_value,
    c.customer_unique_id,
    o.order_purchase_timestamp
FROM payments_clean AS p
INNER JOIN orders_clean AS o
    ON p.order_id = o.order_id
INNER JOIN customers_clean AS c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered';
GO


-- ------------------------------------------------------------
-- vw_rfm_segments
--
-- Same RFM logic as 02_business_questions_advanced.sql, exposed
-- as a view for the Power BI model. See that file for the
-- quintile derivation behind the recency/frequency/monetary
-- thresholds and the segment-level findings.
-- ------------------------------------------------------------

CREATE VIEW vw_rfm_segments AS
WITH max_date_cte AS (
    SELECT MAX(order_purchase_timestamp) AS max_date
    FROM orders_clean
    WHERE order_status = 'delivered'
),
rfm_cte AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS frequency,
        DATEDIFF(DAY, MAX(o.order_purchase_timestamp), (SELECT max_date FROM max_date_cte)) AS recency,
        ROUND(SUM(oi.price), 2) AS monetary
    FROM customers_clean AS c
    INNER JOIN orders_clean AS o
        ON c.customer_id = o.customer_id
    INNER JOIN order_items_clean AS oi
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scored_cte AS (
    SELECT
        customer_unique_id,
        recency,
        frequency,
        monetary,
        CASE
            WHEN recency <= 92 THEN 5
            WHEN recency <= 177 THEN 4
            WHEN recency <= 268 THEN 3
            WHEN recency <= 382 THEN 2
            ELSE 1
        END AS r_score,
        CASE
            WHEN frequency = 1 THEN 1
            WHEN frequency = 2 THEN 2
            WHEN frequency = 3 THEN 3
            WHEN frequency = 4 THEN 4
            ELSE 5
        END AS f_score,
        CASE
            WHEN monetary <= 39.90 THEN 1
            WHEN monetary <= 69.90 THEN 2
            WHEN monetary <= 109.90 THEN 3
            WHEN monetary <= 179.90 THEN 4
            ELSE 5
        END AS m_score
    FROM rfm_cte
)
SELECT
    customer_unique_id,
    recency,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    CASE
        WHEN r_score = 5 AND f_score = 5 AND m_score = 5 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score = 1 AND m_score >= 4 THEN 'High-Value New Customers'
        WHEN r_score >= 3 AND f_score BETWEEN 2 AND 3 THEN 'Potential Loyalists'
        WHEN r_score <= 2 AND f_score >= 2 AND m_score >= 4 THEN 'At-Risk High-Value'
        WHEN f_score = 1 THEN 'One-Time Customers'
        ELSE 'Lost / Low-Value'
    END AS customer_segment
FROM rfm_scored_cte;
GO


-- ------------------------------------------------------------
-- vw_seller_delivery_performance
--
-- Seller-level delivery stats. Consumed alongside a >= 15
-- delivered-order filter at the state grain in Power BI, and a
-- >= 50 delivered-order filter at the seller grain in
-- 02_business_questions_advanced.sql, to avoid small-sample
-- distortion (see the AM-state case study in
-- 04_validate_views.sql).
-- ------------------------------------------------------------

CREATE VIEW vw_seller_delivery_performance AS
SELECT
    oi.seller_id,
    COUNT(DISTINCT o.order_id) AS total_delivered_orders,
    COUNT(DISTINCT CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN o.order_id END) AS total_delayed_orders,
    AVG(CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN DATEDIFF(DAY, o.order_estimated_delivery_date, o.order_delivered_customer_date)
    END) AS avg_delay_days,
    CAST(
        100.0 * COUNT(DISTINCT CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN o.order_id END)
        / COUNT(DISTINCT o.order_id) AS DECIMAL(5, 2)
    ) AS delay_percentage
FROM order_items_clean AS oi
INNER JOIN orders_clean AS o
    ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY oi.seller_id;
GO
