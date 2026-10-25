-- Synthetic sample data for docs/demo.gif. scripts/record-demo.sh runs this in an empty directory.
SELECT setseed(0.42);
COPY (
  SELECT trip_id, pickup_at, pickup_at + to_seconds(dur) AS dropoff_at, passengers, distance_mi,
         round(3 + distance_mi * 2.9 + r1 * 6, 2) AS fare_usd,
         CASE WHEN r2 < 0.2 THEN NULL ELSE round((3 + distance_mi * 2.9) * r2 * 0.25, 2) END AS tip_usd,
         payment, pickup_zone, dropoff_zone, vendor
  FROM (
    SELECT i AS trip_id,
           TIMESTAMP '2026-01-01' + to_seconds((random() * 86400 * 180)::BIGINT) AS pickup_at,
           (300 + random() * 3000)::BIGINT AS dur,
           (1 + floor(random() * 4))::TINYINT AS passengers,
           round(0.4 + random() * 18, 2) AS distance_mi,
           random() AS r1, random() AS r2,
           ['card','cash','app'][1 + floor(random() * 3)::INT] AS payment,
           ['Midtown','SoHo','Harlem','Astoria','Williamsburg','JFK Airport','LaGuardia','Chelsea','Tribeca','Flushing'][1 + floor(random() * 10)::INT] AS pickup_zone,
           ['Midtown','SoHo','Harlem','Astoria','Williamsburg','JFK Airport','LaGuardia','Chelsea','Tribeca','Flushing'][1 + floor(random() * 10)::INT] AS dropoff_zone,
           ['Yellow','Green'][1 + floor(random() * 2)::INT] AS vendor
    FROM range(1, 50001) t(i)
  )
) TO 'trips.parquet' (FORMAT parquet);
COPY (
  SELECT customer_id, first_name, last_name,
         lower(first_name || '.' || last_name || customer_id::VARCHAR || '@example.com') AS email,
         country, signup_date, lifetime_value, is_active
  FROM (
    SELECT i AS customer_id,
           ['Ada','Grace','Alan','Edsger','Barbara','Donald','Margaret','Ken','Frances','Linus','Radia','John'][1 + floor(random() * 12)::INT] AS first_name,
           ['Lovelace','Hopper','Turing','Dijkstra','Liskov','Knuth','Hamilton','Thompson','Allen','Torvalds','Perlman','Backus'][1 + floor(random() * 12)::INT] AS last_name,
           ['US','GB','DE','FR','JP','BR','CA','IN'][1 + floor(random() * 8)::INT] AS country,
           DATE '2021-01-01' + floor(random() * 1800)::INT AS signup_date,
           round(random() * random() * 5000, 2) AS lifetime_value,
           random() < 0.8 AS is_active
    FROM range(1, 2001) t(i)
  )
) TO 'customers.csv' (HEADER);
COPY (
  SELECT 'evt_' || lpad(i::VARCHAR, 6, '0') AS event_id,
         TIMESTAMP '2026-10-01' + to_seconds((random() * 86400 * 20)::BIGINT) AS ts,
         1 + floor(random() * 2000)::INT AS user_id,
         ['page_view','click','add_to_cart','checkout','search'][1 + floor(random() * 5)::INT] AS event_type,
         ['/','/products','/cart','/checkout','/search','/account'][1 + floor(random() * 6)::INT] AS page,
         (random() * 4000)::INT AS duration_ms
  FROM range(1, 5001) t(i)
) TO 'events.json' (FORMAT json);
ATTACH 'shop.duckdb' AS shop; USE shop;
CREATE TABLE products (product_id INTEGER PRIMARY KEY, name VARCHAR, category VARCHAR, price DECIMAL(10,2));
INSERT INTO products SELECT i, 'Product ' || i, ['Books','Games','Garden','Kitchen','Toys'][1 + floor(random() * 5)::INT], round(2 + random() * 200, 2) FROM range(1, 301) t(i);
CREATE TABLE customers (customer_id INTEGER PRIMARY KEY, email VARCHAR UNIQUE, country VARCHAR, signup_date DATE);
INSERT INTO customers SELECT customer_id, email, country, signup_date FROM read_csv('customers.csv');
CREATE TABLE orders (order_id INTEGER PRIMARY KEY, customer_id INTEGER REFERENCES customers(customer_id), ordered_at TIMESTAMP, status VARCHAR);
INSERT INTO orders SELECT i, 1 + floor(random() * 2000)::INT, TIMESTAMP '2025-01-01' + to_seconds((random() * 86400 * 600)::BIGINT), ['placed','shipped','delivered','returned'][1 + floor(random() * 4)::INT] FROM range(1, 12001) t(i);
CREATE TABLE order_items (order_id INTEGER, product_id INTEGER, quantity INTEGER, unit_price DECIMAL(10,2), PRIMARY KEY (order_id, product_id));
INSERT INTO order_items SELECT o, p, 1 + floor(random() * 4)::INT, round(2 + random() * 200, 2) FROM (SELECT DISTINCT 1 + floor(random() * 12000)::INT AS o, 1 + floor(random() * 300)::INT AS p FROM range(40000));
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE TABLE reviews (review_id INTEGER, product_id INTEGER, rating TINYINT, body VARCHAR);
INSERT INTO reviews SELECT i, 1 + floor(random() * 300)::INT, 1 + floor(random() * 5)::INT, ['Great','Fine','Broke in a week','Would buy again','Too small'][1 + floor(random() * 5)::INT] FROM range(1, 3001) t(i);
USE memory; DETACH shop;
LOAD avro;
COPY (SELECT * FROM 'events.json' LIMIT 2000) TO 'events.avro' (FORMAT avro);
