-- Q4. Revenue by category, rolled up to parent category.
-- Concepts: recursive CTE (category tree), JOIN, GROUP BY ... WITH ROLLUP.
-- Interpretation: Electronics earns about 75% of revenue (Laptops and Phones lead); the ROLLUP rows give each parent total and the last row is the grand total.
-- (In the result a NULL category marks a parent subtotal; NULL in both columns marks the grand total.)
WITH RECURSIVE tree AS (
  SELECT category_id, name, name AS parent_name FROM categories WHERE parent_category_id IS NULL
  UNION ALL
  SELECT c.category_id, c.name, t.parent_name FROM categories c JOIN tree t ON c.parent_category_id = t.category_id)
SELECT t.parent_name, t.name AS category, SUM(i.quantity * i.unit_price) AS revenue
FROM tree t
JOIN products p ON p.category_id = t.category_id
JOIN order_items i ON i.product_id = p.product_id
JOIN orders o ON o.order_id = i.order_id AND o.status IN ('paid','shipped','delivered')
WHERE t.name <> t.parent_name
GROUP BY t.parent_name, t.name WITH ROLLUP
ORDER BY GROUPING(t.parent_name), t.parent_name, GROUPING(t.name), revenue DESC;
