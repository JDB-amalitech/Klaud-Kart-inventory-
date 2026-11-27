-- Kloud Kart cleaning, in the load order of Diagrams/sales_erd_hierarchy.drawio:
-- every parent is cleaned and its rules enforced before any child that points at it.
--   LEVEL 0  01 categories (+ sub-categories)   02 customers
--   LEVEL 1  03 products                         04 orders
--   LEVEL 2  05 inventory_log                    06 order_items
-- Each step is its own file and can run alone, in this order.
-- Prerequisite: relationDATA/relationship.sql has been applied.
--   docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /cleaning/clean_all.sql
-- Undo everything: reload from the CSVs (docker compose down -v; docker compose up -d --wait).

\set ON_ERROR_STOP on
\pset null '(null)'

\echo '=== 00 setup'
\ir 00_setup.sql
\echo '=== LEVEL 0 · 01 categories'
\ir 01_categories.sql
\echo '=== LEVEL 0 · 02 customers'
\ir 02_customers.sql
\echo '=== LEVEL 1 · 03 products'
\ir 03_products.sql
\echo '=== LEVEL 1 · 04 orders'
\ir 04_orders.sql
\echo '=== LEVEL 2 · 05 inventory_log'
\ir 05_inventory_log.sql
\echo '=== LEVEL 2 · 06 order_items'
\ir 06_order_items.sql
