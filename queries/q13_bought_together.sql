-- Q13. Products frequently bought together.
-- Concepts: self-join on order_items, GROUP BY, HAVING.
-- Interpretation: Wireless Earbuds with the USB-C Fast Charger is the most common pairing (4 orders), a candidate for a bundle offer.
SELECT p1.name AS product_a, p2.name AS product_b, COUNT(*) AS times_together
FROM order_items a
JOIN order_items b ON a.order_id = b.order_id AND a.product_id < b.product_id
JOIN products p1 ON p1.product_id = a.product_id
JOIN products p2 ON p2.product_id = b.product_id
GROUP BY p1.name, p2.name
HAVING COUNT(*) >= 2
ORDER BY times_together DESC, product_a
LIMIT 10;
