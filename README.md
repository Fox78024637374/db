# Отчёт по лабораторной работе №1
**Дисциплина:** Математические основы баз данных
**Тема:** Проектирование реляционной схемы базы данных для маркетплейса

---

## 1. Цель работы

Изучение теоретических основ проектирования реляционных баз данных, освоение принципов нормализации отношений до 3-й нормальной формы (3НФ), разработка концептуальной и логической схемы базы данных для предметной области «Маркетплейс» и её физическая реализация в СУБД PostgreSQL.

---

## 2. Описание предметной области

Предметная область — электронная торговая площадка (маркетплейс), связывающая покупателей и продавцов. Система должна обеспечивать выполнение следующих функций:

* Управление пользователями и их ролями (покупатели, продавцы, администраторы);
* Ведение каталога товаров, распределённых по иерархическим категориям;
* Управление профилями магазинов (продавцов);
* Организация корзины товаров для покупателей;
* Оформление и обработка заказов, а также учёт позиций заказа;
* Фиксация платежей и статусов доставки;
* Учёт остатков товаров на складе;
* Сбор отзывов и оценок покупателей на товары.

---

## 3. Логическое проектирование и нормализация (3НФ)

В результате анализа предметной области выделено **13 сущностей**. Схема базы данных приведена к третьей нормальной форме (3НФ):

1. **1НФ:** Все атрибуты атомарны, у таблиц определены первичные ключи.
2. **2НФ:** Все неключевые атрибуты функционально полно зависят от первичного ключа. Связи «многие-ко-многим» (товары в заказах и корзинах) развязаны через промежуточные таблицы (`order_items`, `cart_items`).
3. **3НФ:** Транзитивные зависимости между неключевыми атрибутами отсутствуют.

### Список таблиц и их назначение

* `users` — учётные записи пользователей системы;
* `sellers` — профили продавцов/магазинов (связь 1:1 с `users`, `UNIQUE(user_id)`);
* `addresses` — адреса доставки пользователей (1:N с `users`);
* `categories` — **иерархический** справочник категорий (самоссылка `parent_id → categories(id)`);
* `products` — каталог товаров (FK на `sellers`, FK на `categories`);
* `stock` — учёт количества товара на складе (связь 1:1 с `products`, PK по `product_id`);
* `carts` — корзины покупателей (1:N с `users`);
* `cart_items` — товары в корзине (M:N между `carts` и `products`, PK `(cart_id, product_id)`);
* `orders` — оформленные заказы (1:N с `users`);
* `order_items` — состав заказа с фиксацией цены на момент покупки (`unit_price`, PK `(order_id, product_id)`);
* `payments` — данные об оплате заказов (1:N с `orders` — у заказа может быть несколько попыток оплаты);
* `deliveries` — сведения о доставке заказов (связь 1:1 с `orders`, `UNIQUE(order_id)`, привязка к `addresses`);
* `reviews` — отзывы покупателей на товары (один отзыв пользователя на товар, `UNIQUE(user_id, product_id)`).

---

## 4. ER-диаграмма

Физическая схема базы данных, сгенерированная в pgAdmin 4:

![ER-диаграмма базы данных](./lab_1/erd_lab1.png)

---

## 5. Физическая реализация (DDL-скрипт)

База данных реализована в **PostgreSQL 16** (укажите свою реальную версию — `SELECT version();`). Полный скрипт — в файле [`lab_1schema.sql`](./lab_1schema.sql): идемпотентный (`DROP TABLE IF EXISTS ... CASCADE` в начале), PK на `GENERATED ALWAYS AS IDENTITY`, деньги — `numeric(12,2)`, моменты времени — `timestamptz`, целостность — `FOREIGN KEY` с правилами `ON DELETE / ON UPDATE`. Ниже — ключевые фрагменты из реального скрипта:

```sql
-- Таблица пользователей
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

-- Таблица продавцов (1:1 с users)
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

-- Таблица категорий (иерархия, самоссылка)
CREATE TABLE categories (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_id  BIGINT REFERENCES categories(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    name       VARCHAR(100) NOT NULL,
    CONSTRAINT uq_categories_name UNIQUE (name)
);

-- Таблица товаров
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

-- Таблица остатков на складе (1:1 с products)
CREATE TABLE stock (
    product_id BIGINT PRIMARY KEY,
    quantity   INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_stock_product FOREIGN KEY (product_id)
        REFERENCES products(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_stock_quantity CHECK (quantity >= 0)
);

-- Таблица заказов
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

-- Позиции в заказе (с фиксацией цены покупки)
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
```

Остальные таблицы (`addresses`, `carts`, `cart_items`, `payments`, `deliveries`, `reviews`), а также индексы по внешним ключам — в полном файле [`lab_1schema.sql`](./lab_1schema.sql).

Запуск:

```bash
psql -U postgres -d marketplace -f lab_1schema.sql
```

---

## 6. Ключевые проектные решения

**Иерархия категорий (самоссылка).** Таблица `categories` ссылается сама на себя через `parent_id`. Корневые категории имеют `parent_id IS NULL`. Для обхода поддерева применяется рекурсивный запрос (`WITH RECURSIVE`).

**Связь «многие-ко-многим».** Реализована дважды через ассоциативные таблицы:
* `cart_items` — товары в корзине, PK `(cart_id, product_id)`;
* `order_items` — товары в заказе, PK `(order_id, product_id)`, с фиксацией цены покупки в `unit_price`.

**Суррогатные ключи.** Для большинства таблиц выбран `BIGINT GENERATED ALWAYS AS IDENTITY`: он стабилен, компактен и не зависит от изменений бизнес-правил. Естественные ключи применены там, где они действительно уникальны по смыслу: 1:1-связи (`stock.product_id`, `deliveries.order_id`) и ассоциативные таблицы (`cart_items`, `order_items`).

**Правила ссылочной целостности.**
* `ON DELETE RESTRICT` — защищает бизнес-значимые данные (нельзя удалить товар, если он в заказе; нельзя удалить продавца с товарами; нельзя удалить категорию с подкатегориями).
* `ON DELETE CASCADE` — удаляет технические зависимые строки (позиции заказа, платежи, склад, отзывы, корзины и т. п.).

**Типы данных.** Для денежных величин используется `NUMERIC(12,2)` (а не `FLOAT`), чтобы избежать ошибок округления. Для моментов времени — `TIMESTAMPTZ` (с часовым поясом).

---

## 7. Вывод

В ходе выполнения лабораторной работы №1 была полностью спроектирована реляционная база данных для маркетплейса. Были построены концептуальная, логическая и физическая модели данных, проведена нормализация до 3НФ, а также сформирован и успешно выполнен DDL-скрипт создания структуры в PostgreSQL. Схема содержит 13 сущностей, две связи «многие-ко-многим» через ассоциативные таблицы, иерархическую самоссылку категорий, все виды ограничений целостности (`PRIMARY KEY`, `FOREIGN KEY`, `NOT NULL`, `UNIQUE`, `CHECK`, `DEFAULT`) и правила `ON DELETE / ON UPDATE`.