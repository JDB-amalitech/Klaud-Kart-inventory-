-- Goal 1 · NO OVERSELLING. The contract race_test.py calls: place_order(customer, product, quantity).
--
-- How two buyers for the last unit are serialised:
--   One conditional UPDATE does the check and the decrement together:
--       UPDATE products SET stock = stock - q WHERE product_id = p AND stock >= q
--   The first buyer's UPDATE locks the row. The second waits on that lock; when the first commits,
--   PostgreSQL re-checks the second buyer's WHERE against the NEW stock (Read Committed re-evaluation),
--   finds it no longer true, updates nothing, and that buyer gets an instant "Out of stock".
--   No read-then-write gap exists, so there is nothing to race. No serialization errors can occur, so
--   there is nothing to retry and no error ever reaches the caller.
--
-- Same unit of work: stock decrement, order, order line and the sale movement (with its order_id) commit
-- together or not at all. The CHECK (stock_quantity >= 0) from the schema upgrade is the safety net.
--
-- Flash sale (400 buyers, one product): buyers queue first come, first served on a per-product advisory
-- lock, then take the row lock for one short transaction (no network calls inside). Once stock is gone,
-- later buyers are refused from a plain read without queueing. lock_timeout caps any wait at 5 s and turns
-- it into a clear "try again" answer instead of a spinner or an error.
-- Rejected: triggers alone, SERIALIZABLE + retry, SELECT ... FOR UPDATE then UPDATE, SKIP LOCKED (ADR/0006).

CREATE OR REPLACE FUNCTION place_order(p_customer_id bigint, p_product_id bigint, p_quantity integer)
RETURNS TABLE (success boolean, order_id bigint, message text)
LANGUAGE plpgsql
SET lock_timeout = '5s'
AS $$
#variable_conflict use_column
DECLARE
    v_price    numeric(12,2);
    v_order_id bigint;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RETURN QUERY SELECT false, NULL::bigint, 'Quantity must be at least 1.';
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = p_customer_id) THEN
        RETURN QUERY SELECT false, NULL::bigint, 'Unknown customer.';
        RETURN;
    END IF;

    -- Fast refusal: once stock is gone, later buyers are told at once instead of queueing on the row lock.
    -- A plain read, no lock. It can only ever let a buyer through to the UPDATE below, which decides;
    -- it can never sell stock that is not there.
    IF (SELECT p.stock_quantity FROM products p WHERE p.product_id = p_product_id) < p_quantity THEN
        RETURN QUERY SELECT false, NULL::bigint, 'Out of stock.';
        RETURN;
    END IF;

    -- Queue, then check and take the stock in one statement.
    -- The advisory lock (namespace 1001 = "stock queue", key = product) makes buyers of one product take
    -- turns strictly first come, first served, waking only the next in line. Measured on a 400-buyer flash
    -- sale: 33% less time per call than queueing on the row lock alone (ADR/0006). It is queue discipline
    -- only: the conditional UPDATE is still what guarantees no overselling, even for a writer that skips it.
    PERFORM set_config('kloudkart.movement_logged', 'on', true);
    BEGIN
        PERFORM pg_advisory_xact_lock(1001, p_product_id::integer);
        UPDATE products p
        SET    stock_quantity = p.stock_quantity - p_quantity
        WHERE  p.product_id = p_product_id
          AND  p.stock_quantity >= p_quantity
        RETURNING p.price INTO v_price;
    EXCEPTION WHEN lock_not_available THEN
        PERFORM set_config('kloudkart.movement_logged', 'off', true);
        RETURN QUERY SELECT false, NULL::bigint, 'Too many buyers right now, please try again.';
        RETURN;
    END;
    PERFORM set_config('kloudkart.movement_logged', 'off', true);

    IF v_price IS NULL THEN
        IF EXISTS (SELECT 1 FROM products p WHERE p.product_id = p_product_id) THEN
            RETURN QUERY SELECT false, NULL::bigint, 'Out of stock.';
        ELSE
            RETURN QUERY SELECT false, NULL::bigint, 'Unknown product.';
        END IF;
        RETURN;
    END IF;

    INSERT INTO orders (customer_id, order_date, status, total_amount)
    VALUES (p_customer_id, now(), 'pending', v_price * p_quantity)
    RETURNING orders.order_id INTO v_order_id;

    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, p_product_id, p_quantity, v_price);

    INSERT INTO inventory_log (product_id, change_qty, reason, order_id)
    VALUES (p_product_id, -p_quantity, 'sale', v_order_id);

    RETURN QUERY SELECT true, v_order_id, 'Order placed.';
END $$;

COMMENT ON FUNCTION place_order(bigint, bigint, integer) IS
    'The only way to sell stock. Exactly one buyer gets the last unit; others get "Out of stock." Writes order, line and sale movement together.';
