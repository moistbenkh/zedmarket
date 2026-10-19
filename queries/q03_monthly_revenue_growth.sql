-- Q3. Monthly revenue and month-on-month growth.
-- Concepts: GROUP BY, window function LAG.
-- Interpretation: Revenue peaks in Nov-Dec (the seasonal peak) and again in Feb and Aug; the large swings reflect a small dataset where single big-ticket orders move the month.
WITH monthly AS (
  SELECT DATE(DATE_FORMAT(order_date, '%Y-%m-01')) AS month, SUM(total_amount) AS revenue
  FROM orders WHERE status IN ('paid','shipped','delivered')
  GROUP BY DATE(DATE_FORMAT(order_date, '%Y-%m-01')))
SELECT month, revenue,
       LAG(revenue) OVER (ORDER BY month) AS previous_month,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month)) / NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 1) AS growth_pct
FROM monthly
ORDER BY month;
