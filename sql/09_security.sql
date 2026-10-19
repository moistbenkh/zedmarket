-- 09_security.sql : least-privilege roles, login users and a masked analytics view (MySQL 8).
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

-- 2. Roles and users (dropped first so the script can be re-run)
DROP USER IF EXISTS 'app_user'@'%', 'analyst_user'@'%', 'admin_user'@'%';
DROP ROLE IF EXISTS 'app_role', 'analyst_role', 'admin_role';

CREATE ROLE 'app_role', 'analyst_role', 'admin_role';

-- Application role (the web app): read everything it shows, change order status, run the order procedures.
-- No INSERT/DELETE, no DDL, no write access to audit_log. Procedures, views and triggers run with the owner's rights,
-- so the app can place orders and the audit trail is still written, without the app holding those privileges itself.
GRANT SELECT ON ecommerce.* TO 'app_role';
GRANT UPDATE (status) ON ecommerce.orders TO 'app_role';
GRANT EXECUTE ON PROCEDURE ecommerce.place_order    TO 'app_role';
GRANT EXECUTE ON PROCEDURE ecommerce.place_order_rs TO 'app_role';
GRANT EXECUTE ON PROCEDURE ecommerce.pay_order      TO 'app_role';
GRANT EXECUTE ON PROCEDURE ecommerce.cancel_order   TO 'app_role';
GRANT EXECUTE ON PROCEDURE ecommerce.refund_order   TO 'app_role';

-- Analyst role: SELECT on views and non-personal tables only; no raw customer data, no writes
GRANT SELECT ON ecommerce.v_monthly_revenue        TO 'analyst_role';
GRANT SELECT ON ecommerce.v_top_products           TO 'analyst_role';
GRANT SELECT ON ecommerce.v_low_stock              TO 'analyst_role';
GRANT SELECT ON ecommerce.v_customer_orders_masked TO 'analyst_role';
GRANT SELECT ON ecommerce.categories  TO 'analyst_role';
GRANT SELECT ON ecommerce.products    TO 'analyst_role';
GRANT SELECT ON ecommerce.order_items TO 'analyst_role';
GRANT SELECT ON ecommerce.payments    TO 'analyst_role';
GRANT SELECT ON ecommerce.reviews     TO 'analyst_role';

-- Admin role: full data access including customers and the audit log, but no DROP/ALTER/CREATE
GRANT SELECT, INSERT, UPDATE, DELETE ON ecommerce.* TO 'admin_role';
GRANT EXECUTE ON ecommerce.* TO 'admin_role';

-- 3. Login users. MySQL stores these passwords as salted hashes (caching_sha2_password), never as plain text.
CREATE USER 'app_user'@'%'     IDENTIFIED BY '__APP_PW__';
CREATE USER 'analyst_user'@'%' IDENTIFIED BY '__ANALYST_PW__';
CREATE USER 'admin_user'@'%'   IDENTIFIED BY '__ADMIN_PW__';
GRANT 'app_role'     TO 'app_user'@'%';
GRANT 'analyst_role' TO 'analyst_user'@'%';
GRANT 'admin_role'   TO 'admin_user'@'%';
-- A role does nothing until it is active at login, so make each one the user's default role.
SET DEFAULT ROLE 'app_role'     TO 'app_user'@'%';
SET DEFAULT ROLE 'analyst_role' TO 'analyst_user'@'%';
SET DEFAULT ROLE 'admin_role'   TO 'admin_user'@'%';
