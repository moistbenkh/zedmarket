-- 04_business_rules_test.sql : proves the business rules. Creates a self-test procedure, runs it, drops it.
-- Prints one row per check: PASS or FAIL. NOTE: the procedures manage their own transactions, so this test
-- leaves two small test orders behind. build.sh rebuilds the database afterwards; if you ran it by hand, rerun build.sh.
DELIMITER $$
DROP PROCEDURE IF EXISTS sp_selftest_rules$$
CREATE PROCEDURE sp_selftest_rules()
BEGIN
  DECLARE c INT; DECLARE a INT; DECLARE o1 INT; DECLARE o2 INT; DECLARE o4 INT; DECLARE s0 INT; DECLARE s1 INT; DECLARE n INT;
  DECLARE v_status VARCHAR(12);

  DROP TEMPORARY TABLE IF EXISTS tr;
  CREATE TEMPORARY TABLE tr (n INT AUTO_INCREMENT PRIMARY KEY, result VARCHAR(5), test VARCHAR(100), detail VARCHAR(200));

  SET c = (SELECT a2.customer_id FROM addresses a2 JOIN customers cu ON cu.customer_id = a2.customer_id
            WHERE cu.role = 'customer' AND a2.is_default LIMIT 1);
  SET a = (SELECT a2.address_id FROM addresses a2 JOIN customers cu ON cu.customer_id = a2.customer_id
            WHERE cu.role = 'customer' AND a2.is_default LIMIT 1);

  -- 1. Happy path: place + pay
  SET s0 = (SELECT stock_quantity FROM products WHERE product_id = 8);
  CALL place_order(c, a, '[{"product_id":8,"quantity":2},{"product_id":10,"quantity":1}]', o1);
  SET v_status = (SELECT status FROM orders WHERE order_id = o1);
  IF v_status = 'placed' AND (SELECT total_amount FROM orders WHERE order_id = o1) = 2 * 650 + 220 THEN
    INSERT INTO tr (result, test, detail) VALUES ('PASS', '1a order placed', 'total = sum of lines, unit prices copied');
  ELSE
    INSERT INTO tr (result, test, detail) VALUES ('FAIL', '1a order placed', CONCAT('status ', IFNULL(v_status, 'NULL')));
  END IF;
  CALL pay_order(o1, 'mobile_money', 1);
  SET v_status = (SELECT status FROM orders WHERE order_id = o1);
  SET s1 = (SELECT stock_quantity FROM products WHERE product_id = 8);
  IF v_status = 'paid' AND s1 = s0 - 2 THEN
    INSERT INTO tr (result, test, detail) VALUES ('PASS', '1b payment completed, stock reduced', CONCAT('stock ', s0, ' -> ', s1));
  ELSE
    INSERT INTO tr (result, test, detail) VALUES ('FAIL', '1b payment completed, stock reduced', CONCAT('status ', v_status, ', stock ', s0, ' -> ', s1));
  END IF;

  -- 2. Out of stock is blocked (product 19 has stock 2)
  BEGIN
    DECLARE v_m TEXT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_m = MESSAGE_TEXT;
      INSERT INTO tr (result, test, detail) VALUES ('PASS', '2 oversell blocked', v_m);
    END;
    CALL place_order(c, a, '[{"product_id":19,"quantity":3}]', o4);
    INSERT INTO tr (result, test, detail) VALUES ('FAIL', '2 oversell blocked', 'oversell was allowed');
  END;

  -- 3. Failed payment keeps the order placed and stock untouched
  SET s0 = (SELECT stock_quantity FROM products WHERE product_id = 11);
  CALL place_order(c, a, '[{"product_id":11,"quantity":2}]', o2);
  CALL pay_order(o2, 'card', 0);
  SET v_status = (SELECT status FROM orders WHERE order_id = o2);
  SET s1 = (SELECT stock_quantity FROM products WHERE product_id = 11);
  IF v_status = 'placed' AND s1 = s0 AND EXISTS (SELECT 1 FROM payments WHERE order_id = o2 AND status = 'failed') THEN
    INSERT INTO tr (result, test, detail) VALUES ('PASS', '3 failed payment', 'recorded as failed, order still placed, stock unchanged');
  ELSE
    INSERT INTO tr (result, test, detail) VALUES ('FAIL', '3 failed payment', CONCAT('status ', v_status));
  END IF;

  -- 4. Invalid transition: placed -> delivered is rejected
  BEGIN
    DECLARE v_m TEXT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_m = MESSAGE_TEXT;
      INSERT INTO tr (result, test, detail) VALUES ('PASS', '4 invalid status jump blocked', v_m);
    END;
    UPDATE orders SET status = 'delivered' WHERE order_id = o2;
    INSERT INTO tr (result, test, detail) VALUES ('FAIL', '4 invalid status jump blocked', 'placed -> delivered was allowed');
  END;

  -- 5. Cancel a placed order; a cancelled order cannot be paid
  CALL cancel_order(o2);
  SET v_status = (SELECT status FROM orders WHERE order_id = o2);
  IF v_status <> 'cancelled' THEN
    INSERT INTO tr (result, test, detail) VALUES ('FAIL', '5a cancel', CONCAT('status ', v_status));
  END IF;
  BEGIN
    DECLARE v_m TEXT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_m = MESSAGE_TEXT;
      INSERT INTO tr (result, test, detail) VALUES ('PASS', '5 cancelled order cannot be paid', v_m);
    END;
    CALL pay_order(o2, 'card', 1);
    INSERT INTO tr (result, test, detail) VALUES ('FAIL', '5 cancelled order cannot be paid', 'cancelled order was paid');
  END;

  -- 6. Refund a paid order: status, payment and stock all reversed
  SET s0 = (SELECT stock_quantity FROM products WHERE product_id = 8);
  CALL refund_order(o1);
  SET s1 = (SELECT stock_quantity FROM products WHERE product_id = 8);
  IF (SELECT status FROM orders WHERE order_id = o1) = 'refunded'
     AND EXISTS (SELECT 1 FROM payments WHERE order_id = o1 AND status = 'refunded')
     AND s1 = s0 + 2 THEN
    INSERT INTO tr (result, test, detail) VALUES ('PASS', '6 refund', CONCAT('order and payment refunded, stock ', s0, ' -> ', s1));
  ELSE
    INSERT INTO tr (result, test, detail) VALUES ('FAIL', '6 refund', CONCAT('stock ', s0, ' -> ', s1));
  END IF;

  -- 7. A refunded order cannot be refunded again
  BEGIN
    DECLARE v_m TEXT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_m = MESSAGE_TEXT;
      INSERT INTO tr (result, test, detail) VALUES ('PASS', '7 double refund blocked', v_m);
    END;
    CALL refund_order(o1);
    INSERT INTO tr (result, test, detail) VALUES ('FAIL', '7 double refund blocked', 'second refund was allowed');
  END;

  -- 8. Audit trail captured the activity
  SET n = (SELECT COUNT(*) FROM audit_log WHERE table_name IN ('orders', 'payments', 'products'));
  IF n >= 10 THEN
    INSERT INTO tr (result, test, detail) VALUES ('PASS', '8 audit trail', CONCAT('audit_log holds ', n, ' rows'));
  ELSE
    INSERT INTO tr (result, test, detail) VALUES ('FAIL', '8 audit trail', CONCAT('only ', n, ' audit rows'));
  END IF;

  SELECT result, test, detail FROM tr ORDER BY tr.n;
END$$
DELIMITER ;
CALL sp_selftest_rules();
DROP PROCEDURE sp_selftest_rules;
