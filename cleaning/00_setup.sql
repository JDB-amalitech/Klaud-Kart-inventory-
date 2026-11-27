-- Cleaning 00: where removed rows and every change are kept. Nothing is deleted for good.
-- Prerequisite: relationDATA/relationship.sql (steps 03 and 07 validate its foreign keys).

BEGIN;

CREATE SCHEMA IF NOT EXISTS cleaning;     -- change log, review list, extract facts, helper
CREATE SCHEMA IF NOT EXISTS quarantine;   -- rows taken out of the live tables, with the reason

-- Every value changed by a cleaning step: old and new, so any change can be traced or undone.
CREATE TABLE IF NOT EXISTS cleaning.change_log (
    change_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    step        text   NOT NULL,
    table_name  text   NOT NULL,
    row_id      bigint NOT NULL,
    column_name text   NOT NULL,
    old_value   text,
    new_value   text,
    changed_at  timestamptz NOT NULL DEFAULT now()
);

-- Rows a person must decide on; the data alone cannot settle them.
CREATE TABLE IF NOT EXISTS cleaning.review (
    review_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    step       text   NOT NULL,
    table_name text   NOT NULL,
    row_id     bigint NOT NULL,
    issue      text   NOT NULL,
    detail     text,
    flagged_at timestamptz NOT NULL DEFAULT now()
);

-- Facts about the original extract, captured once. Later steps only touch rows inside these
-- bounds, so re-running a step after go-live can never quarantine real new orders.
CREATE TABLE IF NOT EXISTS cleaning.extract (
    one          boolean PRIMARY KEY DEFAULT true CHECK (one),
    extract_end  date    NOT NULL,   -- last day with a normal order volume (100+ orders)
    max_order_id integer NOT NULL,
    max_log_id   integer NOT NULL,
    captured_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO cleaning.extract (extract_end, max_order_id, max_log_id)
SELECT (SELECT max(d) FROM (SELECT order_date::date AS d FROM orders GROUP BY 1 HAVING count(*) >= 100) x),
       (SELECT max(order_id) FROM orders),
       (SELECT max(log_id) FROM inventory_log)
ON CONFLICT (one) DO NOTHING;

-- Quarantine tables: same columns as the live table, plus why, which step, and when.
-- Prefixed names, because inventory_log already has its own 'reason' column.
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['customers', 'orders', 'order_items', 'inventory_log'] LOOP
        EXECUTE format('CREATE TABLE IF NOT EXISTS quarantine.%1$I (LIKE public.%1$I)', t);
        EXECUTE format('ALTER TABLE quarantine.%I
                            ADD COLUMN IF NOT EXISTS quarantine_reason text,
                            ADD COLUMN IF NOT EXISTS quarantine_step text,
                            ADD COLUMN IF NOT EXISTS quarantined_at timestamptz DEFAULT now()', t);
    END LOOP;
END $$;

-- Move the rows matching p_where from a live table to its quarantine twin. Returns rows moved.
CREATE OR REPLACE FUNCTION cleaning.quarantine(p_table text, p_where text, p_reason text, p_step text)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE moved bigint;
BEGIN
    EXECUTE format('WITH moved AS (DELETE FROM public.%1$I WHERE %2$s RETURNING *)
                    INSERT INTO quarantine.%1$I SELECT moved.*, %3$L, %4$L, now() FROM moved',
                   p_table, p_where, p_reason, p_step);
    GET DIAGNOSTICS moved = ROW_COUNT;
    RETURN moved;
END $$;

COMMIT;

SELECT * FROM cleaning.extract;
