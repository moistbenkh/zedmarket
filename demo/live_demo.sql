-- live_demo.sql : the database half of the demo. Run with:   mysql ... ecommerce -t < demo/live_demo.sql   (use the admin account)
-- It changes data: run demo/reset_demo.sh afterwards.
SELECT '1. The system in numbers' AS step;
SELECT (SELECT COUNT(*) FROM categories) categories, (SELECT COUNT(*) FROM products) products, (SELECT COUNT(*) FROM customers) customers,
       (SELECT COUNT(*) FROM orders) orders, (SELECT COUNT(*) FROM order_items) order_lines, (SELECT COUNT(*) FROM payments) payments, (SELECT COUNT(*) FROM reviews) reviews;

SELECT '2. Place an order through the procedure (2 earbuds + 1 charger for customer 3)' AS step;
SELECT address_id INTO @addr FROM addresses WHERE customer_id = 3 AND is_default LIMIT 1;
SELECT stock_quantity AS earbuds_stock_before FROM products WHERE product_id = 8;
CALL place_order(3, @addr, '[{"product_id":8,"quantity":2},{"product_id":10,"quantity":1}]', @order);
SELECT order_id, status, total_amount FROM orders WHERE order_id = @order;
SELECT product_id, quantity, unit_price FROM order_items WHERE order_id = @order;

SELECT '3. Pay: the trigger reduces stock' AS step;
CALL pay_order(@order, 'mobile_money', 1);
SELECT status FROM orders WHERE order_id = @order;
SELECT stock_quantity AS earbuds_stock_after FROM products WHERE product_id = 8;

SELECT '4. A failed payment leaves the order placed and stock untouched' AS step;
CALL place_order(3, @addr, '[{"product_id":11,"quantity":1}]', @order2);
CALL pay_order(@order2, 'card', 0);
SELECT o.status AS order_status, p.status AS payment_status FROM orders o JOIN payments p ON p.order_id = o.order_id WHERE o.order_id = @order2;

SELECT '5. Overselling is blocked (product 19 has only 2 in stock)' AS step;
-- Expected: ERROR 1644 (45000): Insufficient stock for product 19 ... (the mysql client stops here; run the next steps separately if needed)
-- CALL place_order(3, @addr, '[{"product_id":19,"quantity":3}]', @bad);

SELECT '6. Refund: status, payment and stock are all reversed' AS step;
CALL refund_order(@order);
SELECT status FROM orders WHERE order_id = @order;
SELECT stock_quantity AS earbuds_stock_after_refund FROM products WHERE product_id = 8;

SELECT '7. The audit trail the triggers wrote' AS step;
SELECT audit_id, table_name, record_id, action, changed_by, changed_at FROM audit_log WHERE (table_name = 'orders' AND record_id IN (@order, @order2)) ORDER BY audit_id;

SELECT '8. A headline view, and the masked view an analyst sees' AS step;
SELECT * FROM v_top_products ORDER BY revenue DESC LIMIT 5;
SELECT first_name_masked, email_masked, phone_masked, city FROM v_customer_orders_masked LIMIT 3;
