-- ============================================================
-- Лабораторная работа №6. Современные возможности PostgreSQL
-- и оптимизация запросов
-- СУБД: PostgreSQL 15+
-- ============================================================

-- 1. Столбец JSONB для характеристик товаров
ALTER TABLE products
    ADD COLUMN IF NOT EXISTS attributes JSONB;

ALTER TABLE products DROP CONSTRAINT IF EXISTS chk_products_attributes_object;
ALTER TABLE products
    ADD CONSTRAINT chk_products_attributes_object
    CHECK (attributes IS NULL OR jsonb_typeof(attributes) = 'object');

UPDATE products
SET attributes = CASE category_id
    WHEN 2 THEN '{"color":"black","screen_in":6.5,"memory_gb":128,"5g":true}'::jsonb
    WHEN 3 THEN '{"cpu":"Intel Core i5","ram_gb":16,"storage_gb":512,"screen_in":15.6,"color":"silver"}'::jsonb
    WHEN 4 THEN '{"color":"black","wireless":true,"battery_h":30}'::jsonb
    WHEN 6 THEN '{"power_w":1500,"color":"silver","warranty_years":2}'::jsonb
    WHEN 7 THEN '{"power_w":2000,"bagless":true,"color":"red"}'::jsonb
    WHEN 9 THEN '{"size":"L","color":"blue","material":"cotton"}'::jsonb
    WHEN 10 THEN '{"size":"M","color":"black","material":"polyester"}'::jsonb
    WHEN 11 THEN '{"author":"Иванов И.И.","pages":320,"cover":"hard"}'::jsonb
    WHEN 12 THEN '{"kind":"fitness","weight_kg":5,"color":"black"}'::jsonb
    ELSE '{}'::jsonb
END;

UPDATE products
SET attributes = jsonb_set(
        attributes,
        '{sku}',
        to_jsonb('SKU-' || lpad(id::text, 4, '0'))
    );

-- 2. Запросы к JSONB
SELECT id,
       title,
       attributes -> 'screen_in'  AS screen_json,
       attributes ->> 'screen_in' AS screen_text,
       attributes ->> 'color'     AS color
FROM products
WHERE category_id = 2
ORDER BY id
LIMIT 10;

SELECT id,
       title,
       attributes ->> 'author' AS author,
       (attributes ->> 'pages')::int AS pages
FROM products
WHERE category_id = 11
  AND attributes ? 'author'
ORDER BY pages DESC
LIMIT 10;

SELECT id,
       title,
       attributes #>> '{cpu}' AS cpu,
       attributes #>> '{ram_gb}' AS ram_gb
FROM products
WHERE attributes @> '{"cpu":"Intel Core i5"}'::jsonb
ORDER BY id
LIMIT 10;

-- 3. Планы до создания новых индексов
DROP INDEX IF EXISTS idx_products_category_price;
DROP INDEX IF EXISTS idx_orders_status_created;
DROP INDEX IF EXISTS idx_products_attributes_gin;

VACUUM (ANALYZE) products;
VACUUM (ANALYZE) orders;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, price
FROM products
WHERE category_id = 2
  AND price < 3000
ORDER BY price
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, created_at
FROM orders
WHERE status = 'paid'
  AND created_at >= '2026-01-01'
  AND created_at < '2026-04-01'
ORDER BY created_at;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title
FROM products
WHERE attributes @> '{"sku":"SKU-0854"}'::jsonb;

-- 4. Индексы и повторные планы
CREATE INDEX idx_products_category_price
    ON products(category_id, price);

CREATE INDEX idx_orders_status_created
    ON orders(status, created_at);

CREATE INDEX idx_products_attributes_gin
    ON products USING GIN (attributes);

ANALYZE products;
ANALYZE orders;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, price
FROM products
WHERE category_id = 2
  AND price < 3000
ORDER BY price
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, created_at
FROM orders
WHERE status = 'paid'
  AND created_at >= '2026-01-01'
  AND created_at < '2026-04-01'
ORDER BY created_at;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title
FROM products
WHERE attributes @> '{"sku":"SKU-0854"}'::jsonb;

-- 5. Сравнение массовой вставки с индексом и без индекса
DROP TABLE IF EXISTS lab6_insert_no_index;
DROP TABLE IF EXISTS lab6_insert_with_index;

CREATE TEMP TABLE lab6_insert_no_index (
    id          BIGINT,
    category_id INT,
    price       NUMERIC(12,2),
    payload     TEXT
);

CREATE TEMP TABLE lab6_insert_with_index (
    id          BIGINT,
    category_id INT,
    price       NUMERIC(12,2),
    payload     TEXT
);

CREATE INDEX lab6_insert_with_index_idx
    ON lab6_insert_with_index(category_id, price);

EXPLAIN (ANALYZE, BUFFERS, TIMING)
INSERT INTO lab6_insert_no_index
SELECT g,
       g % 9 + 2,
       (g % 9000) + 100,
       'payload-' || g
FROM generate_series(1, 100000) AS g;

EXPLAIN (ANALYZE, BUFFERS, TIMING)
INSERT INTO lab6_insert_with_index
SELECT g,
       g % 9 + 2,
       (g % 9000) + 100,
       'payload-' || g
FROM generate_series(1, 100000) AS g;

DROP TABLE lab6_insert_no_index;
DROP TABLE lab6_insert_with_index;

-- 6. Итоговые примеры использования JSONB
SELECT id, title, attributes
FROM products
WHERE attributes @> '{"color":"black"}'::jsonb
ORDER BY id
LIMIT 10;

SELECT count(*) AS black_products
FROM products
WHERE attributes @> '{"color":"black"}'::jsonb;

SELECT count(*) AS products_with_sku
FROM products
WHERE attributes ? 'sku';
