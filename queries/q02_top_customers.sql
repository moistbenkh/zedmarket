-- Q2. Which customers have made the most purchases?
-- Concepts: JOIN, COUNT, SUM, GROUP BY, HAVING, ORDER BY.
-- Interpretation: The most active buyers place 8-9 orders each, but Faith Mumba has the highest spend (about K35k), so frequency and value are not the same ranking.
SELECT CONCAT(c.first_name, ' ', c.last_name) AS customer, COUNT(*) AS orders, SUM(o.total_amount) AS total_spent
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.status IN ('paid','shipped','delivered')
GROUP BY c.customer_id, c.first_name, c.last_name
HAVING COUNT(*) >= 2
ORDER BY orders DESC, total_spent DESC
LIMIT 10;
