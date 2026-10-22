-- ============================================================
-- Лабораторная работа №3. Многотабличные запросы
-- и аналитические представления
-- СУБД: PostgreSQL 15+
-- ============================================================

DROP VIEW IF EXISTS v_product_catalog CASCADE;
DROP VIEW IF EXISTS v_seller_revenue  CASCADE;
DROP VIEW IF EXISTS v_category_stats  CASCADE;

-- Запрос 1. INNER JOIN трёх таблиц: товар — категория — продавец
SELECT p.id,
       p.title,
       c.name       AS category,
       s.store_name AS seller,
       p.price
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
JOIN sellers    AS s ON s.id = p.seller_id
WHERE p.is_active = TRUE
ORDER BY p.price DESC
LIMIT 15;

-- Запрос 2. LEFT JOIN: товары без отзывов
SELECT p.id,
       p.title,
       p.price
FROM products AS p
LEFT JOIN reviews AS r ON r.product_id = p.id
WHERE r.id IS NULL
ORDER BY p.price DESC
LIMIT 15;

-- Запрос 3. GROUP BY: количество товаров и средняя цена по категориям
SELECT c.id,
       c.name AS category,
       COUNT(p.id) AS products_count,
       ROUND(AVG(p.price), 2) AS avg_price
FROM categories AS c
LEFT JOIN products AS p ON p.category_id = c.id
GROUP BY c.id, c.name
ORDER BY products_count DESC, c.name;

-- Запрос 4. HAVING: продавцы с выручкой выше 2 000 000
SELECT s.id,
       s.store_name,
       COUNT(DISTINCT o.id) AS orders_count,
       SUM(oi.quantity * oi.unit_price) AS revenue
FROM sellers AS s
JOIN products AS p    ON p.seller_id = s.id
JOIN order_items AS oi ON oi.product_id = p.id
JOIN orders AS o      ON o.id = oi.order_id
WHERE o.status <> 'cancelled'
GROUP BY s.id, s.store_name
HAVING SUM(oi.quantity * oi.unit_price) > 2000000
ORDER BY revenue DESC;

-- Запрос 5a. Скалярный подзапрос: товары дороже средней цены
SELECT p.id,
       p.title,
       p.price,
       (SELECT ROUND(AVG(price), 2) FROM products) AS avg_price
FROM products AS p
WHERE p.price > (SELECT AVG(price) FROM products)
ORDER BY p.price DESC
LIMIT 15;

-- Запрос 5b. Подзапрос с IN: продавцы, у которых есть товары в категории 2
SELECT s.id,
       s.store_name
FROM sellers AS s
WHERE s.id IN (SELECT p.seller_id
               FROM products AS p
               WHERE p.category_id = 2)
ORDER BY s.id
LIMIT 15;

-- Запрос 5c. EXISTS: товары, у которых есть отзыв с оценкой 5
SELECT p.id,
       p.title,
       p.price
FROM products AS p
WHERE p.is_active = TRUE
  AND EXISTS (SELECT 1
              FROM reviews AS r
              WHERE r.product_id = p.id
                AND r.score = 5)
ORDER BY p.price DESC
LIMIT 15;

-- Запрос 6a. CTE: дневная выручка и количество заказов
WITH order_revenue AS (
    SELECT o.id,
           o.created_at::date AS day,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.id
    WHERE o.status <> 'cancelled'
    GROUP BY o.id, o.created_at
),
daily AS (
    SELECT day,
           SUM(revenue) AS revenue,
           COUNT(*)     AS orders_count
    FROM order_revenue
    GROUP BY day
)
SELECT day,
       revenue,
       orders_count,
       ROUND(revenue / NULLIF(orders_count, 0), 2) AS avg_order_revenue
FROM daily
ORDER BY day DESC
LIMIT 15;

-- Запрос 6b. Рекурсивный CTE: обход дерева категорий
WITH RECURSIVE category_tree AS (
    SELECT id,
           parent_id,
           name,
           0 AS depth,
           name::text AS path
    FROM categories
    WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id,
           c.parent_id,
           c.name,
           ct.depth + 1,
           ct.path || ' → ' || c.name
    FROM categories AS c
    JOIN category_tree AS ct ON ct.id = c.parent_id
)
SELECT id,
       depth,
       repeat('  ', depth) || name AS tree_node,
       path
FROM category_tree
ORDER BY path;

-- Запрос 7a. Представление: каталог товаров
CREATE VIEW v_product_catalog AS
SELECT p.id,
       p.title,
       c.name AS category,
       s.store_name AS seller,
       p.price,
       COALESCE(st.quantity, 0) AS stock_quantity,
       p.is_active
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
JOIN sellers    AS s ON s.id = p.seller_id
LEFT JOIN stock AS st ON st.product_id = p.id;

-- Запрос 7b. Представление: выручка продавцов
CREATE VIEW v_seller_revenue AS
SELECT s.id AS seller_id,
       s.store_name,
       COUNT(DISTINCT o.id) AS orders_count,
       SUM(oi.quantity) AS items_sold,
       SUM(oi.quantity * oi.unit_price) AS revenue
FROM sellers AS s
JOIN products AS p    ON p.seller_id = s.id
JOIN order_items AS oi ON oi.product_id = p.id
JOIN orders AS o      ON o.id = oi.order_id
WHERE o.status <> 'cancelled'
GROUP BY s.id, s.store_name;

-- Запрос 7c. Представление: статистика по категориям
CREATE VIEW v_category_stats AS
SELECT c.id AS category_id,
       c.name AS category,
       COUNT(p.id) AS products_count,
       ROUND(AVG(p.price), 2) AS avg_price,
       COALESCE(SUM(st.quantity), 0) AS stock_total
FROM categories AS c
LEFT JOIN products AS p ON p.category_id = c.id
LEFT JOIN stock AS st   ON st.product_id = p.id
GROUP BY c.id, c.name;

-- Обращение к представлению 1
SELECT category,
       seller,
       title,
       price,
       stock_quantity
FROM v_product_catalog
WHERE is_active = TRUE
ORDER BY price DESC
LIMIT 10;

-- Обращение к представлению 2
SELECT store_name,
       orders_count,
       items_sold,
       revenue
FROM v_seller_revenue
ORDER BY revenue DESC
LIMIT 10;

-- Обращение к представлению 3
SELECT category,
       products_count,
       avg_price,
       stock_total
FROM v_category_stats
ORDER BY products_count DESC, category;
