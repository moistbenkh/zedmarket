-- Q11. Products with above-average sales but a below-3.5 average rating.
-- Concepts: subquery in WHERE, JOIN, derived tables, CTE.
-- Interpretation: Blender 600W, Formal Shirt and Chitenge Wrap Dress sell well but rate below 3.5, so they are quality-review candidates (note the small review counts).
WITH sales AS (
  SELECT i.product_id, SUM(i.quantity) AS units
  FROM order_items i JOIN orders o ON o.order_id = i.order_id
  WHERE o.status IN ('paid','shipped','delivered') GROUP BY i.product_id)
SELECT p.name, s.units, ROUND(r.avg_rating, 2) AS avg_rating, r.reviews
FROM sales s
JOIN products p ON p.product_id = s.product_id
JOIN (SELECT product_id, AVG(rating) AS avg_rating, COUNT(*) AS reviews FROM reviews GROUP BY product_id) r
     ON r.product_id = s.product_id
WHERE s.units > (SELECT AVG(units) FROM sales)
  AND r.avg_rating < 3.5
ORDER BY s.units DESC;
