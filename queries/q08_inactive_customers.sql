-- Q8. Customers with no order in the last 90 days (lapsed customers).
-- Reference date is fixed at 2026-10-18 so results are repeatable for the demo.
-- Concepts: subquery (NOT EXISTS), scalar subquery for last order date.
-- Interpretation: Many customers have no order in 90 days (some have never ordered); these are the targets for a win-back campaign.
SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS customer,
       (SELECT DATE(MAX(o.order_date)) FROM orders o WHERE o.customer_id = c.customer_id AND o.status <> 'cart') AS last_order
FROM customers c
WHERE c.role = 'customer'
  AND NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.customer_id = c.customer_id AND o.status <> 'cart'
                    AND o.order_date >= DATE '2026-10-18' - INTERVAL 90 DAY)
ORDER BY last_order IS NOT NULL, last_order;
