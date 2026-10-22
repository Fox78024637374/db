-- ============================================================
-- Лабораторная работа №5. Транзакции, целостность данных
-- и серверная логика
-- СУБД: PostgreSQL 15+
-- ============================================================

-- 1. Журнал изменения цен и денормализованный рейтинг товара
CREATE TABLE IF NOT EXISTS product_price_audit (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id  BIGINT NOT NULL,
    old_price   NUMERIC(12,2),
    new_price   NUMERIC(12,2),
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_by  TEXT NOT NULL DEFAULT current_user
);

ALTER TABLE product_price_audit
    DROP CONSTRAINT IF EXISTS fk_price_audit_product;
ALTER TABLE product_price_audit
    ADD CONSTRAINT fk_price_audit_product
    FOREIGN KEY (product_id) REFERENCES products(id)
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE products
    ADD COLUMN IF NOT EXISTS rating NUMERIC(3,2) NOT NULL DEFAULT 0;

ALTER TABLE products DROP CONSTRAINT IF EXISTS chk_products_rating;
ALTER TABLE products
    ADD CONSTRAINT chk_products_rating CHECK (rating BETWEEN 0 AND 5);

UPDATE products AS p
SET rating = COALESCE(
        (SELECT ROUND(AVG(r.score), 2)
         FROM reviews AS r
         WHERE r.product_id = p.id),
        0
    );

-- 2. Триггер аудита изменения цены
CREATE OR REPLACE FUNCTION log_product_price_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO product_price_audit (product_id, old_price, new_price)
    VALUES (OLD.id, OLD.price, NEW.price);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_price_audit ON products;
CREATE TRIGGER trg_products_price_audit
AFTER UPDATE OF price ON products
FOR EACH ROW
WHEN (OLD.price IS DISTINCT FROM NEW.price)
EXECUTE FUNCTION log_product_price_change();

-- 3. Триггер поддержания среднего рейтинга товара
CREATE OR REPLACE FUNCTION refresh_product_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_product_id BIGINT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_product_id := OLD.product_id;
    ELSE
        v_product_id := NEW.product_id;
    END IF;

    UPDATE products
    SET rating = COALESCE(
            (SELECT ROUND(AVG(score), 2)
             FROM reviews
             WHERE product_id = v_product_id),
            0
        )
    WHERE id = v_product_id;

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_product_rating ON reviews;
CREATE TRIGGER trg_refresh_product_rating
AFTER INSERT OR UPDATE OR DELETE ON reviews
FOR EACH ROW
EXECUTE FUNCTION refresh_product_rating();

-- 4. Атомарная функция оформления заказа
CREATE OR REPLACE FUNCTION place_order(
    p_user    BIGINT,
    p_product BIGINT,
    p_qty     INT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id BIGINT;
    v_price    NUMERIC(12,2);
    v_stock    INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Количество должно быть положительным (передано %)', p_qty;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user) THEN
        RAISE EXCEPTION 'Пользователь % не найден', p_user;
    END IF;

    SELECT price
    INTO v_price
    FROM products
    WHERE id = p_product AND is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Товар % не найден или неактивен', p_product;
    END IF;

    SELECT quantity
    INTO v_stock
    FROM stock
    WHERE product_id = p_product
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Для товара % нет складской записи', p_product;
    END IF;

    IF v_stock < p_qty THEN
        RAISE EXCEPTION 'Недостаточно товара на складе (id=%, остаток=%, запрошено=%)',
            p_product, v_stock, p_qty;
    END IF;

    INSERT INTO orders (user_id, status, total_amount)
    VALUES (p_user, 'created', v_price * p_qty)
    RETURNING id INTO v_order_id;

    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, p_product, p_qty, v_price);

    UPDATE stock
    SET quantity = quantity - p_qty,
        updated_at = now()
    WHERE product_id = p_product;

    RETURN v_order_id;
END;
$$;

-- 5. Функция расчёта выручки продавца за период
CREATE OR REPLACE FUNCTION seller_revenue(
    p_seller_id BIGINT,
    p_from      DATE,
    p_to        DATE
)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_revenue NUMERIC(14,2);
BEGIN
    SELECT COALESCE(SUM(oi.quantity * oi.unit_price), 0)
    INTO v_revenue
    FROM sellers AS s
    JOIN products AS p     ON p.seller_id = s.id
    JOIN order_items AS oi ON oi.product_id = p.id
    JOIN orders AS o       ON o.id = oi.order_id
    WHERE s.id = p_seller_id
      AND o.status <> 'cancelled'
      AND o.created_at::date BETWEEN p_from AND p_to;

    RETURN v_revenue;
END;
$$;

-- 6. Демонстрация транзакции с COMMIT
DROP TABLE IF EXISTS lab5_tx_demo;
CREATE TEMP TABLE lab5_tx_demo (
    order_id   BIGINT,
    product_id BIGINT,
    qty        INT
);

BEGIN;
WITH new_order AS (
    INSERT INTO orders (user_id, status, total_amount)
    VALUES (1, 'created', (SELECT price FROM products WHERE id = 1) * 2)
    RETURNING id
)
INSERT INTO lab5_tx_demo (order_id, product_id, qty)
SELECT id, 1, 2 FROM new_order;

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT d.order_id, d.product_id, d.qty, p.price
FROM lab5_tx_demo AS d
JOIN products AS p ON p.id = d.product_id;

UPDATE stock AS s
SET quantity = s.quantity - d.qty,
    updated_at = now()
FROM lab5_tx_demo AS d
WHERE s.product_id = d.product_id;
COMMIT;

SELECT o.id AS order_id,
       o.status,
       o.total_amount,
       oi.product_id,
       oi.quantity,
       oi.unit_price,
       s.quantity AS stock_after
FROM lab5_tx_demo AS d
JOIN orders AS o      ON o.id = d.order_id
JOIN order_items AS oi ON oi.order_id = o.id
JOIN stock AS s       ON s.product_id = d.product_id;

-- Возврат данных после демонстрации COMMIT
BEGIN;
UPDATE stock AS s
SET quantity = s.quantity + d.qty,
    updated_at = now()
FROM lab5_tx_demo AS d
WHERE s.product_id = d.product_id;

DELETE FROM orders AS o
USING lab5_tx_demo AS d
WHERE o.id = d.order_id;
COMMIT;

DROP TABLE lab5_tx_demo;

-- 7. Демонстрация ROLLBACK: данные остаются неизменными
SELECT count(*) AS orders_before,
       (SELECT quantity FROM stock WHERE product_id = 1) AS stock_before
FROM orders;

BEGIN;
WITH new_order AS (
    INSERT INTO orders (user_id, status, total_amount)
    VALUES (1, 'created', (SELECT price FROM products WHERE id = 1) * 3)
    RETURNING id
)
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT id, 1, 3, (SELECT price FROM products WHERE id = 1)
FROM new_order;

UPDATE stock
SET quantity = quantity - 3,
    updated_at = now()
WHERE product_id = 1;

-- Имитация сбоя: отменяем всю транзакцию
ROLLBACK;

SELECT count(*) AS orders_after,
       (SELECT quantity FROM stock WHERE product_id = 1) AS stock_after
FROM orders;

-- 8. Демонстрация SAVEPOINT
BEGIN;
UPDATE stock SET quantity = quantity - 1 WHERE product_id = 1;
SAVEPOINT sp_stock;
UPDATE stock SET quantity = quantity - 10 WHERE product_id = 1;
ROLLBACK TO SAVEPOINT sp_stock;
COMMIT;

SELECT quantity AS stock_after_savepoint
FROM stock
WHERE product_id = 1;

UPDATE stock SET quantity = quantity + 1 WHERE product_id = 1;

-- 9. Успешное оформление заказа
BEGIN;
SELECT place_order(1, 1, 2) AS new_order_id;

SELECT o.id AS order_id,
       o.total_amount,
       oi.product_id,
       oi.quantity,
       oi.unit_price,
       s.quantity AS stock_after
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.id
JOIN stock AS s       ON s.product_id = oi.product_id
WHERE o.id = (SELECT max(id) FROM orders);
ROLLBACK;

-- 10. Ошибка при нехватке товара: частичных изменений нет
DO $$
DECLARE
    v_stock_before INT;
    v_stock_after  INT;
    v_orders_before BIGINT;
    v_orders_after  BIGINT;
BEGIN
    SELECT quantity INTO v_stock_before FROM stock WHERE product_id = 1;
    SELECT count(*) INTO v_orders_before FROM orders;

    BEGIN
        PERFORM place_order(1, 1, 999999);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Ожидаемая ошибка: %', SQLERRM;
    END;

    SELECT quantity INTO v_stock_after FROM stock WHERE product_id = 1;
    SELECT count(*) INTO v_orders_after FROM orders;

    RAISE NOTICE 'Остаток до=%, после=%', v_stock_before, v_stock_after;
    RAISE NOTICE 'Заказов до=%, после=%', v_orders_before, v_orders_after;
END;
$$;

-- 11. Проверка функции выручки продавца
SELECT seller_revenue(22, DATE '2024-01-01', DATE '2026-12-31') AS revenue_2024_2026;

-- 12. Проверка триггера аудита цены
SELECT price AS price_before FROM products WHERE id = 854;

UPDATE products SET price = price + 100 WHERE id = 854;
UPDATE products SET price = price - 100 WHERE id = 854;

SELECT price AS price_after FROM products WHERE id = 854;

SELECT id,
       product_id,
       old_price,
       new_price,
       changed_at
FROM product_price_audit
WHERE product_id = 854
ORDER BY id DESC
LIMIT 2;

-- 13. Проверка триггера рейтинга
SELECT id, rating AS rating_before FROM products WHERE id = 854;

BEGIN;
INSERT INTO reviews (user_id, product_id, score, comment)
VALUES (1, 854, 5, 'Тестовый отзыв для проверки триггера');
SELECT id, rating AS rating_after_insert FROM products WHERE id = 854;
ROLLBACK;

SELECT id, rating AS rating_after_rollback FROM products WHERE id = 854;

-- 14. Товары с наибольшим рейтингом
SELECT id, title, rating
FROM products
WHERE rating > 0
ORDER BY rating DESC, id
LIMIT 10;
