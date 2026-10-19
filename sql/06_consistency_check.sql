-- 06_consistency_check.sql : every check should return 0 problems
SELECT 'order total <> sum of lines' AS check_name, COUNT(*) AS problems FROM (
  SELECT o.order_id FROM orders o JOIN order_items i ON i.order_id = o.order_id
  GROUP BY o.order_id, o.total_amount HAVING o.total_amount <> SUM(i.quantity * i.unit_price)) x
UNION ALL
SELECT 'order without items', COUNT(*) FROM orders o WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id)
UNION ALL
SELECT 'payment amount <> order total', COUNT(*) FROM payments p JOIN orders o ON o.order_id = p.order_id WHERE p.amount <> o.total_amount
UNION ALL
SELECT 'order address not owned by customer', COUNT(*) FROM orders o JOIN addresses a ON a.address_id = o.address_id WHERE a.customer_id <> o.customer_id
UNION ALL
SELECT 'review for product never bought', COUNT(*) FROM reviews r WHERE NOT EXISTS (
  SELECT 1 FROM orders o JOIN order_items i ON i.order_id = o.order_id WHERE o.customer_id = r.customer_id AND i.product_id = r.product_id);
