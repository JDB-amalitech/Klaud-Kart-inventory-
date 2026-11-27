-- Cleaning 04 · LEVEL 1 · orders (diagram load order 5). Parent customers are clean and merged (02).
-- 1. Status: 15 spellings -> 5 values (trim + lower case; 'canceled' -> 'cancelled'; 'complete' -> 'completed').
-- 2. Orders whose customer does not exist (ids 999007-999997) -> quarantined, with their lines, because
--    the foreign key refuses to orphan a line. Their stock movements show they were real sales; they can
--    be restored once the customer is identified.
-- 3. Orders dated after the extract end -> FLAGGED, not removed: their stock movements are real (ADR/0004).
-- Rules enforced: status CHECK; fk_orders_customer validated.

BEGIN;

WITH mapped AS (
    SELECT order_id,
           status AS old_status,
           CASE lower(btrim(status))
                WHEN 'canceled' THEN 'cancelled'
                WHEN 'complete' THEN 'completed'
                ELSE lower(btrim(status)) END AS new_status
    FROM orders
), changed AS (
    UPDATE orders o
    SET    status = m.new_status
    FROM   mapped m
    WHERE  o.order_id = m.order_id
      AND  o.status IS DISTINCT FROM m.new_status
    RETURNING o.order_id, m.old_status, m.new_status
)
INSERT INTO cleaning.change_log (step, table_name, row_id, column_name, old_value, new_value)
SELECT '04_orders', 'orders', order_id, 'status', old_status, new_status FROM changed;

SELECT 'lines of orders whose customer does not exist' AS quarantined,
       cleaning.quarantine('order_items',
           'order_id IN (SELECT o.order_id FROM orders o
                         WHERE NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = o.customer_id))',
           'order belongs to an unknown customer', '04_orders') AS rows;

SELECT 'orders whose customer does not exist' AS quarantined,
       cleaning.quarantine('orders',
           'NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = orders.customer_id)',
           'customer does not exist (ids 999007-999997)', '04_orders') AS rows;

DELETE FROM cleaning.review WHERE step = '04_orders';
INSERT INTO cleaning.review (step, table_name, row_id, issue, detail)
SELECT '04_orders', 'orders', o.order_id, 'dated after the extract end: confirm the date',
       'order_date ' || o.order_date || ', status ' || o.status
FROM orders o, cleaning.extract e
WHERE o.order_date::date > e.extract_end AND o.order_id <= e.max_order_id;

ALTER TABLE orders DROP CONSTRAINT IF EXISTS chk_orders_status,
    ADD CONSTRAINT chk_orders_status
        CHECK (status IN ('pending', 'shipped', 'completed', 'cancelled', 'refunded'));
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_customer;

COMMIT;

SELECT status, count(*) AS orders FROM orders GROUP BY 1 ORDER BY 2 DESC;
