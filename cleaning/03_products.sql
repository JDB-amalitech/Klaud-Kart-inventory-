-- Cleaning 03 · LEVEL 1 · products (diagram load order 4). Parent categories are clean (01).
-- 1. Uncategorised products -> 9900 Uncategorised (race_test fixtures excluded).
-- 2. Negative stock -> 0 (you cannot hold less than nothing), with a 'correction' movement in the log
--    so the trail explains the change.
-- 3. Stock that differs from the log's net movement -> listed for a physical count; neither side is guessed.
--    (The log's own orphans, cleaned in 05, belong to products that do not exist, so they cannot affect this.)
-- Rules enforced: fk_products_category validated; stock can never go below zero.

BEGIN;

WITH changed AS (
    UPDATE products
    SET    category_id = 9900
    WHERE  category_id IS NULL
      AND  product_name NOT LIKE 'RACE TEST FIXTURE%'
    RETURNING product_id
)
INSERT INTO cleaning.change_log (step, table_name, row_id, column_name, old_value, new_value)
SELECT '03_products', 'products', product_id, 'category_id', NULL, '9900' FROM changed;

WITH negative AS (
    SELECT product_id, stock_quantity FROM products WHERE stock_quantity < 0
), movement AS (
    INSERT INTO inventory_log (log_id, product_id, change_qty, reason, created_at, note)
    SELECT (SELECT max(log_id) FROM inventory_log) + row_number() OVER (ORDER BY product_id),
           product_id, -stock_quantity, 'correction', now(), 'cleaning 03: negative stock reset to 0'
    FROM negative
), reset AS (
    UPDATE products p
    SET    stock_quantity = 0
    FROM   negative n
    WHERE  p.product_id = n.product_id
    RETURNING p.product_id, n.stock_quantity AS old_stock
)
INSERT INTO cleaning.change_log (step, table_name, row_id, column_name, old_value, new_value)
SELECT '03_products', 'products', product_id, 'stock_quantity', old_stock::text, '0' FROM reset;

DELETE FROM cleaning.review WHERE step = '03_products';
INSERT INTO cleaning.review (step, table_name, row_id, issue, detail)
SELECT '03_products', 'products', p.product_id, 'stock does not match the log: count physically',
       'stock ' || p.stock_quantity || ' vs log ' || n.log_net
FROM products p
JOIN (SELECT product_id, sum(change_qty) AS log_net FROM inventory_log GROUP BY 1) n USING (product_id)
WHERE p.stock_quantity <> n.log_net;

ALTER TABLE products VALIDATE CONSTRAINT fk_products_category;
ALTER TABLE products DROP CONSTRAINT IF EXISTS chk_products_stock_nonnegative,
    ADD CONSTRAINT chk_products_stock_nonnegative CHECK (stock_quantity >= 0);

COMMIT;

SELECT (SELECT count(*) FROM cleaning.change_log WHERE step = '03_products' AND column_name = 'stock_quantity') AS negative_stock_reset,
       (SELECT count(*) FROM cleaning.review     WHERE step = '03_products') AS products_to_count;
