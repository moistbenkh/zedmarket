-- Q6. Payment method share and failure rate.
-- Concepts: GROUP BY, CASE, aggregate percentages, window function over an aggregate.
-- Interpretation: Mobile money carries about 60% of payment attempts, and cash on delivery has by far the highest failure rate (28.6%).
SELECT method,
       COUNT(*) AS attempts,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct,
       SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed,
       ROUND(100.0 * SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) / COUNT(*), 1) AS failure_rate_pct
FROM payments
GROUP BY method
ORDER BY attempts DESC;
