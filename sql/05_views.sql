-- 05_views.sql : headline reports saved as views. Revenue = orders in paid, shipped, delivered.
CREATE OR REPLACE VIEW v_monthly_revenue AS
SELECT DATE(DATE_FORMAT(order_date, '%Y-%m-01')) AS month, COUNT(*) AS orders, SUM(total_amount) AS revenue
FROM orders WHERE status IN ('paid','shipped','delivered')
GROUP BY DATE(DATE_FORMAT(order_date, '%Y-%m-01'));

CREATE OR REPLACE VIEW v_top_products AS
SELECT p.product_id, p.name, SUM(i.quantity) AS units_sold, SUM(i.quantity * i.unit_price) AS revenue
FROM order_items i JOIN orders o ON o.order_id = i.order_id JOIN products p ON p.product_id = i.product_id
WHERE o.status IN ('paid','shipped','delivered') GROUP BY p.product_id, p.name;

CREATE OR REPLACE VIEW v_top_customers AS
SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS customer, COUNT(*) AS orders, SUM(o.total_amount) AS spend
FROM orders o JOIN customers c ON c.customer_id = o.customer_id
WHERE o.status IN ('paid','shipped','delivered') GROUP BY c.customer_id, c.first_name, c.last_name;

CREATE OR REPLACE VIEW v_low_stock AS
SELECT product_id, name, stock_quantity, reorder_level FROM products
WHERE stock_quantity <= reorder_level AND is_active;
