-- Q10. Average order value per month.
-- Concepts: AVG, GROUP BY, DATE_FORMAT.
-- Interpretation: Average order value is mostly K1,000-K2,500, with spikes in months that include laptop or flagship phone orders.
SELECT DATE_FORMAT(order_date, '%Y-%m') AS month, COUNT(*) AS orders, ROUND(AVG(total_amount), 2) AS avg_order_value
FROM orders WHERE status IN ('paid','shipped','delivered')
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY month;
