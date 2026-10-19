-- Q12. Order status funnel.
-- Concepts: GROUP BY, COUNT, CASE for lifecycle ordering, window total.
-- Interpretation: About 84% of orders reach delivered, 8.8% are cancelled and 3.8% refunded; the in-progress stages are small because most data is historical.
SELECT status, COUNT(*) AS orders, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders
FROM orders
GROUP BY status
ORDER BY CASE status WHEN 'cart' THEN 1 WHEN 'placed' THEN 2 WHEN 'paid' THEN 3 WHEN 'shipped' THEN 4
                     WHEN 'delivered' THEN 5 WHEN 'cancelled' THEN 6 ELSE 7 END;
