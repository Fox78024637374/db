-- ============================================================
-- Лабораторная работа №2. Базовые SQL-запросы и фильтрация данных
-- СУБД: PostgreSQL 15+
-- Все запросы выполняются к базе marketplace после lab_2seed.sql
-- Файл совместим с pgAdmin 4 Query Tool и psql.
-- ============================================================

-- === Запрос 1. DISTINCT: уникальные пары «продавец — категория» ===
SELECT DISTINCT p.seller_id  AS seller_id,
                p.category_id AS category_id
FROM products AS p
ORDER BY p.seller_id, p.category_id
LIMIT 15;

-- === Запрос 2. Фильтрация AND/OR со скобками ===
SELECT p.id,
       p.title,
       p.price,
       p.category_id
FROM products AS p
WHERE (p.category_id = 2 OR p.category_id = 3)
  AND p.is_active = TRUE
  AND p.price >= 3000
ORDER BY p.price DESC
LIMIT 15;

-- === Запрос 3. Предикат BETWEEN ===
SELECT p.id,
       p.title,
       p.price
FROM products AS p
WHERE p.price BETWEEN 1000 AND 5000
ORDER BY p.price
LIMIT 15;

-- === Запрос 4. Предикат IN ===
SELECT o.id,
       o.user_id,
       o.status,
       o.total_amount
FROM orders AS o
WHERE o.status IN ('paid', 'shipped', 'delivered')
ORDER BY o.created_at DESC, o.id ASC
LIMIT 15;

-- === Запрос 5. Предикат ILIKE (поиск по шаблону) ===
SELECT p.id,
       p.title,
       p.price
FROM products AS p
WHERE p.title ILIKE '%смартфон%'
ORDER BY p.price DESC
LIMIT 15;

-- === Запрос 6. IS NULL и COALESCE ===
SELECT p.id,
       p.title,
       COALESCE(p.description, 'Описание не указано') AS description
FROM products AS p
WHERE p.description IS NULL
ORDER BY p.id
LIMIT 15;

-- === Запрос 7. Сортировка по двум столбцам в разных направлениях ===
SELECT p.id,
       p.category_id,
       p.title,
       p.price
FROM products AS p
WHERE p.is_active = TRUE
ORDER BY p.category_id ASC, p.price DESC
LIMIT 15;

-- === Запрос 8. Постраничный вывод: страница 1 (LIMIT 5 OFFSET 0) ===
SELECT p.id,
       p.title,
       p.price
FROM products AS p
WHERE p.is_active = TRUE
ORDER BY p.price DESC, p.id ASC
LIMIT 5 OFFSET 0;

-- === Запрос 9. Постраничный вывод: страница 2 (LIMIT 5 OFFSET 5) ===
SELECT p.id,
       p.title,
       p.price
FROM products AS p
WHERE p.is_active = TRUE
ORDER BY p.price DESC, p.id ASC
LIMIT 5 OFFSET 5;

-- === Запрос 10. Постраничный вывод: страница 3 (LIMIT 5 OFFSET 10) ===
SELECT p.id,
       p.title,
       p.price
FROM products AS p
WHERE p.is_active = TRUE
ORDER BY p.price DESC, p.id ASC
LIMIT 5 OFFSET 10;

-- === Запрос 11. Сортировка с NULLS LAST ===
SELECT p.id,
       p.title,
       p.description
FROM products AS p
ORDER BY p.description ASC NULLS LAST, p.id
LIMIT 10;
