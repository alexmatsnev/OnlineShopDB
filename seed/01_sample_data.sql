-- =========================================================
-- 01_sample_data.sql
-- Fills the online shop database with a small, realistic set
-- of sample data for practicing queries.
--
-- Run on freshly created tables (after the schema scripts),
-- so that IDs start from 1 and the references below match:
--   psql -U alex_mav -d online_shop -f seed/01_sample_data.sql
--
-- Built-in cases for practice:
--   - customers 9 and 10 have no orders (LEFT JOIN practice)
--   - products 11 and 12 were never ordered
--   - product 11 is out of stock (stock_quantity = 0)
--   - orders cover every status, including one cancelled
--   - customer 3 has no phone, customer 7 has no address
-- =========================================================

-- Run everything as one transaction: either all data is
-- inserted, or none of it (if any statement fails).
BEGIN;

-- ---------------------------------------------------------
-- Customers (IDs 1-10)
-- ---------------------------------------------------------
INSERT INTO customers (first_name, last_name, email, phone, address, created_at) VALUES
    ('Aigerim',  'Nurlanova',   'aigerim.nurlanova@example.com', '+77010000001', 'Astana, Mangilik El 10',     '2026-01-12 10:15:00+05'),
    ('Daniyar',  'Sadykov',     'daniyar.sadykov@example.com',   '+77010000002', 'Almaty, Abay 25',            '2026-01-20 14:40:00+05'),
    ('Elena',    'Ivanova',     'elena.ivanova@example.com',     NULL,           'Karaganda, Bukhar-Zhyrau 5', '2026-02-02 09:05:00+05'),
    ('Timur',    'Akhmetov',    'timur.akhmetov@example.com',    '+77010000004', 'Astana, Kabanbay Batyr 48',  '2026-02-15 18:30:00+05'),
    ('Madina',   'Seitkali',    'madina.seitkali@example.com',   '+77010000005', 'Almaty, Dostyk 102',         '2026-03-01 11:20:00+05'),
    ('Sergey',   'Petrov',      'sergey.petrov@example.com',     '+77010000006', 'Pavlodar, Toraigyrov 64',    '2026-03-22 16:45:00+05'),
    ('Dana',     'Zhumabekova', 'dana.zhumabekova@example.com',  '+77010000007', NULL,                         '2026-04-10 20:10:00+05'),
    ('Arman',    'Kassymov',    'arman.kassymov@example.com',    '+77010000008', 'Aktobe, Abilkayir Khan 30',  '2026-05-05 08:55:00+05'),
    ('Olga',     'Kim',         'olga.kim@example.com',          '+77010000009', 'Almaty, Satpayev 17',        '2026-06-14 13:00:00+05'),
    ('Yerlan',   'Bekov',       'yerlan.bekov@example.com',      '+77010000010', 'Astana, Turan 37',           '2026-08-30 19:25:00+05');

-- ---------------------------------------------------------
-- Products (IDs 1-12), prices in tenge
-- ---------------------------------------------------------
INSERT INTO products (name, description, price, stock_quantity, created_at) VALUES
    ('Wireless mouse',              'Ergonomic 2.4 GHz mouse',           7990.00,  50, '2026-01-05 09:00:00+05'),
    ('Mechanical keyboard',         'Hot-swappable, RGB backlight',     29990.00,  20, '2026-01-05 09:00:00+05'),
    ('USB-C cable 1m',              'Fast charging cable',               2490.00, 200, '2026-01-05 09:00:00+05'),
    ('27" monitor',                 'IPS, 2560x1440, 75 Hz',           119990.00,   8, '2026-01-05 09:00:00+05'),
    ('Laptop stand',                'Adjustable aluminium stand',       12990.00,  35, '2026-01-05 09:00:00+05'),
    ('Webcam 1080p',                'Full HD webcam with microphone',   18990.00,  25, '2026-02-01 09:00:00+05'),
    ('Noise-cancelling headphones', 'Over-ear, Bluetooth 5.3',          59990.00,  15, '2026-02-01 09:00:00+05'),
    ('USB-C hub 7-in-1',            'HDMI, USB-A, SD card reader',      15990.00,  40, '2026-02-01 09:00:00+05'),
    ('Portable SSD 1TB',            'USB 3.2, up to 1050 MB/s',         44990.00,  18, '2026-03-01 09:00:00+05'),
    ('Mouse pad XL',                '900x400 mm, stitched edges',        4990.00,  60, '2026-03-01 09:00:00+05'),
    ('Wireless charger',            '15 W Qi charging pad',              9990.00,   0, '2026-05-01 09:00:00+05'),
    ('Bluetooth speaker',           'Waterproof, 12 h battery',         24990.00,  12, '2026-07-01 09:00:00+05');

-- ---------------------------------------------------------
-- Orders (IDs 1-15)
-- ---------------------------------------------------------
INSERT INTO orders (customer_id, order_date, status, shipping_address) VALUES
    (1, '2026-02-03 12:10:00+05', 'delivered', 'Astana, Mangilik El 10'),
    (2, '2026-02-14 19:45:00+05', 'delivered', 'Almaty, Abay 25'),
    (1, '2026-03-01 10:30:00+05', 'delivered', 'Astana, Mangilik El 10'),
    (3, '2026-03-18 15:20:00+05', 'cancelled', 'Karaganda, Bukhar-Zhyrau 5'),
    (4, '2026-04-05 21:05:00+05', 'delivered', 'Astana, Kabanbay Batyr 48'),
    (5, '2026-04-22 09:50:00+05', 'delivered', 'Almaty, Dostyk 102'),
    (2, '2026-05-10 17:15:00+05', 'delivered', 'Almaty, Abay 25'),
    (6, '2026-06-02 11:40:00+05', 'delivered', 'Pavlodar, Toraigyrov 64'),
    (7, '2026-06-19 22:00:00+05', 'delivered', 'Shymkent, Tauke Khan 12'),
    (1, '2026-07-07 13:25:00+05', 'delivered', 'Astana, Mangilik El 10'),
    (8, '2026-08-12 08:35:00+05', 'shipped',   'Aktobe, Abilkayir Khan 30'),
    (4, '2026-09-01 18:50:00+05', 'shipped',   'Astana, Kabanbay Batyr 48'),
    (5, '2026-09-20 14:05:00+05', 'paid',      'Almaty, Dostyk 102'),
    (6, '2026-09-28 10:45:00+05', 'paid',      'Pavlodar, Toraigyrov 64'),
    (2, '2026-10-01 20:30:00+05', 'new',       'Almaty, Abay 25');

-- ---------------------------------------------------------
-- Order items
-- unit_price is copied from the products table, so it always
-- matches the product's price at the moment of insertion.
-- ---------------------------------------------------------
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT v.order_id, v.product_id, v.quantity, p.price
FROM (VALUES
    ( 1,  1, 1), ( 1,  3, 2),
    ( 2,  4, 1),
    ( 3,  2, 1), ( 3, 10, 1),
    ( 4,  7, 1),
    ( 5,  5, 1), ( 5,  8, 1), ( 5,  3, 3),
    ( 6,  9, 1),
    ( 7,  1, 2), ( 7, 10, 2),
    ( 8,  6, 1), ( 8,  3, 1),
    ( 9,  7, 1),
    (10,  8, 1), (10,  9, 1),
    (11,  4, 1), (11,  5, 1),
    (12,  2, 1), (12,  1, 1), (12, 10, 1),
    (13,  6, 2),
    (14,  3, 5),
    (15,  7, 1), (15,  8, 1)
) AS v (order_id, product_id, quantity)
JOIN products p ON p.product_id = v.product_id;

COMMIT;
