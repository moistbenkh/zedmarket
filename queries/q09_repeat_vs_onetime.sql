-- Q9. Repeat versus one-time customers.
-- Concepts: nested aggregation, GROUP BY, CASE.
-- Interpretation: Repeat customers (2+ orders) generate about 95% of revenue and spend roughly four times more per customer than one-time buyers.
SELECT CASE WHEN n_orders >= 2 THEN 'Repeat (2+ orders)' ELSE 'One-time' END AS segment,
       COUNT(*) AS customers, SUM(spend) AS revenue, ROUND(AVG(spend), 2) AS avg_spend_per_customer
FROM (SELECT customer_id, COUNT(*) AS n_orders, SUM(total_amount) AS spend
      FROM orders WHERE status IN ('paid','shipped','delivered')
      GROUP BY customer_id) per_customer
GROUP BY CASE WHEN n_orders >= 2 THEN 'Repeat (2+ orders)' ELSE 'One-time' END
ORDER BY customers DESC;
