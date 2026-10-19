-- Q14. Top 3 customers by spend within each city (customer's default address).
-- Concepts: DENSE_RANK window function with PARTITION BY.
-- Interpretation: Faith Mumba (Lusaka), Mutinta Musonda (Kitwe) and Grace Kunda (Choma) are the top spenders in their cities; DENSE_RANK handles ties.
SELECT * FROM (
  SELECT a.city, CONCAT(c.first_name, ' ', c.last_name) AS customer, SUM(o.total_amount) AS spend,
         DENSE_RANK() OVER (PARTITION BY a.city ORDER BY SUM(o.total_amount) DESC) AS city_rank
  FROM customers c
  JOIN addresses a ON a.customer_id = c.customer_id AND a.is_default
  JOIN orders o ON o.customer_id = c.customer_id AND o.status IN ('paid','shipped','delivered')
  GROUP BY a.city, c.customer_id, c.first_name, c.last_name) ranked
WHERE city_rank <= 3
ORDER BY city, city_rank;
