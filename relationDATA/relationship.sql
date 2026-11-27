-- Kloud Kart: table relationships, as drawn in Diagrams/sales_erd_hierarchy.drawio.
--   Level 0  categories, customers          (parents, load first)
--   Level 1  products, orders               (children)
--   Level 2  order_items, inventory_log     (transactions, load last)
-- The diagram's dashed orders <-> products link is left out on purpose: order_items already joins them.
--
-- Decisions (ADR/0003):
--   NOT VALID          every new insert/update is checked from now on; the orphans already in the data
--                      (ADR/0002 finding 6) are kept until a cleaning decision is recorded, then:
--                      ALTER TABLE <table> VALIDATE CONSTRAINT <name>;
--   ON DELETE RESTRICT sales history and the stock trail must never vanish because a parent row was deleted.
--   Nullable FKs       a NULL category or parent is allowed (roots, uncategorised products, race_test fixtures).
--   No FK indexes yet  added in the performance stage, so the report has a measured before/after.
--
-- Re-runnable: each constraint is dropped and recreated.
--   docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /relationDATA/relationship.sql

\set ON_ERROR_STOP on
BEGIN;

ALTER TABLE categories DROP CONSTRAINT IF EXISTS fk_categories_parent,
    ADD CONSTRAINT fk_categories_parent FOREIGN KEY (parent_id)
        REFERENCES categories (category_id) ON DELETE RESTRICT NOT VALID;

ALTER TABLE products DROP CONSTRAINT IF EXISTS fk_products_category,
    ADD CONSTRAINT fk_products_category FOREIGN KEY (category_id)
        REFERENCES categories (category_id) ON DELETE RESTRICT NOT VALID;

ALTER TABLE orders DROP CONSTRAINT IF EXISTS fk_orders_customer,
    ADD CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id)
        REFERENCES customers (customer_id) ON DELETE RESTRICT NOT VALID;

ALTER TABLE order_items DROP CONSTRAINT IF EXISTS fk_order_items_order,
    ADD CONSTRAINT fk_order_items_order FOREIGN KEY (order_id)
        REFERENCES orders (order_id) ON DELETE RESTRICT NOT VALID;

ALTER TABLE order_items DROP CONSTRAINT IF EXISTS fk_order_items_product,
    ADD CONSTRAINT fk_order_items_product FOREIGN KEY (product_id)
        REFERENCES products (product_id) ON DELETE RESTRICT NOT VALID;

ALTER TABLE inventory_log DROP CONSTRAINT IF EXISTS fk_inventory_log_product,
    ADD CONSTRAINT fk_inventory_log_product FOREIGN KEY (product_id)
        REFERENCES products (product_id) ON DELETE RESTRICT NOT VALID;

COMMIT;

-- The relationships now in place. validated = false means "enforced for new rows, old orphans not yet resolved".
SELECT conrelid::regclass  AS child_table,
       confrelid::regclass AS parent_table,
       conname             AS constraint_name,
       convalidated        AS validated
FROM pg_constraint
WHERE contype = 'f' AND connamespace = 'public'::regnamespace
ORDER BY 1::text, 2::text;
