
DROP TABLE IF EXISTS deliveries   CASCADE;
DROP TABLE IF EXISTS addresses    CASCADE;
DROP TABLE IF EXISTS reviews      CASCADE;
DROP TABLE IF EXISTS payments     CASCADE;
DROP TABLE IF EXISTS order_items  CASCADE;
DROP TABLE IF EXISTS orders       CASCADE;
DROP TABLE IF EXISTS cart_items   CASCADE;
DROP TABLE IF EXISTS carts        CASCADE;
DROP TABLE IF EXISTS stock        CASCADE;
DROP TABLE IF EXISTS products     CASCADE;
DROP TABLE IF EXISTS sellers      CASCADE;
DROP TABLE IF EXISTS categories   CASCADE;
DROP TABLE IF EXISTS users        CASCADE;

-- 1. Пользователи
CREATE TABLE users (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name   VARCHAR(200) NOT NULL,
    email       VARCHAR(254) NOT NULL,
    phone       VARCHAR(20),
    role        VARCHAR(20)  NOT NULL DEFAULT 'buyer',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT uq_users_phone UNIQUE (phone),
    CONSTRAINT chk_users_role CHECK (role IN ('buyer','seller','admin'))
);

-- 2. Категории (иерархия, самоссылка)
CREATE TABLE categories (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_id  BIGINT REFERENCES categories(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    name       VARCHAR(100) NOT NULL,
    CONSTRAINT uq_categories_name UNIQUE (name)
);

-- 3. Продавцы (1:1 с users)
CREATE TABLE sellers (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL,
    store_name  VARCHAR(200) NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_sellers_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT uq_sellers_user UNIQUE (user_id),
    CONSTRAINT uq_sellers_store_name UNIQUE (store_name)
);

-- 4. Товары
CREATE TABLE products (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id   BIGINT NOT NULL,
    category_id BIGINT NOT NULL,
    title       VARCHAR(300) NOT NULL,
    description TEXT,
    price       NUMERIC(12,2) NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_products_seller FOREIGN KEY (seller_id)
        REFERENCES sellers(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_products_category FOREIGN KEY (category_id)
        REFERENCES categories(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_products_price CHECK (price > 0)
);

-- 5. Склад (1:1 с products)
CREATE TABLE stock (
    product_id BIGINT PRIMARY KEY,
    quantity   INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_stock_product FOREIGN KEY (product_id)
        REFERENCES products(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_stock_quantity CHECK (quantity >= 0)
);

-- 6. Корзины
CREATE TABLE carts (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_carts_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE
);

-- 7. Позиции корзины (M:N carts × products)
CREATE TABLE cart_items (
    cart_id    BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity   INTEGER NOT NULL,
    PRIMARY KEY (cart_id, product_id),
    CONSTRAINT fk_cart_items_cart FOREIGN KEY (cart_id)
        REFERENCES carts(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_cart_items_product FOREIGN KEY (product_id)
        REFERENCES products(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_cart_items_quantity CHECK (quantity > 0)
);

-- 8. Заказы
CREATE TABLE orders (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      BIGINT NOT NULL,
    status       VARCHAR(20) NOT NULL DEFAULT 'created',
    total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_orders_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_orders_status CHECK (status IN
        ('created','paid','shipped','delivered','cancelled')),
    CONSTRAINT chk_orders_total CHECK (total_amount >= 0)
);

-- 9. Позиции заказа (M:N orders × products)
CREATE TABLE order_items (
    order_id   BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity   INTEGER NOT NULL,
    unit_price NUMERIC(12,2) NOT NULL,
    PRIMARY KEY (order_id, product_id),
    CONSTRAINT fk_order_items_order FOREIGN KEY (order_id)
        REFERENCES orders(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_order_items_product FOREIGN KEY (product_id)
        REFERENCES products(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_order_items_quantity CHECK (quantity > 0),
    CONSTRAINT chk_order_items_price CHECK (unit_price > 0)
);

-- 10. Платежи
CREATE TABLE payments (
    id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    amount   NUMERIC(12,2) NOT NULL,
    status   VARCHAR(20) NOT NULL DEFAULT 'pending',
    paid_at  TIMESTAMPTZ,
    CONSTRAINT fk_payments_order FOREIGN KEY (order_id)
        REFERENCES orders(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_payments_amount CHECK (amount > 0),
    CONSTRAINT chk_payments_status CHECK (status IN
        ('pending','completed','failed','refunded'))
);

-- 11. Отзывы
CREATE TABLE reviews (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    score      INTEGER NOT NULL,
    comment    TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_reviews_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_reviews_product FOREIGN KEY (product_id)
        REFERENCES products(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_reviews_score CHECK (score BETWEEN 1 AND 5),
    CONSTRAINT uq_reviews_user_product UNIQUE (user_id, product_id)
);

-- 12. Адреса
CREATE TABLE addresses (
    id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id   BIGINT NOT NULL,
    city      VARCHAR(100) NOT NULL,
    street    VARCHAR(200) NOT NULL,
    house     VARCHAR(20)  NOT NULL,
    apartment VARCHAR(20),
    CONSTRAINT fk_addresses_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE
);

-- 13. Доставки
CREATE TABLE deliveries (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id        BIGINT NOT NULL,
    address_id      BIGINT NOT NULL,
    delivery_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    delivery_date   TIMESTAMPTZ,
    CONSTRAINT fk_deliveries_order FOREIGN KEY (order_id)
        REFERENCES orders(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_deliveries_address FOREIGN KEY (address_id)
        REFERENCES addresses(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_deliveries_order UNIQUE (order_id),
    CONSTRAINT chk_deliveries_status CHECK (delivery_status IN
        ('pending','in_transit','delivered','cancelled'))
);

-- Индексы по внешним ключам
CREATE INDEX idx_products_seller      ON products(seller_id);
CREATE INDEX idx_products_category    ON products(category_id);
CREATE INDEX idx_orders_user          ON orders(user_id);
CREATE INDEX idx_reviews_product      ON reviews(product_id);
CREATE INDEX idx_cart_items_product   ON cart_items(product_id);
CREATE INDEX idx_order_items_product  ON order_items(product_id);
CREATE INDEX idx_addresses_user       ON addresses(user_id);
CREATE INDEX idx_categories_parent    ON categories(parent_id);