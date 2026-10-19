-- Q1. Which products have the highest sales?
-- Concepts: JOIN, SUM, GROUP BY, ORDER BY. Revenue = orders in paid/shipped/delivered.
-- Interpretation: Phones and laptops dominate revenue: 5 of the top 6 products are high-ticket electronics, while earbuds and power banks lead on units.
SELECT p.name, SUM(i.quantity) AS units_sold, SUM(i.quantity * i.unit_price) AS revenue
FROM order_items i
JOIN orders   o ON o.order_id   = i.order_id
JOIN products p ON p.product_id = i.product_id
WHERE o.status IN ('paid','shipped','delivered')
GROUP BY p.name
ORDER BY revenue DESC
LIMIT 10;
