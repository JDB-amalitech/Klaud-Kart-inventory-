-- Cleaning 02 · LEVEL 0 · customers (diagram load order 2). Cleaned before orders, which point at it.
-- 1. Text: email trim + lower case; full_name trim + single spaces (casing left as entered: cosmetic);
--    city trim + Title Case ('Accra', 'accra', 'ACCRA', 'Accra ' -> 'Accra'). Must come before the
--    merge, or duplicates stay hidden behind spaces and capitals.
-- 2. Merge: same email AND same name -> the earliest-registered account; its orders follow it;
--    duplicate accounts are quarantined. All 533 duplicate-email groups share a name.
-- Rule enforced: unique index on email.

BEGIN;

WITH proposed AS (
    SELECT customer_id, email, full_name, city,
           lower(btrim(email))                               AS new_email,
           regexp_replace(btrim(full_name), '\s+', ' ', 'g') AS new_name,
           initcap(btrim(city))                              AS new_city
    FROM customers
), changed AS (
    UPDATE customers t
    SET    email = p.new_email, full_name = p.new_name, city = p.new_city
    FROM   proposed p
    WHERE  t.customer_id = p.customer_id
      AND  (t.email, t.full_name, t.city) IS DISTINCT FROM (p.new_email, p.new_name, p.new_city)
    RETURNING p.*
)
INSERT INTO cleaning.change_log (step, table_name, row_id, column_name, old_value, new_value)
SELECT '02_customers', 'customers', c.customer_id, v.column_name, v.old_value, v.new_value
FROM changed c,
     LATERAL (VALUES ('email',     c.email,     c.new_email),
                     ('full_name', c.full_name, c.new_name),
                     ('city',      c.city,      c.new_city)) v(column_name, old_value, new_value)
WHERE v.old_value IS DISTINCT FROM v.new_value;

CREATE TEMP TABLE merge_map ON COMMIT DROP AS
SELECT customer_id AS duplicate_id, survivor_id
FROM (SELECT customer_id,
             first_value(customer_id) OVER (PARTITION BY email, lower(full_name)
                                            ORDER BY registered_at, customer_id) AS survivor_id
      FROM customers) x
WHERE customer_id <> survivor_id;

WITH moved AS (
    UPDATE orders o
    SET    customer_id = m.survivor_id
    FROM   merge_map m
    WHERE  o.customer_id = m.duplicate_id
    RETURNING o.order_id, m.duplicate_id, m.survivor_id
)
INSERT INTO cleaning.change_log (step, table_name, row_id, column_name, old_value, new_value)
SELECT '02_customers', 'orders', order_id, 'customer_id', duplicate_id::text, survivor_id::text FROM moved
UNION ALL
SELECT '02_customers', 'customers', duplicate_id, 'merged_into', NULL, survivor_id::text FROM merge_map;

SELECT 'duplicate accounts (orders moved to survivor)' AS quarantined,
       cleaning.quarantine('customers', 'customer_id IN (SELECT duplicate_id FROM merge_map)',
           'merged into the earliest account with the same email and name', '02_customers') AS rows;

CREATE UNIQUE INDEX IF NOT EXISTS ux_customers_email ON customers (lower(btrim(email)));

COMMIT;
