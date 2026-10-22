-- ============================================================
-- Лабораторная работа №2. Наполнение базы данных тестовыми данными
-- СУБД: PostgreSQL 15+
-- Скрипт идемпотентен: очищает таблицы и заполняет их заново.
-- ============================================================

BEGIN;

-- Полная очистка с обнулением счётчиков IDENTITY.
TRUNCATE TABLE deliveries, addresses, reviews, payments,
               order_items, orders, cart_items, carts,
               stock, products, sellers, categories, users
    RESTART IDENTITY CASCADE;

-- ------------------------------------------------------------
-- 1. Пользователи: 1 администратор, 30 продавцов, 169 покупателей
-- ------------------------------------------------------------
INSERT INTO users (id, full_name, email, phone, role, created_at)
OVERRIDING SYSTEM VALUE
SELECT g,
       'Пользователь ' || g,
       'user' || g || '@example.com',
       '+7' || (9000000000 + g)::text,
       CASE
           WHEN g = 1 THEN 'admin'
           WHEN g <= 31 THEN 'seller'
           ELSE 'buyer'
       END,
       now() - ((g % 365) || ' days')::interval
FROM generate_series(1, 200) AS g;

-- ------------------------------------------------------------
-- 2. Категории: дерево из 12 узлов (3 корня с подкатегориями)
-- ------------------------------------------------------------
INSERT INTO categories (id, parent_id, name)
OVERRIDING SYSTEM VALUE
VALUES
    (1,  NULL, 'Электроника'),
    (2,  1,    'Смартфоны'),
    (3,  1,    'Ноутбуки'),
    (4,  1,    'Аудиотехника'),
    (5,  NULL, 'Бытовая техника'),
    (6,  5,    'Кухонная техника'),
    (7,  5,    'Пылесосы'),
    (8,  NULL, 'Одежда'),
    (9,  8,    'Мужская одежда'),
    (10, 8,    'Женская одежда'),
    (11, NULL, 'Книги'),
    (12, NULL, 'Спорт и отдых');

-- ------------------------------------------------------------
-- 3. Продавцы: 30 магазинов, привязанных к пользователям 2..31
-- ------------------------------------------------------------
INSERT INTO sellers (id, user_id, store_name, description, created_at)
OVERRIDING SYSTEM VALUE
SELECT g,
       g + 1,
       'Магазин №' || g,
       CASE WHEN g % 5 = 0 THEN NULL ELSE 'Описание магазина №' || g END,
       now() - (((g * 3) % 300) || ' days')::interval
FROM generate_series(1, 30) AS g;

-- ------------------------------------------------------------
-- 4. Товары: 1200 строк, распределены по продавцам и категориям
-- ------------------------------------------------------------
WITH cats AS (
    SELECT ARRAY[2, 3, 4, 6, 7, 9, 10, 11, 12] AS ids
)
INSERT INTO products (id, seller_id, category_id, title, description,
                      price, is_active, created_at)
OVERRIDING SYSTEM VALUE
SELECT g,
       1 + ((g * 7) % 30),
       c.ids[1 + ((g - 1) % array_length(c.ids, 1))],
       CASE c.ids[1 + ((g - 1) % array_length(c.ids, 1))]
           WHEN 2  THEN 'Смартфон'
           WHEN 3  THEN 'Ноутбук'
           WHEN 4  THEN 'Наушники'
           WHEN 6  THEN 'Блендер'
           WHEN 7  THEN 'Пылесос'
           WHEN 9  THEN 'Мужская куртка'
           WHEN 10 THEN 'Женское платье'
           WHEN 11 THEN 'Книга'
           ELSE 'Спортивный товар'
       END || ' №' || g,
       CASE WHEN g % 7 = 0 THEN NULL ELSE 'Описание товара №' || g END,
       (1000 + ((g * 137) % 9000))::numeric(12, 2),
       (g % 11 <> 0),
       now() - ((g % 500) || ' days')::interval
FROM generate_series(1, 1200) AS g
CROSS JOIN cats AS c;

-- ------------------------------------------------------------
-- 5. Складские остатки: по одной записи на каждый товар
-- ------------------------------------------------------------
INSERT INTO stock (product_id, quantity, updated_at)
SELECT p.id,
       CASE WHEN p.id % 17 = 0 THEN 0 ELSE (p.id * 37) % 500 END,
       now() - ((p.id % 30) || ' days')::interval
FROM products AS p;

-- ------------------------------------------------------------
-- 6. Корзины: 120 корзин покупателей (пользователи 32..151)
-- ------------------------------------------------------------
INSERT INTO carts (id, user_id, created_at)
OVERRIDING SYSTEM VALUE
SELECT g,
       31 + g,
       now() - ((g % 180) || ' days')::interval
FROM generate_series(1, 120) AS g;

-- ------------------------------------------------------------
-- 7. Позиции корзин: по 3 товара в каждой корзине
-- ------------------------------------------------------------
INSERT INTO cart_items (cart_id, product_id, quantity)
SELECT c.id,
       1 + (((c.id * 37) + (k * 113)) % 1200),
       1 + ((c.id + k) % 5)
FROM carts AS c
CROSS JOIN generate_series(1, 3) AS k;

-- ------------------------------------------------------------
-- 8. Адреса: по одному адресу на каждого пользователя
-- ------------------------------------------------------------
INSERT INTO addresses (id, user_id, city, street, house, apartment)
OVERRIDING SYSTEM VALUE
SELECT g,
       g,
       (ARRAY['Москва', 'Санкт-Петербург', 'Казань',
              'Новосибирск', 'Екатеринбург'])[1 + (g % 5)],
       'Улица ' || g,
       ((g % 200) + 1)::text,
       CASE WHEN g % 4 = 0 THEN NULL ELSE ((g % 150) + 1)::text END
FROM generate_series(1, 200) AS g;

-- ------------------------------------------------------------
-- 9. Заказы: 1500 строк, статусы распределены равномерно
-- ------------------------------------------------------------
INSERT INTO orders (id, user_id, status, total_amount, created_at)
OVERRIDING SYSTEM VALUE
SELECT g,
       32 + ((g * 7) % 169),
       (ARRAY['created', 'paid', 'shipped', 'delivered', 'cancelled'])[1 + (g % 5)],
       0,
       now() - ((g % 730) || ' days')::interval
FROM generate_series(1, 1500) AS g;

-- ------------------------------------------------------------
-- 10. Позиции заказов: от 1 до 3 товаров в каждом заказе
-- ------------------------------------------------------------
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT o.id,
       p.id,
       1 + ((o.id + k) % 5),
       p.price
FROM orders AS o
CROSS JOIN generate_series(1, 3) AS k
JOIN products AS p
  ON p.id = 1 + (((o.id * 53) + (k * 311)) % 1200);

-- Сумма заказа рассчитывается по его позициям.
UPDATE orders AS o
SET total_amount = COALESCE(
        (SELECT SUM(oi.quantity * oi.unit_price)
         FROM order_items AS oi
         WHERE oi.order_id = o.id), 0);

-- ------------------------------------------------------------
-- 11. Платежи: по оплате для заказов в статусах paid/shipped/delivered
-- ------------------------------------------------------------
INSERT INTO payments (order_id, amount, status, paid_at)
SELECT o.id,
       o.total_amount,
       CASE WHEN o.id % 17 = 0 THEN 'pending' ELSE 'completed' END,
       CASE WHEN o.id % 17 = 0 THEN NULL
            ELSE o.created_at + interval '10 minutes' END
FROM orders AS o
WHERE o.status IN ('paid', 'shipped', 'delivered');

-- ------------------------------------------------------------
-- 12. Доставки: для заказов shipped и delivered
-- ------------------------------------------------------------
INSERT INTO deliveries (order_id, address_id, delivery_status, delivery_date)
SELECT o.id,
       (SELECT a.id
        FROM addresses AS a
        WHERE a.user_id = o.user_id
        ORDER BY a.id
        LIMIT 1),
       CASE WHEN o.status = 'delivered' THEN 'delivered' ELSE 'in_transit' END,
       CASE WHEN o.status = 'delivered'
            THEN o.created_at + interval '3 days' END
FROM orders AS o
WHERE o.status IN ('shipped', 'delivered');

-- ------------------------------------------------------------
-- 13. Отзывы: по одному отзыву на пару (покупатель, товар)
-- ------------------------------------------------------------
INSERT INTO reviews (user_id, product_id, score, comment, created_at)
SELECT DISTINCT ON (o.user_id, oi.product_id)
       o.user_id,
       oi.product_id,
       1 + ((o.id + oi.product_id) % 5),
       CASE WHEN (o.id + oi.product_id) % 3 = 0 THEN NULL
            ELSE 'Отзыв к товару №' || oi.product_id END,
       o.created_at + interval '7 days'
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.id
WHERE o.status = 'delivered'
ORDER BY o.user_id, oi.product_id, o.id;

-- ------------------------------------------------------------
-- 14. Синхронизация счётчиков IDENTITY после явных ID
-- ------------------------------------------------------------
SELECT setval(pg_get_serial_sequence('users', 'id'),      (SELECT max(id) FROM users));
SELECT setval(pg_get_serial_sequence('categories', 'id'), (SELECT max(id) FROM categories));
SELECT setval(pg_get_serial_sequence('sellers', 'id'),    (SELECT max(id) FROM sellers));
SELECT setval(pg_get_serial_sequence('products', 'id'),   (SELECT max(id) FROM products));
SELECT setval(pg_get_serial_sequence('carts', 'id'),      (SELECT max(id) FROM carts));
SELECT setval(pg_get_serial_sequence('orders', 'id'),     (SELECT max(id) FROM orders));
SELECT setval(pg_get_serial_sequence('payments', 'id'),   (SELECT max(id) FROM payments));
SELECT setval(pg_get_serial_sequence('reviews', 'id'),    (SELECT max(id) FROM reviews));
SELECT setval(pg_get_serial_sequence('addresses', 'id'),  (SELECT max(id) FROM addresses));
SELECT setval(pg_get_serial_sequence('deliveries', 'id'), (SELECT max(id) FROM deliveries));

COMMIT;

-- ------------------------------------------------------------
-- 15. Контроль наполнения
-- ------------------------------------------------------------
SELECT 'users'      AS table_name, count(*) AS rows FROM users
UNION ALL SELECT 'categories', count(*) FROM categories
UNION ALL SELECT 'sellers',    count(*) FROM sellers
UNION ALL SELECT 'products',   count(*) FROM products
UNION ALL SELECT 'stock',      count(*) FROM stock
UNION ALL SELECT 'carts',      count(*) FROM carts
UNION ALL SELECT 'cart_items', count(*) FROM cart_items
UNION ALL SELECT 'addresses',  count(*) FROM addresses
UNION ALL SELECT 'orders',     count(*) FROM orders
UNION ALL SELECT 'order_items',count(*) FROM order_items
UNION ALL SELECT 'payments',   count(*) FROM payments
UNION ALL SELECT 'deliveries', count(*) FROM deliveries
UNION ALL SELECT 'reviews',    count(*) FROM reviews
ORDER BY table_name;

ANALYZE;
