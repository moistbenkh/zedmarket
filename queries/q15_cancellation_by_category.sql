-- Q15. Cancellation rate by category (categories with at least 8 orders).
-- Concepts: JOIN, COUNT DISTINCT, conditional aggregate, HAVING.
-- Interpretation: Pantry Staples has the highest cancellation rate (14.6%), followed by Laptops and Menswear (12.5%); Appliances has none.
SELECT c.name AS category,
       COUNT(DISTINCT o.order_id) AS orders,
       COUNT(DISTINCT CASE WHEN o.status = 'cancelled' THEN o.order_id END) AS cancelled,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN o.status = 'cancelled' THEN o.order_id END) / COUNT(DISTINCT o.order_id), 1) AS cancel_rate_pct
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
JOIN products p ON p.product_id = i.product_id
JOIN categories c ON c.category_id = p.category_id
WHERE o.status <> 'cart'
GROUP BY c.name
HAVING COUNT(DISTINCT o.order_id) >= 8
ORDER BY cancel_rate_pct DESC, category;
