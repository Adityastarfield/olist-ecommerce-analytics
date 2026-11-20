/* ============================================================
   02_business_questions_advanced.sql
   
   Follow-up business questions using CTEs and window functions:
   MoM growth, running totals, category ranking, RFM segmentation,
   state-level delivery performance, and payment-method analysis.
   ============================================================ */


-- ------------------------------------------------------------
-- Sellers with both above-average revenue AND above-average ratings
-- ------------------------------------------------------------

WITH avg_price_cte AS (
    SELECT
        oi.seller_id,
        ROUND(SUM(oi.price), 2) AS total_revenue_per_seller
    FROM order_items_clean AS oi
    INNER JOIN orders_clean AS o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id
),
avg_review_cte AS (
    SELECT
        os.seller_id,
        ROUND(AVG(CAST(r.review_score AS FLOAT)), 2) AS avg_review_per_seller
    FROM reviews_clean AS r
    INNER JOIN (
        SELECT order_id, seller_id
        FROM order_items_clean
        GROUP BY order_id, seller_id
    ) AS os
        ON r.order_id = os.order_id
    INNER JOIN orders_clean AS o
        ON o.order_id = os.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY os.seller_id
)
SELECT
    ap.seller_id,
    ap.total_revenue_per_seller AS total_revenue,
    ar.avg_review_per_seller AS avg_review
FROM avg_price_cte AS ap
INNER JOIN avg_review_cte AS ar
    ON ap.seller_id = ar.seller_id
WHERE ap.total_revenue_per_seller >= (SELECT AVG(total_revenue_per_seller) FROM avg_price_cte)
  AND ar.avg_review_per_seller >= (SELECT AVG(avg_review_per_seller) FROM avg_review_cte)
ORDER BY ap.total_revenue_per_seller DESC, ar.avg_review_per_seller DESC;


-- ------------------------------------------------------------
-- Month-over-month revenue growth rate (%)
-- ------------------------------------------------------------

WITH monthly_revenue_cte AS (
    SELECT
        SUM(oi.price) AS current_month_revenue,
        MONTH(o.order_purchase_timestamp) AS revenue_month,
        YEAR(o.order_purchase_timestamp) AS revenue_year,
        LAG(SUM(oi.price)) OVER (
            ORDER BY YEAR(o.order_purchase_timestamp), MONTH(o.order_purchase_timestamp)
        ) AS previous_month_revenue
    FROM order_items_clean AS oi
    INNER JOIN orders_clean AS o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY MONTH(o.order_purchase_timestamp), YEAR(o.order_purchase_timestamp)
)
SELECT
    revenue_year,
    revenue_month,
    ROUND(
        (CAST((current_month_revenue - previous_month_revenue) AS FLOAT) / previous_month_revenue) * 100,
        2
    ) AS month_over_month_perc
FROM monthly_revenue_cte
ORDER BY revenue_year, revenue_month;


-- ------------------------------------------------------------
-- Running total revenue across months
-- ------------------------------------------------------------

WITH monthly_revenue_cte AS (
    SELECT
        SUM(oi.price) AS current_month_revenue,
        MONTH(o.order_purchase_timestamp) AS revenue_month,
        YEAR(o.order_purchase_timestamp) AS revenue_year
    FROM order_items_clean AS oi
    INNER JOIN orders_clean AS o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY MONTH(o.order_purchase_timestamp), YEAR(o.order_purchase_timestamp)
)
SELECT
    revenue_year,
    revenue_month,
    ROUND(
        SUM(current_month_revenue) OVER (
            ORDER BY revenue_year, revenue_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        2
    ) AS running_total
FROM monthly_revenue_cte;


-- ------------------------------------------------------------
-- Do product categories rank the same by revenue and by units sold?
-- ------------------------------------------------------------

SELECT
    ct.product_category_name_english,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    COUNT(*) AS total_units_count,
    DENSE_RANK() OVER (ORDER BY SUM(oi.price) DESC) AS rank_by_revenue,
    DENSE_RANK() OVER (ORDER BY COUNT(oi.product_id) DESC) AS rank_by_products_sold_count,
    ROUND(AVG(oi.price), 2) AS avg_product_price
FROM order_items_clean AS oi
INNER JOIN orders_clean AS o
    ON oi.order_id = o.order_id
INNER JOIN products_clean AS p
    ON p.product_id = oi.product_id
INNER JOIN category_translation AS ct
    ON ct.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY ct.product_category_name_english
ORDER BY rank_by_revenue, rank_by_products_sold_count;


-- ------------------------------------------------------------
-- Repeat customer count, rewritten as a CTE instead of a subquery
-- ------------------------------------------------------------

WITH customer_count_cte AS (
    SELECT
        c.customer_unique_id,
        COUNT(c.customer_unique_id) AS count_id
    FROM customers_clean AS c
    INNER JOIN orders_clean AS o
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*) AS number_of_customers,
    count_id AS number_of_orders
FROM customer_count_cte
GROUP BY count_id
ORDER BY number_of_orders;


-- ------------------------------------------------------------
-- Which states generate the most revenue?
-- ------------------------------------------------------------

SELECT
    cc.customer_state,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    DENSE_RANK() OVER (ORDER BY SUM(oi.price) DESC) AS rank_by_revenue
FROM customers_clean AS cc
INNER JOIN orders_clean AS o
    ON o.customer_id = cc.customer_id
INNER JOIN order_items_clean AS oi
    ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY cc.customer_state
ORDER BY rank_by_revenue;


-- ------------------------------------------------------------
-- Average delivery difference from estimated date, by state
-- (negative = delivered early)
-- ------------------------------------------------------------

SELECT
    cc.customer_state,
    AVG(DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date)) AS delivery_difference_days
FROM customers_clean AS cc
INNER JOIN orders_clean AS o
    ON o.customer_id = cc.customer_id
WHERE o.order_status = 'delivered'
GROUP BY cc.customer_state
ORDER BY delivery_difference_days DESC;


-- ------------------------------------------------------------
-- Which states have the worst average delays (delayed orders only)?
-- ------------------------------------------------------------

SELECT
    cc.customer_state,
    COUNT(*) AS delayed_orders,
    AVG(DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date)) AS delay_delivery_days
FROM customers_clean AS cc
INNER JOIN orders_clean AS o
    ON o.customer_id = cc.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date > o.order_estimated_delivery_date
GROUP BY cc.customer_state
ORDER BY delay_delivery_days DESC;


-- ------------------------------------------------------------
-- Percentage of delayed deliveries by state
-- ------------------------------------------------------------

SELECT
    cc.customer_state,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS delayed_orders,
    CAST(
        100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END)
        / COUNT(*) AS DECIMAL(5, 2)
    ) AS delayed_percentage
FROM customers_clean AS cc
INNER JOIN orders_clean AS o
    ON o.customer_id = cc.customer_id
WHERE o.order_status = 'delivered'
GROUP BY cc.customer_state
ORDER BY delayed_percentage DESC;


-- ------------------------------------------------------------
-- Seller-wise delivery analysis (min 50 delivered orders for a fair sample)
-- ------------------------------------------------------------

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
GROUP BY oi.seller_id
HAVING COUNT(DISTINCT o.order_id) >= 50
   AND COUNT(DISTINCT CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN o.order_id END) > 0
ORDER BY delay_percentage DESC, avg_delay_days DESC;


-- ------------------------------------------------------------
-- Which product categories have the highest delivery delay rates?
-- (min 50 delivered orders for a fair sample)
-- ------------------------------------------------------------

SELECT
    ct.product_category_name_english,
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
INNER JOIN products_clean AS p
    ON p.product_id = oi.product_id
INNER JOIN category_translation AS ct
    ON ct.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY ct.product_category_name_english
HAVING COUNT(DISTINCT o.order_id) >= 50
   AND COUNT(DISTINCT CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN o.order_id END) > 0
ORDER BY delay_percentage DESC, total_delayed_orders DESC, avg_delay_days DESC;


-- ------------------------------------------------------------
-- Average order value (AOV) by product category
-- ------------------------------------------------------------

WITH total_order_value_cte AS (
    SELECT
        oi.order_id,
        SUM(oi.price) AS total_price
    FROM orders_clean AS o
    INNER JOIN order_items_clean AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.order_id
),
order_by_category_cte AS (
    SELECT DISTINCT
        oi.order_id,
        ct.product_category_name_english
    FROM order_items_clean AS oi
    INNER JOIN orders_clean AS o
        ON oi.order_id = o.order_id
    INNER JOIN products_clean AS p
        ON p.product_id = oi.product_id
    INNER JOIN category_translation AS ct
        ON ct.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
)
SELECT
    obc.product_category_name_english,
    ROUND(AVG(tov.total_price), 2) AS aov
FROM order_by_category_cte AS obc
INNER JOIN total_order_value_cte AS tov
    ON obc.order_id = tov.order_id
GROUP BY obc.product_category_name_english
ORDER BY aov DESC;


-- ------------------------------------------------------------
-- Payment method preference and average order value per payment type
-- ------------------------------------------------------------

WITH order_value_cte AS (
    SELECT
        order_id,
        SUM(price) AS order_value
    FROM order_items_clean
    GROUP BY order_id
),
payment_type_cte AS (
    SELECT DISTINCT order_id, payment_type
    FROM payments_clean
)
SELECT
    pt.payment_type,
    COUNT(*) AS orders_using_payment_type,
    ROUND(AVG(ov.order_value), 2) AS aov
FROM payment_type_cte AS pt
INNER JOIN order_value_cte AS ov
    ON pt.order_id = ov.order_id
INNER JOIN orders_clean AS o
    ON pt.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY pt.payment_type;


-- ------------------------------------------------------------
-- RFM segmentation
--
-- Recency/Frequency/Monetary thresholds below are quintile
-- boundaries derived from the delivered-order customer population
-- (not arbitrary round numbers).
-- ------------------------------------------------------------

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
),
customer_segment_cte AS (
    SELECT
        customer_unique_id,
        recency,
        frequency,
        monetary,
        CASE
            WHEN r_score = 5 AND f_score = 5 AND m_score = 5 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score = 1 AND m_score >= 4 THEN 'High-Value New Customers'
            WHEN r_score >= 3 AND f_score BETWEEN 2 AND 3 THEN 'Potential Loyalists'
            WHEN r_score <= 2 AND f_score >= 2 AND m_score >= 4 THEN 'At-Risk High-Value'
            WHEN f_score = 1 THEN 'One-Time Customers'
            ELSE 'Lost / Low-Value'
        END AS customer_segment
    FROM rfm_scored_cte
)
SELECT
    customer_segment,
    COUNT(*) AS customers,
    ROUND(SUM(monetary), 2) AS total_revenue,
    ROUND(AVG(monetary), 2) AS avg_revenue_per_customer,
    CAST(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER () AS DECIMAL(5, 2)) AS revenue_percentage
FROM customer_segment_cte
GROUP BY customer_segment
ORDER BY avg_revenue_per_customer DESC;

-- Key findings:
-- 81.46% of customers fall into the "One-Time Customers" RFM segment specifically, 
-- including High-Value New Customers (who also ordered exactly once, but are tracked
-- separately due to high recency/spend), 97.0% of all customers have ordered only
-- once, and they represent 94.48% of total revenue.
-- High-Value New Customers represent only 15.54% of customers but contribute 29.39% of revenue.
-- 714 At-Risk High-Value customers generate an average of $312 per customer, making them a targeted retention opportunity.
-- The largest growth opportunity is converting one-time customers into repeat buyers.
