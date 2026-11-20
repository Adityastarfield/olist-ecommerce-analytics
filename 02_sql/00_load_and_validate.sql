/* ============================================================
   00_load_and_validate.sql
   
   Purpose: quick visual check of every loaded table.
   
   Run this after loading all 9 cleaned tables via
   01_data_cleaning/03_load_to_sql.ipynb
   ============================================================ */


SELECT * FROM customers_clean;
SELECT * FROM geolocation_clean;
SELECT * FROM order_items_clean;
SELECT * FROM payments_clean;
SELECT * FROM reviews_clean;
SELECT * FROM orders_clean;
SELECT * FROM products_clean;
SELECT * FROM sellers_clean;
SELECT * FROM category_translation;


