-- Q7. Which products are at or below their reorder level?
-- Concepts: WHERE, ORDER BY.
-- Interpretation: Four products are below reorder level; the Blender 600W has the largest shortfall and should be restocked first.
SELECT name, stock_quantity, reorder_level, reorder_level - stock_quantity AS shortfall
FROM products
WHERE stock_quantity <= reorder_level AND is_active
ORDER BY shortfall DESC;
