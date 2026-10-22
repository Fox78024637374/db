-- ============================================================
-- Лабораторная работа №4. Оконные функции и аналитика данных
-- СУБД: PostgreSQL 15+
-- ============================================================

-- Запрос 1a. Демонстрация различий ROW_NUMBER, RANK и DENSE_RANK
-- на строках с равными ценами
WITH demo (category, title, price) AS (
    VALUES
        ('Смартфоны', 'Модель A', 1000),
        ('Смартфоны', 'Модель B', 1000),
        ('Смартфоны', 'Модель C', 900),
        ('Смартфоны', 'Модель D', 800)
)
SELECT category,
       title,
       price,
       ROW_NUMBER() OVER (PARTITION BY category ORDER BY price DESC) AS row_number,
       RANK()       OVER (PARTITION BY category ORDER BY price DESC) AS rank,
       DENSE_RANK() OVER (PARTITION BY category ORDER BY price DESC) AS dense_rank
FROM demo
ORDER BY price DESC, title;

-- Запрос 1b. Рейтинг товаров по цене внутри категории «Смартфоны»
SELECT c.name AS category,
       p.title,
       p.price,
       ROW_NUMBER() OVER (PARTITION BY p.category_id ORDER BY p.price DESC) AS row_number,
       RANK()       OVER (PARTITION BY p.category_id ORDER BY p.price DESC) AS rank,
       DENSE_RANK() OVER (PARTITION BY p.category_id ORDER BY p.price DESC) AS dense_rank
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
WHERE p.is_active = TRUE
  AND p.category_id = 2
ORDER BY p.price DESC
LIMIT 15;

-- Запрос 2. Три самых дорогих товара в каждой категории
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
SELECT category,
       rn,
       title,
       price
FROM ranked
WHERE rn <= 3
ORDER BY category, rn;

-- Запрос 3. Нарастающий итог выручки по дням
SELECT o.created_at::date AS day,
       SUM(oi.quantity * oi.unit_price) AS day_revenue,
       SUM(SUM(oi.quantity * oi.unit_price))
           OVER (ORDER BY o.created_at::date) AS running_total
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.id
WHERE o.status <> 'cancelled'
GROUP BY o.created_at::date
ORDER BY day
LIMIT 15;

-- Запрос 4. Доля выручки продавца в выручке его категории
WITH seller_category AS (
    SELECT p.category_id,
           p.seller_id,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM products AS p
    JOIN order_items AS oi ON oi.product_id = p.id
    JOIN orders AS o      ON o.id = oi.order_id
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
LIMIT 20;

-- Запрос 5. LAG и LEAD: сравнение выручки текущего дня с соседними
WITH daily AS (
    SELECT o.created_at::date AS day,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.id
    WHERE o.status <> 'cancelled'
    GROUP BY o.created_at::date
)
SELECT day,
       revenue,
       LAG(revenue)  OVER (ORDER BY day) AS prev_day,
       revenue - LAG(revenue) OVER (ORDER BY day) AS growth_abs,
       ROUND((revenue - LAG(revenue) OVER (ORDER BY day))
             / NULLIF(LAG(revenue) OVER (ORDER BY day), 0) * 100, 2) AS growth_pct,
       LEAD(revenue) OVER (ORDER BY day) AS next_day
FROM daily
ORDER BY day DESC
LIMIT 15;

-- Запрос 6. Та же задача, что в запросе 4, но через GROUP BY и соединение
WITH seller_category AS (
    SELECT p.category_id,
           p.seller_id,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM products AS p
    JOIN order_items AS oi ON oi.product_id = p.id
    JOIN orders AS o      ON o.id = oi.order_id
    WHERE o.status <> 'cancelled'
    GROUP BY p.category_id, p.seller_id
),
category_total AS (
    SELECT category_id,
           SUM(revenue) AS category_revenue
    FROM seller_category
    GROUP BY category_id
)
SELECT c.name AS category,
       s.store_name AS seller,
       sc.revenue,
       ct.category_revenue,
       ROUND(sc.revenue / ct.category_revenue * 100, 2) AS share_pct
FROM seller_category AS sc
JOIN category_total AS ct ON ct.category_id = sc.category_id
JOIN categories AS c      ON c.id = sc.category_id
JOIN sellers    AS s      ON s.id = sc.seller_id
ORDER BY category, share_pct DESC
LIMIT 15;
