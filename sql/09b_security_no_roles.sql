-- 09b_security_no_roles.sql : FALLBACK for 09_security.sql, for hosts that do not let the admin account CREATE ROLE.
-- Same privileges, granted directly to the three login users. scripts/build.sh uses this automatically if 09_security.sql fails.
-- Run as the admin account (on Aiven: avnadmin) after build.sh. Safe to re-run.
-- The three passwords are placeholders: scripts/build.sh replaces __APP_PW__, __ANALYST_PW__ and __ADMIN_PW__
-- from the APP_DB_PASSWORD, ANALYST_DB_PASSWORD and ADMIN_DB_PASSWORD environment variables. If you run this file
-- by hand (for example in MySQL Workbench), replace those three words first. Never commit real passwords.
-- Database name used below: ecommerce

-- 1. Masked view: no names, emails or phones. Analysts see this instead of the raw tables.
--    (A view runs with its definer's rights, so analysts can read it without any access to `customers`.)
CREATE OR REPLACE VIEW v_customer_orders_masked AS
SELECT c.customer_id,
       CONCAT(LEFT(c.first_name, 1), '***')                       AS first_name_masked,
       CONCAT('*****@', SUBSTRING_INDEX(c.email, '@', -1))       AS email_masked,
       CONCAT('xxx-xxx-', RIGHT(COALESCE(c.phone, ''), 3))       AS phone_masked,
       a.city, a.province,
       o.order_id, o.order_date, o.status, o.total_amount
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
LEFT JOIN addresses a ON a.address_id = o.address_id;

-- 2. Users (dropped first so the script can be re-run)
DROP USER IF EXISTS 'app_user'@'%', 'analyst_user'@'%', 'admin_user'@'%';
CREATE USER 'app_user'@'%'     IDENTIFIED BY '__APP_PW__';
CREATE USER 'analyst_user'@'%' IDENTIFIED BY '__ANALYST_PW__';
CREATE USER 'admin_user'@'%'   IDENTIFIED BY '__ADMIN_PW__';

-- Application user (the web app): read everything it shows, change order status, run the order procedures. No INSERT/DELETE, no DDL.
GRANT SELECT ON ecommerce.* TO 'app_user'@'%';
GRANT UPDATE (status) ON ecommerce.orders TO 'app_user'@'%';
GRANT EXECUTE ON PROCEDURE ecommerce.place_order    TO 'app_user'@'%';
GRANT EXECUTE ON PROCEDURE ecommerce.place_order_rs TO 'app_user'@'%';
GRANT EXECUTE ON PROCEDURE ecommerce.pay_order      TO 'app_user'@'%';
GRANT EXECUTE ON PROCEDURE ecommerce.cancel_order   TO 'app_user'@'%';
GRANT EXECUTE ON PROCEDURE ecommerce.refund_order   TO 'app_user'@'%';

-- Analyst user: views and non-personal tables only, no writes
GRANT SELECT ON ecommerce.v_monthly_revenue        TO 'analyst_user'@'%';
GRANT SELECT ON ecommerce.v_top_products           TO 'analyst_user'@'%';
GRANT SELECT ON ecommerce.v_low_stock              TO 'analyst_user'@'%';
GRANT SELECT ON ecommerce.v_customer_orders_masked TO 'analyst_user'@'%';
GRANT SELECT ON ecommerce.categories  TO 'analyst_user'@'%';
GRANT SELECT ON ecommerce.products    TO 'analyst_user'@'%';
GRANT SELECT ON ecommerce.order_items TO 'analyst_user'@'%';
GRANT SELECT ON ecommerce.payments    TO 'analyst_user'@'%';
GRANT SELECT ON ecommerce.reviews     TO 'analyst_user'@'%';

-- Admin user: full data access including the audit log, but no DROP/ALTER/CREATE
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON ecommerce.* TO 'admin_user'@'%';
