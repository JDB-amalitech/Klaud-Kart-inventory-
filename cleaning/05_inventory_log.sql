-- Cleaning 05 · LEVEL 2 · inventory_log (diagram load order 6). Parent products are clean (03).
-- 1. Movements for products that do not exist (99xxx ids) -> quarantined.
-- 2. Movements dated after the extract end -> FLAGGED, not removed: for 39 products stock only matches
--    the log with them kept, so they are real movements with a wrong date (ADR/0004).
-- Rule enforced: fk_inventory_log_product validated.

BEGIN;

SELECT 'stock movements whose product does not exist' AS quarantined,
       cleaning.quarantine('inventory_log',
           'NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = inventory_log.product_id)',
           'product does not exist', '05_inventory_log') AS rows;

DELETE FROM cleaning.review WHERE step = '05_inventory_log';
INSERT INTO cleaning.review (step, table_name, row_id, issue, detail)
SELECT '05_inventory_log', 'inventory_log', l.log_id, 'dated after the extract end: confirm the date',
       'created_at ' || l.created_at || ', ' || l.reason || ' ' || l.change_qty || ' of product ' || l.product_id
FROM inventory_log l, cleaning.extract e
WHERE l.created_at::date > e.extract_end AND l.log_id <= e.max_log_id;

ALTER TABLE inventory_log VALIDATE CONSTRAINT fk_inventory_log_product;

COMMIT;

SELECT count(*) AS movements_to_confirm FROM cleaning.review WHERE step = '05_inventory_log';
