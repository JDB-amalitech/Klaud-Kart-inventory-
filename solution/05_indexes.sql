-- Indexes, each chosen from a measured plan (performance/README.md). Added last so every query has a
-- before/after. Each costs a little on every insert; place_order inserts one row into each of orders,
-- order_items and inventory_log per sale, so these are kept to the ones that pay for themselves.

-- One customer's orders in date order: running total and per-customer lookups read only that customer.
-- INCLUDE lets those reads answer from the index without visiting the table.
CREATE INDEX IF NOT EXISTS ix_orders_customer_date
    ON orders (customer_id, order_date, order_id) INCLUDE (total_amount, status);

-- One product's movements in time order: the auditor's trail for a product.
CREATE INDEX IF NOT EXISTS ix_inventory_log_product_time
    ON inventory_log (product_id, created_at, log_id);

-- Foreign-key columns PostgreSQL does not index on its own: joins from orders to lines, and the key
-- checks when an order or product is deleted (race_test.py cleanup) would otherwise scan 335k lines.
CREATE INDEX IF NOT EXISTS ix_order_items_order   ON order_items (order_id);
CREATE INDEX IF NOT EXISTS ix_order_items_product ON order_items (product_id);

ANALYZE orders;
ANALYZE order_items;
ANALYZE inventory_log;
