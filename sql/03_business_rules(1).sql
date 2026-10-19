-- 03_business_rules.sql : business rules enforced inside the database (MySQL 8: triggers + stored procedures)
-- Lifecycle: cart -> placed -> paid -> shipped -> delivered ; refunds from paid/shipped/delivered ;
--            cancel from cart/placed.  "Revenue" in all reports = orders in paid, shipped, delivered.
-- Run with the mysql client (it understands DELIMITER) or MySQL Workbench "Run SQL Script".
-- Every rule violation is raised with SQLSTATE '45000' and a readable message, which the web app shows to the user.

DELIMITER $$

-- ---------- Rule 1: only valid order-status transitions ----------
CREATE TRIGGER trg_orders_status_guard BEFORE UPDATE ON orders FOR EACH ROW
BEGIN
  DECLARE v_msg VARCHAR(128);
  IF NEW.status <> OLD.status THEN
    IF NOT (   (OLD.status = 'cart'      AND NEW.status IN ('placed','cancelled'))
            OR (OLD.status = 'placed'    AND NEW.status IN ('paid','cancelled'))
            OR (OLD.status = 'paid'      AND NEW.status IN ('shipped','refunded'))
            OR (OLD.status = 'shipped'   AND NEW.status IN ('delivered','refunded'))
            OR (OLD.status = 'delivered' AND NEW.status = 'refunded')) THEN
      SET v_msg = CONCAT('Invalid order status change: ', OLD.status, ' -> ', NEW.status, ' (order ', OLD.order_id, ')');
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
  END IF;
END$$

-- ---------- Rule 2: stock is reduced when an order becomes paid, restored on refund ----------
CREATE TRIGGER trg_orders_stock AFTER UPDATE ON orders FOR EACH ROW
BEGIN
  DECLARE v_short INT DEFAULT NULL;
  DECLARE v_msg VARCHAR(128) DEFAULT NULL;
  IF NEW.status = 'paid' AND OLD.status <> 'paid' THEN
    SET v_short = (SELECT i.product_id FROM order_items i JOIN products p ON p.product_id = i.product_id
                    WHERE i.order_id = NEW.order_id AND p.stock_quantity < i.quantity LIMIT 1);
    IF v_short IS NOT NULL THEN
      SET v_msg = CONCAT('Insufficient stock for product ', v_short, ' when paying order ', NEW.order_id);
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
    UPDATE products p JOIN order_items i ON i.product_id = p.product_id
       SET p.stock_quantity = p.stock_quantity - i.quantity
     WHERE i.order_id = NEW.order_id;
  ELSEIF NEW.status = 'refunded' AND OLD.status IN ('paid','shipped','delivered') THEN
    UPDATE products p JOIN order_items i ON i.product_id = p.product_id
       SET p.stock_quantity = p.stock_quantity + i.quantity
     WHERE i.order_id = NEW.order_id;
  END IF;
END$$

-- ---------- Rule 3: audit trail (who changed what, before and after) ----------
-- MySQL triggers cannot be generic over tables, so each audited table has its own small triggers.
-- changed_by is the database login that made the change (USER() without the host part).
CREATE TRIGGER trg_orders_audit_ins AFTER INSERT ON orders FOR EACH ROW
BEGIN
  INSERT INTO audit_log (table_name, record_id, action, old_value, new_value, changed_by)
  VALUES ('orders', NEW.order_id, 'INSERT', NULL,
          JSON_OBJECT('order_id', NEW.order_id, 'customer_id', NEW.customer_id, 'address_id', NEW.address_id,
                      'order_date', NEW.order_date, 'status', NEW.status, 'total_amount', NEW.total_amount),
          SUBSTRING_INDEX(USER(), '@', 1));
END$$

CREATE TRIGGER trg_orders_audit_upd AFTER UPDATE ON orders FOR EACH ROW FOLLOWS trg_orders_stock
BEGIN
  INSERT INTO audit_log (table_name, record_id, action, old_value, new_value, changed_by)
  VALUES ('orders', NEW.order_id, 'UPDATE',
          JSON_OBJECT('order_id', OLD.order_id, 'customer_id', OLD.customer_id, 'address_id', OLD.address_id,
                      'order_date', OLD.order_date, 'status', OLD.status, 'total_amount', OLD.total_amount),
          JSON_OBJECT('order_id', NEW.order_id, 'customer_id', NEW.customer_id, 'address_id', NEW.address_id,
                      'order_date', NEW.order_date, 'status', NEW.status, 'total_amount', NEW.total_amount),
          SUBSTRING_INDEX(USER(), '@', 1));
END$$

CREATE TRIGGER trg_orders_audit_del AFTER DELETE ON orders FOR EACH ROW
BEGIN
  INSERT INTO audit_log (table_name, record_id, action, old_value, new_value, changed_by)
  VALUES ('orders', OLD.order_id, 'DELETE',
          JSON_OBJECT('order_id', OLD.order_id, 'customer_id', OLD.customer_id, 'status', OLD.status, 'total_amount', OLD.total_amount),
          NULL, SUBSTRING_INDEX(USER(), '@', 1));
END$$

CREATE TRIGGER trg_payments_audit_ins AFTER INSERT ON payments FOR EACH ROW
BEGIN
  INSERT INTO audit_log (table_name, record_id, action, old_value, new_value, changed_by)
  VALUES ('payments', NEW.payment_id, 'INSERT', NULL,
          JSON_OBJECT('payment_id', NEW.payment_id, 'order_id', NEW.order_id, 'method', NEW.method,
                      'status', NEW.status, 'amount', NEW.amount),
          SUBSTRING_INDEX(USER(), '@', 1));
END$$

CREATE TRIGGER trg_payments_audit_upd AFTER UPDATE ON payments FOR EACH ROW
BEGIN
  INSERT INTO audit_log (table_name, record_id, action, old_value, new_value, changed_by)
  VALUES ('payments', NEW.payment_id, 'UPDATE',
          JSON_OBJECT('payment_id', OLD.payment_id, 'order_id', OLD.order_id, 'method', OLD.method,
                      'status', OLD.status, 'amount', OLD.amount),
          JSON_OBJECT('payment_id', NEW.payment_id, 'order_id', NEW.order_id, 'method', NEW.method,
                      'status', NEW.status, 'amount', NEW.amount),
          SUBSTRING_INDEX(USER(), '@', 1));
END$$

-- products: only price or stock changes are audited
CREATE TRIGGER trg_products_audit_upd AFTER UPDATE ON products FOR EACH ROW
BEGIN
  IF NOT (OLD.price <=> NEW.price AND OLD.stock_quantity <=> NEW.stock_quantity) THEN
    INSERT INTO audit_log (table_name, record_id, action, old_value, new_value, changed_by)
    VALUES ('products', NEW.product_id, 'UPDATE',
            JSON_OBJECT('product_id', OLD.product_id, 'price', OLD.price, 'stock_quantity', OLD.stock_quantity),
            JSON_OBJECT('product_id', NEW.product_id, 'price', NEW.price, 'stock_quantity', NEW.stock_quantity),
            SUBSTRING_INDEX(USER(), '@', 1));
  END IF;
END$$

-- ---------- Procedure: place_order ----------
-- p_items is a JSON array of lines, for example '[{"product_id":8,"quantity":2},{"product_id":10,"quantity":1}]'.
-- Blocks unknown or inactive products, bad quantities, duplicate products, a foreign address, and quantities above stock.
-- Copies the current price into each line and stores the total. Runs as ONE transaction (all or nothing).
-- Stock is only reserved when the order is paid (Rule 2), and re-checked then, so two shoppers cannot oversell.
CREATE PROCEDURE place_order(IN p_customer_id INT, IN p_address_id INT, IN p_items TEXT, OUT p_order_id INT)
BEGIN
  DECLARE v_msg VARCHAR(128) DEFAULT NULL;
  DECLARE v_n INT DEFAULT 0;
  DECLARE v_order_id INT DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  SET p_order_id = NULL;

  IF p_items IS NULL OR NOT JSON_VALID(p_items) OR JSON_TYPE(p_items) <> 'ARRAY' OR JSON_LENGTH(p_items) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order needs at least one item, and one quantity per product';
  END IF;

  SET v_n = (SELECT COUNT(*) FROM JSON_TABLE(p_items, '$[*]' COLUMNS (
               product_id INT PATH '$.product_id', quantity INT PATH '$.quantity')) jt
              WHERE jt.product_id IS NULL OR jt.quantity IS NULL OR jt.quantity <= 0);
  IF v_n > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Every item needs a product and a quantity above zero';
  END IF;

  SET v_n = (SELECT COUNT(*) - COUNT(DISTINCT jt.product_id) FROM JSON_TABLE(p_items, '$[*]' COLUMNS (
               product_id INT PATH '$.product_id')) jt);
  IF v_n > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The same product appears twice in one order';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM addresses WHERE address_id = p_address_id AND customer_id = p_customer_id) THEN
    SET v_msg = CONCAT('Address ', IFNULL(p_address_id, 'NULL'), ' does not belong to customer ', IFNULL(p_customer_id, 'NULL'));
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;

  SET v_msg = (SELECT CONCAT('Product ', jt.product_id, ' does not exist')
                 FROM JSON_TABLE(p_items, '$[*]' COLUMNS (product_id INT PATH '$.product_id')) jt
                 LEFT JOIN products p ON p.product_id = jt.product_id
                WHERE p.product_id IS NULL LIMIT 1);
  IF v_msg IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg; END IF;

  SET v_msg = (SELECT CONCAT('Product ', p.product_id, ' is not available')
                 FROM JSON_TABLE(p_items, '$[*]' COLUMNS (product_id INT PATH '$.product_id')) jt
                 JOIN products p ON p.product_id = jt.product_id
                WHERE NOT p.is_active LIMIT 1);
  IF v_msg IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg; END IF;

  SET v_msg = (SELECT CONCAT('Insufficient stock for product ', p.product_id, ': requested ', jt.quantity, ', available ', p.stock_quantity)
                 FROM JSON_TABLE(p_items, '$[*]' COLUMNS (product_id INT PATH '$.product_id', quantity INT PATH '$.quantity')) jt
                 JOIN products p ON p.product_id = jt.product_id
                WHERE jt.quantity > p.stock_quantity LIMIT 1);
  IF v_msg IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg; END IF;

  START TRANSACTION;
  INSERT INTO orders (customer_id, address_id, status, total_amount) VALUES (p_customer_id, p_address_id, 'placed', 0);
  SET v_order_id = LAST_INSERT_ID();
  INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  SELECT v_order_id, jt.product_id, jt.quantity, p.price
    FROM JSON_TABLE(p_items, '$[*]' COLUMNS (product_id INT PATH '$.product_id', quantity INT PATH '$.quantity')) jt
    JOIN products p ON p.product_id = jt.product_id;
  UPDATE orders SET total_amount = (SELECT SUM(quantity * unit_price) FROM order_items WHERE order_id = v_order_id)
   WHERE order_id = v_order_id;
  COMMIT;
  SET p_order_id = v_order_id;
END$$

-- Same procedure for the web app: returns the new order id as a result set, so no session variables are needed
-- (connection pools such as Cloudflare Hyperdrive do not promise to keep session variables between statements).
CREATE PROCEDURE place_order_rs(IN p_customer_id INT, IN p_address_id INT, IN p_items TEXT)
BEGIN
  DECLARE v_order_id INT DEFAULT NULL;
  CALL place_order(p_customer_id, p_address_id, p_items, v_order_id);
  SELECT v_order_id AS order_id;
END$$

-- ---------- Procedure: pay_order ----------
-- Success -> payment completed, order paid (stock reduced by trigger). Failure -> payment failed, order stays placed (retry allowed).
CREATE PROCEDURE pay_order(IN p_order_id INT, IN p_method VARCHAR(20), IN p_success TINYINT)
BEGIN
  DECLARE v_status VARCHAR(12) DEFAULT NULL;
  DECLARE v_total DECIMAL(12,2) DEFAULT NULL;
  DECLARE v_msg VARCHAR(128) DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;
  SELECT status, total_amount INTO v_status, v_total FROM orders WHERE order_id = p_order_id FOR UPDATE;
  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order does not exist';
  END IF;
  IF v_status <> 'placed' THEN
    SET v_msg = CONCAT('Only placed orders can be paid (order ', p_order_id, ' is ', v_status, ')');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  IF p_success <> 0 THEN
    INSERT INTO payments (order_id, method, status, amount, paid_at) VALUES (p_order_id, p_method, 'completed', v_total, NOW());
    UPDATE orders SET status = 'paid' WHERE order_id = p_order_id;
  ELSE
    INSERT INTO payments (order_id, method, status, amount) VALUES (p_order_id, p_method, 'failed', v_total);
  END IF;
  COMMIT;
END$$

-- ---------- Procedure: cancel_order (cart or placed only) ----------
CREATE PROCEDURE cancel_order(IN p_order_id INT)
BEGIN
  DECLARE v_status VARCHAR(12) DEFAULT NULL;
  DECLARE v_msg VARCHAR(128) DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;
  SELECT status INTO v_status FROM orders WHERE order_id = p_order_id FOR UPDATE;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order does not exist'; END IF;
  IF v_status = 'cancelled' THEN
    SET v_msg = CONCAT('Order ', p_order_id, ' is already cancelled');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  UPDATE orders SET status = 'cancelled' WHERE order_id = p_order_id;     -- guard trigger rejects other invalid cases
  UPDATE payments SET status = 'failed' WHERE order_id = p_order_id AND status = 'pending';
  COMMIT;
END$$

-- ---------- Procedure: refund_order (paid, shipped or delivered) ----------
CREATE PROCEDURE refund_order(IN p_order_id INT)
BEGIN
  DECLARE v_status VARCHAR(12) DEFAULT NULL;
  DECLARE v_msg VARCHAR(128) DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;
  SELECT status INTO v_status FROM orders WHERE order_id = p_order_id FOR UPDATE;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order does not exist'; END IF;
  IF v_status = 'refunded' THEN
    SET v_msg = CONCAT('Order ', p_order_id, ' is already refunded');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
  UPDATE orders SET status = 'refunded' WHERE order_id = p_order_id;      -- guard trigger rejects other invalid cases; stock restored by trigger
  UPDATE payments SET status = 'refunded' WHERE order_id = p_order_id AND status = 'completed';
  COMMIT;
END$$

DELIMITER ;
