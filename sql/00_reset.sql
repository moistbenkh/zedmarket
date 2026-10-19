-- 00_reset.sql : drops everything so the database can be rebuilt from scratch (MySQL 8)
SET FOREIGN_KEY_CHECKS = 0;
DROP VIEW IF EXISTS v_monthly_revenue, v_top_products, v_top_customers, v_low_stock, v_customer_orders_masked;
DROP PROCEDURE IF EXISTS place_order;
DROP PROCEDURE IF EXISTS place_order_rs;
DROP PROCEDURE IF EXISTS pay_order;
DROP PROCEDURE IF EXISTS cancel_order;
DROP PROCEDURE IF EXISTS refund_order;
DROP PROCEDURE IF EXISTS sp_selftest_rules;
DROP PROCEDURE IF EXISTS sp_selftest_bad_inserts;
DROP TABLE IF EXISTS audit_log;
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS addresses;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;
SET FOREIGN_KEY_CHECKS = 1;
-- Triggers are dropped together with their tables.
