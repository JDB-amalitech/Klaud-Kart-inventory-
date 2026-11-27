-- Cleaning 06 · LEVEL 2 · order_items (diagram load order 7, last). Parents orders (04) and products (03) are clean.
-- 1. Lines whose order does not exist -> quarantined.
-- 2. 999 / 9999 quantities (normal maximum is 10) -> quarantined; an order left with no line goes with them.
-- 3. Exact duplicate lines -> quarantined ONLY where the order's stored total proves the copy was a double
--    entry (total = lines minus the copies). Where the total already counts both lines it was a genuine
--    repeat purchase and is kept.
-- 4. Null / zero price lines -> flagged; a price is not guessed.
-- 5. Order totals still differing from their lines -> flagged. orders.total_amount (written at checkout)
--    is the figure of record and is never overwritten.
-- Rules enforced: fk_order_items_order and fk_order_items_product validated; quantity must be positive.

BEGIN;

SELECT 'lines whose order does not exist' AS quarantined,
       cleaning.quarantine('order_items',
           'NOT EXISTS (SELECT 1 FROM orders o WHERE o.order_id = order_items.order_id)',
           'order does not exist', '06_order_items') AS rows;

SELECT 'lines with a quantity of 999 or more' AS quarantined,
       cleaning.quarantine('order_items', 'quantity >= 999',
           'extreme quantity (normal maximum is 10)', '06_order_items') AS rows;

SELECT 'orders left with no lines' AS quarantined,
       cleaning.quarantine('orders',
           'NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = orders.order_id)',
           'no lines left after extreme-quantity lines were removed', '06_order_items') AS rows;

SELECT 'duplicate lines proven to be double entries' AS quarantined,
       cleaning.quarantine('order_items',
           'order_item_id IN (
                WITH copies AS (
                    SELECT order_item_id, order_id, quantity * unit_price AS line_value
                    FROM (SELECT oi.*, row_number() OVER (PARTITION BY order_id, product_id, quantity, unit_price
                                                          ORDER BY order_item_id) AS copy_no
                          FROM order_items oi) d
                    WHERE copy_no > 1
                ), proven AS (
                    SELECT c.order_id
                    FROM copies c
                    JOIN orders o USING (order_id)
                    JOIN (SELECT order_id, sum(quantity * unit_price) AS items FROM order_items GROUP BY 1) t USING (order_id)
                    GROUP BY c.order_id, o.total_amount, t.items
                    HAVING abs(t.items - coalesce(sum(c.line_value), 0) - o.total_amount) <= 0.01
                )
                SELECT order_item_id FROM copies WHERE order_id IN (SELECT order_id FROM proven))',
           'duplicate line; order total proves it was entered twice', '06_order_items') AS rows;

DELETE FROM cleaning.review WHERE step = '06_order_items';
INSERT INTO cleaning.review (step, table_name, row_id, issue, detail)
SELECT '06_order_items', 'order_items', order_item_id,
       'unit_price is ' || coalesce(unit_price::text, 'null'),
       'order ' || order_id || ', product ' || product_id || ', quantity ' || quantity
FROM order_items
WHERE coalesce(unit_price, 0) = 0
UNION ALL
SELECT '06_order_items', 'orders', o.order_id,
       CASE WHEN bool_or(coalesce(oi.unit_price, 0) = 0) THEN 'total differs: line with no price'
            ELSE 'total differs: no visible cause' END,
       'total_amount ' || o.total_amount || ' vs lines ' || coalesce(sum(oi.quantity * oi.unit_price), 0)
FROM orders o
JOIN order_items oi USING (order_id)
GROUP BY o.order_id, o.total_amount
HAVING abs(o.total_amount - coalesce(sum(oi.quantity * oi.unit_price), 0)) > 0.01;

ALTER TABLE order_items VALIDATE CONSTRAINT fk_order_items_order;
ALTER TABLE order_items VALIDATE CONSTRAINT fk_order_items_product;
ALTER TABLE order_items DROP CONSTRAINT IF EXISTS chk_order_items_quantity,
    ADD CONSTRAINT chk_order_items_quantity CHECK (quantity > 0);

COMMIT;

SELECT table_name, issue, count(*) AS to_review
FROM cleaning.review WHERE step = '06_order_items' GROUP BY 1, 2 ORDER BY 1, 2;
