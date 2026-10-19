-- 07_bad_inserts_test.sql : each statement below MUST be rejected by a constraint. Prints PASS (rejected) or FAIL (accepted).
-- Runs after the seed on a fresh database; accepted rows would only appear if a constraint were missing (build.sh rebuilds afterwards).
DELIMITER $$
DROP PROCEDURE IF EXISTS sp_selftest_bad_inserts$$
CREATE PROCEDURE sp_selftest_bad_inserts()
BEGIN
  DROP TEMPORARY TABLE IF EXISTS tb;
  CREATE TEMPORARY TABLE tb (n INT AUTO_INCREMENT PRIMARY KEY, result VARCHAR(5), test VARCHAR(60), detail VARCHAR(200));

  BEGIN
    DECLARE v_m TEXT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_m = MESSAGE_TEXT; INSERT INTO tb (result, test, detail) VALUES ('PASS', 'negative price', v_m); END;
    INSERT INTO products (category_id, name, sku, price) VALUES (5, 'Bad price', 'SKU-BAD1', -10);
    INSERT INTO tb (result, test, detail) VALUES ('FAIL', 'negative price', 'accepted');
  END;
  BEGIN
    DECLARE v_m TEXT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_m = MESSAGE_TEXT; INSERT INTO tb (result, test, detail) VALUES ('PASS', 'rating of 7', v_m); END;
    INSERT INTO reviews (product_id, customer_id, rating) VALUES (1, 3, 7);
    INSERT INTO tb (result, test, detail) VALUES ('FAIL', 'rating of 7', 'accepted');
  END;
  BEGIN
    DECLARE v_m TEXT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_m = MESSAGE_TEXT; INSERT INTO tb (result, test, detail) VALUES ('PASS', 'duplicate email', v_m); END;
    INSERT INTO customers (first_name, last_name, email, password_hash) SELECT 'A', 'B', email, 'x' FROM customers LIMIT 1;
    INSERT INTO tb (result, test, detail) VALUES ('FAIL', 'duplicate email', 'accepted');
  END;
  BEGIN
    DECLARE v_m TEXT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_m = MESSAGE_TEXT; INSERT INTO tb (result, test, detail) VALUES ('PASS', 'invalid order status', v_m); END;
    INSERT INTO orders (customer_id, status) VALUES (3, 'teleported');
    INSERT INTO tb (result, test, detail) VALUES ('FAIL', 'invalid order status', 'accepted');
  END;
  BEGIN
    DECLARE v_m TEXT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_m = MESSAGE_TEXT; INSERT INTO tb (result, test, detail) VALUES ('PASS', 'invalid payment method', v_m); END;
    INSERT INTO payments (order_id, method, amount) VALUES (1, 'bitcoin', 10);
    INSERT INTO tb (result, test, detail) VALUES ('FAIL', 'invalid payment method', 'accepted');
  END;
  BEGIN
    DECLARE v_m TEXT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_m = MESSAGE_TEXT; INSERT INTO tb (result, test, detail) VALUES ('PASS', 'zero quantity', v_m); END;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES (1, 1, 0, 10);
    INSERT INTO tb (result, test, detail) VALUES ('FAIL', 'zero quantity', 'accepted');
  END;
  BEGIN
    DECLARE v_m TEXT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_m = MESSAGE_TEXT; INSERT INTO tb (result, test, detail) VALUES ('PASS', 'negative stock', v_m); END;
    INSERT INTO products (category_id, name, sku, price, stock_quantity) VALUES (5, 'Neg stock', 'SKU-BAD2', 10, -1);
    INSERT INTO tb (result, test, detail) VALUES ('FAIL', 'negative stock', 'accepted');
  END;
  BEGIN
    DECLARE v_m TEXT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_m = MESSAGE_TEXT; INSERT INTO tb (result, test, detail) VALUES ('PASS', 'missing customer (foreign key)', v_m); END;
    INSERT INTO orders (customer_id) VALUES (99999);
    INSERT INTO tb (result, test, detail) VALUES ('FAIL', 'missing customer (foreign key)', 'accepted');
  END;

  SELECT result, test, detail FROM tb ORDER BY tb.n;
END$$
DELIMITER ;
CALL sp_selftest_bad_inserts();
DROP PROCEDURE sp_selftest_bad_inserts;
