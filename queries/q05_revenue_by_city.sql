-- Q5. Revenue by delivery city.
-- Concepts: JOIN, GROUP BY, SUM, COUNT.
-- Interpretation: Kitwe, Choma, Ndola and Lusaka lead; Solwezi and Chingola contribute little, which points to where delivery or marketing effort could grow.
SELECT a.city, COUNT(*) AS orders, SUM(o.total_amount) AS revenue
FROM orders o JOIN addresses a ON a.address_id = o.address_id
WHERE o.status IN ('paid','shipped','delivered')
GROUP BY a.city
ORDER BY revenue DESC;
