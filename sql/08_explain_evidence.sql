-- 08_explain_evidence.sql : EXPLAIN ANALYZE with and without the indexes (Stage 4 evidence). Needs MySQL 8.0.18+.
-- Run:  mysql ... ecommerce < 08_explain_evidence.sql > ../docs/explain_evidence.txt
-- IGNORE INDEX makes the optimiser behave as if the index did not exist, so no index has to be dropped
-- (MySQL will not drop an index that a foreign key depends on). FORCE INDEX shows the index being used.
-- With only 160 orders the optimiser may prefer a table scan even when an index exists; the "forced" plans show it is usable.
SELECT '##### BEFORE: indexes ignored' AS section;
SELECT '--- A: orders for one customer since January' AS query_label;
EXPLAIN ANALYZE SELECT COUNT(*), SUM(total_amount) FROM orders IGNORE INDEX (idx_orders_customer_date) WHERE customer_id = 10 AND order_date >= '2026-01-01';
SELECT '--- B: all lines for one product' AS query_label;
EXPLAIN ANALYZE SELECT SUM(quantity) FROM order_items IGNORE INDEX (idx_order_items_product) WHERE product_id = 8;
SELECT '--- C: products in one category' AS query_label;
EXPLAIN ANALYZE SELECT name FROM products IGNORE INDEX (idx_products_category) WHERE category_id = 7;

SELECT '##### AFTER: indexes present, default optimiser' AS section;
EXPLAIN ANALYZE SELECT COUNT(*), SUM(total_amount) FROM orders WHERE customer_id = 10 AND order_date >= '2026-01-01';
EXPLAIN ANALYZE SELECT SUM(quantity) FROM order_items WHERE product_id = 8;
EXPLAIN ANALYZE SELECT name FROM products WHERE category_id = 7;

SELECT '##### AFTER: indexes present, index forced (shows the index is usable)' AS section;
EXPLAIN ANALYZE SELECT COUNT(*), SUM(total_amount) FROM orders FORCE INDEX (idx_orders_customer_date) WHERE customer_id = 10 AND order_date >= '2026-01-01';
EXPLAIN ANALYZE SELECT SUM(quantity) FROM order_items FORCE INDEX (idx_order_items_product) WHERE product_id = 8;
EXPLAIN ANALYZE SELECT name FROM products FORCE INDEX (idx_products_category) WHERE category_id = 7;
