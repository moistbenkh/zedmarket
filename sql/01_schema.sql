-- 01_schema.sql : E-Commerce Customer and Sales Analytics (MySQL 8.0+)
-- 9 tables, all InnoDB. Naming: snake_case, *_id for keys. A cart is an order with status = 'cart'.
-- CHECK constraints are enforced from MySQL 8.0.16. Money is DECIMAL, never FLOAT.

CREATE TABLE categories (
    category_id        INT AUTO_INCREMENT PRIMARY KEY,
    name               VARCHAR(80) NOT NULL UNIQUE,
    parent_category_id INT NULL,
    CONSTRAINT fk_categories_parent FOREIGN KEY (parent_category_id)
        REFERENCES categories(category_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE products (
    product_id      INT AUTO_INCREMENT PRIMARY KEY,
    category_id     INT NOT NULL,
    name            VARCHAR(120) NOT NULL,
    sku             VARCHAR(30)  NOT NULL UNIQUE,
    price           DECIMAL(10,2) NOT NULL,
    stock_quantity  INT NOT NULL DEFAULT 0,
    reorder_level   INT NOT NULL DEFAULT 10,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES categories(category_id),
    CONSTRAINT ck_products_price CHECK (price > 0),
    CONSTRAINT ck_products_stock CHECK (stock_quantity >= 0),
    CONSTRAINT ck_products_reorder CHECK (reorder_level >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE customers (
    customer_id    INT AUTO_INCREMENT PRIMARY KEY,
    first_name     VARCHAR(50)  NOT NULL,
    last_name      VARCHAR(50)  NOT NULL,
    email          VARCHAR(120) NOT NULL UNIQUE,
    phone          VARCHAR(20),
    password_hash  VARCHAR(255) NOT NULL,   -- salted PBKDF2-SHA256 hash only, never plain text
    role           VARCHAR(10)  NOT NULL DEFAULT 'customer',
    registered_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_customers_role CHECK (role IN ('customer','admin','analyst'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE addresses (
    address_id   INT AUTO_INCREMENT PRIMARY KEY,
    customer_id  INT NOT NULL,
    street       VARCHAR(150) NOT NULL,
    city         VARCHAR(60)  NOT NULL,
    province     VARCHAR(60)  NOT NULL,
    country      VARCHAR(60)  NOT NULL DEFAULT 'Zambia',
    is_default   BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT fk_addresses_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE orders (
    order_id      INT AUTO_INCREMENT PRIMARY KEY,
    customer_id   INT NOT NULL,
    address_id    INT NULL,
    order_date    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status        VARCHAR(12) NOT NULL DEFAULT 'cart',
    total_amount  DECIMAL(12,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_orders_address  FOREIGN KEY (address_id)  REFERENCES addresses(address_id),
    CONSTRAINT ck_orders_status CHECK (status IN ('cart','placed','paid','shipped','delivered','cancelled','refunded')),
    CONSTRAINT ck_orders_total  CHECK (total_amount >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE order_items (
    order_item_id  INT AUTO_INCREMENT PRIMARY KEY,
    order_id       INT NOT NULL,
    product_id     INT NOT NULL,
    quantity       INT NOT NULL,
    unit_price     DECIMAL(10,2) NOT NULL,          -- price at time of sale
    CONSTRAINT fk_items_order   FOREIGN KEY (order_id)   REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_items_product FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT uq_items_order_product UNIQUE (order_id, product_id),
    CONSTRAINT ck_items_qty   CHECK (quantity > 0),
    CONSTRAINT ck_items_price CHECK (unit_price > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE payments (
    payment_id   INT AUTO_INCREMENT PRIMARY KEY,
    order_id     INT NOT NULL,
    method       VARCHAR(20) NOT NULL,
    status       VARCHAR(10) NOT NULL DEFAULT 'pending',
    amount       DECIMAL(12,2) NOT NULL,
    paid_at      DATETIME NULL,
    CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT ck_payments_method CHECK (method IN ('mobile_money','card','bank_transfer','cash_on_delivery')),
    CONSTRAINT ck_payments_status CHECK (status IN ('pending','completed','failed','refunded')),
    CONSTRAINT ck_payments_amount CHECK (amount > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE reviews (
    review_id    INT AUTO_INCREMENT PRIMARY KEY,
    product_id   INT NOT NULL,
    customer_id  INT NOT NULL,
    rating       INT NOT NULL,
    comment      TEXT,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reviews_product  FOREIGN KEY (product_id)  REFERENCES products(product_id),
    CONSTRAINT fk_reviews_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT uq_reviews_product_customer UNIQUE (product_id, customer_id),
    CONSTRAINT ck_reviews_rating CHECK (rating BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE audit_log (
    audit_id    INT AUTO_INCREMENT PRIMARY KEY,
    table_name  VARCHAR(40) NOT NULL,
    record_id   INT NOT NULL,
    action      VARCHAR(10) NOT NULL,
    old_value   TEXT,
    new_value   TEXT,
    changed_by  VARCHAR(80) NOT NULL,
    changed_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_audit_action CHECK (action IN ('INSERT','UPDATE','DELETE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Indexes for the analytics queries (MySQL already indexes every foreign key; these are the composite and report indexes)
CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date);
CREATE INDEX idx_order_items_product  ON order_items(product_id);
CREATE INDEX idx_products_category    ON products(category_id);
