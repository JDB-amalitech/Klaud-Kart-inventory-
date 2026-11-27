-- Cleaning 01 · LEVEL 0 · categories (diagram load order 1 and 3: categories + sub-categories,
-- both live in this table through parent_id). Cleaned first: products depend on it.
--   9002 Promotions   was the parent of 9001 and its child: loop broken by making it top-level,
--                     which keeps 9001 Seasonal Promotions under Promotions, the natural reading
--   9003 Clearance    parent 8999 does not exist: made top-level
--   9900 Uncategorised new top-level home for products with no category (assigned in 03)
-- Rule enforced: fk_categories_parent validated.

BEGIN;

INSERT INTO categories (category_id, category_name, parent_id)
VALUES (9900, 'Uncategorised', NULL)
ON CONFLICT (category_id) DO NOTHING;

WITH fix (category_id, new_parent) AS (
    VALUES (9002, NULL::integer), (9003, NULL::integer)
), proposed AS (
    SELECT c.category_id, c.parent_id AS old_parent, f.new_parent
    FROM categories c JOIN fix f USING (category_id)
), changed AS (
    UPDATE categories t
    SET    parent_id = p.new_parent
    FROM   proposed p
    WHERE  t.category_id = p.category_id
      AND  t.parent_id IS DISTINCT FROM p.new_parent
    RETURNING p.*
)
INSERT INTO cleaning.change_log (step, table_name, row_id, column_name, old_value, new_value)
SELECT '01_categories', 'categories', category_id, 'parent_id', old_parent::text, new_parent::text FROM changed;

ALTER TABLE categories VALIDATE CONSTRAINT fk_categories_parent;

COMMIT;
