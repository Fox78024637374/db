-- ============================================================
-- Итоговый проект. Демонстрационный набор запросов
-- База данных: marketplace
-- Перед запуском должны быть выполнены:
--   lab_7/schema_final.sql
--   lab_2/lab_2seed.sql
--   lab_3/lab_3queries.sql      (создаёт представления)
--   lab_6/lab_6json_indexes.sql (заполняет JSONB и создаёт GIN)
-- ============================================================

-- 1. Многотабличная выборка: товар — категория — продавец
SELECT p.id,
       p.title,
       c.name       AS category,
       s.store_name AS seller,
       p.price,
       p.rating
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
JOIN sellers    AS s ON s.id = p.seller_id
WHERE p.is_active = TRUE
ORDER BY p.price DESC
LIMIT 10;

-- 2. Агрегация: сводка по категориям
SELECT c.name AS category,
       COUNT(p.id) AS products_count,
       ROUND(AVG(p.price), 2) AS avg_price,
       MIN(p.price) AS min_price,
       MAX(p.price) AS max_price
FROM categories AS c
LEFT JOIN products AS p ON p.category_id = c.id
GROUP BY c.id, c.name
ORDER BY products_count DESC, c.name;

-- 3. Подзапрос: продавцы с выручкой выше средней
WITH seller_revenue AS (
    SELECT s.id,
           s.store_name,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM sellers AS s
    JOIN products AS p     ON p.seller_id = s.id
    JOIN order_items AS oi ON oi.product_id = p.id
    JOIN orders AS o       ON o.id = oi.order_id
    WHERE o.status <> 'cancelled'
    GROUP BY s.id, s.store_name
)
SELECT id, store_name, revenue
FROM seller_revenue
WHERE revenue > (SELECT AVG(revenue) FROM seller_revenue)
ORDER BY revenue DESC;

-- 4. CTE и оконная функция: три самых дорогих товара в каждой категории
WITH ranked AS (
    SELECT p.id,
           p.title,
           c.name AS category,
           p.price,
           ROW_NUMBER() OVER (
               PARTITION BY p.category_id
               ORDER BY p.price DESC, p.id
           ) AS rn
    FROM products AS p
    JOIN categories AS c ON c.id = p.category_id
    WHERE p.is_active = TRUE
)
SELECT category, rn, title, price
FROM ranked
WHERE rn <= 3
ORDER BY category, rn;

-- 5. Оконная функция: доля продавца в выручке категории
WITH seller_category AS (
    SELECT p.category_id,
           p.seller_id,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM products AS p
    JOIN order_items AS oi ON oi.product_id = p.id
    JOIN orders AS o       ON o.id = oi.order_id
    WHERE o.status <> 'cancelled'
    GROUP BY p.category_id, p.seller_id
)
SELECT c.name AS category,
       s.store_name AS seller,
       sc.revenue,
       SUM(sc.revenue) OVER (PARTITION BY sc.category_id) AS category_revenue,
       ROUND(sc.revenue
             / SUM(sc.revenue) OVER (PARTITION BY sc.category_id) * 100, 2) AS share_pct
FROM seller_category AS sc
JOIN categories AS c ON c.id = sc.category_id
JOIN sellers    AS s ON s.id = sc.seller_id
ORDER BY category, share_pct DESC
LIMIT 15;

-- 6. Рекурсивный CTE: дерево категорий
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
SELECT id, depth, repeat('  ', depth) || name AS tree_node, path
FROM category_tree
ORDER BY path;

-- 7. JSONB: фильтрация и извлечение характеристик
SELECT id,
       title,
       attributes ->> 'sku'   AS sku,
       attributes ->> 'color' AS color,
       attributes ->> 'cpu'   AS cpu
FROM products
WHERE attributes @> '{"color":"black"}'::jsonb
ORDER BY id
LIMIT 10;

-- 8. Представление: выручка продавцов
SELECT store_name,
       orders_count,
       items_sold,
       revenue
FROM v_seller_revenue
ORDER BY revenue DESC
LIMIT 10;

-- 9. Серверная функция: выручка продавца за период
SELECT seller_revenue(22, DATE '2024-01-01', DATE '2026-12-31') AS seller_22_revenue;

-- 10. Проверка целостности данных
SELECT 'orders без пользователя' AS check_name, COUNT(*) AS violations
FROM orders AS o
LEFT JOIN users AS u ON u.id = o.user_id
WHERE u.id IS NULL
UNION ALL
SELECT 'позиции без заказа', COUNT(*)
FROM order_items AS oi
LEFT JOIN orders AS o ON o.id = oi.order_id
WHERE o.id IS NULL
UNION ALL
SELECT 'товары без продавца', COUNT(*)
FROM products AS p
LEFT JOIN sellers AS s ON s.id = p.seller_id
WHERE s.id IS NULL
UNION ALL
SELECT 'отзывы без товара', COUNT(*)
FROM reviews AS r
LEFT JOIN products AS p ON p.id = r.product_id
WHERE p.id IS NULL
UNION ALL
SELECT 'заказы с неверной суммой', COUNT(*)
FROM orders AS o
WHERE o.total_amount <> COALESCE(
    (SELECT SUM(oi.quantity * oi.unit_price)
     FROM order_items AS oi
     WHERE oi.order_id = o.id),
    0
)
ORDER BY check_name;
