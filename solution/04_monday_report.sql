-- Goal 2 · THE MONDAY REPORT. For every customer: total spent, order count, monthly spend for the
-- trailing 12 months, a running per-customer total, and a top-100 ranking.
-- Decisions (one place each, so the report never contradicts itself):
--   what counts      completed + shipped orders. Cancelled and refunded never were spend; pending may
--                    still be cancelled (and is not yet fulfilled, matching when stock leaves the trail).
--   which amount     orders.total_amount, the figure of record written at checkout (ADR/0004).
--   which dates      up to the report date; future-dated orders are excluded until confirmed.
--   12 months        the 12 calendar months ending with the report date's month, oldest first.
--   running total    per customer, in order-date order, ties broken by order_id (ROWS, not RANGE), so
--                    two orders at the same instant still show two steps, as Adwoa's sheet does.
--   ranking          RANK(): customers tied on spend share a place, so the top 100 may list a few more
--                    than 100 rather than drop someone who spent exactly as much.
-- Built as plain views over one pass of the orders: measured fast enough that a stored copy
-- (materialized view) and its staleness were not worth it (performance/README.md, ADR/0006).

-- The single definition of a counted order. Every report figure reads from here, so they all agree.
CREATE OR REPLACE VIEW v_report_orders AS
SELECT o.order_id, o.customer_id, o.order_date, o.total_amount
FROM orders o
WHERE o.status IN ('completed', 'shipped')
  AND o.order_date <= now();          -- future-dated orders wait until their date is confirmed

-- Per customer, as of any date (default today).
CREATE OR REPLACE FUNCTION monday_report(p_as_of date DEFAULT current_date)
RETURNS TABLE (customer_id integer, full_name text, email text, city text,
               total_spent numeric, order_count bigint, monthly_spend_12m numeric[],
               trailing_12m_spend numeric, spend_rank bigint)
LANGUAGE sql STABLE AS $$
    WITH counted AS (
        SELECT * FROM v_report_orders WHERE order_date < p_as_of + 1
    ), months AS (
        SELECT generate_series(date_trunc('month', p_as_of) - interval '11 months',
                               date_trunc('month', p_as_of), interval '1 month')::date AS month
    ), per_customer AS (
        SELECT customer_id, sum(total_amount) AS total_spent, count(*) AS order_count
        FROM counted GROUP BY customer_id
    ), per_month AS (
        SELECT customer_id, date_trunc('month', order_date)::date AS month, sum(total_amount) AS spend
        FROM counted
        WHERE order_date >= date_trunc('month', p_as_of) - interval '11 months'
        GROUP BY 1, 2
    ), monthly AS (            -- 12 values per active customer, zero-filled, oldest month first
        SELECT a.customer_id, array_agg(coalesce(pm.spend, 0) ORDER BY m.month) AS monthly_spend_12m
        FROM (SELECT DISTINCT customer_id FROM per_month) a
        CROSS JOIN months m
        LEFT JOIN per_month pm ON pm.customer_id = a.customer_id AND pm.month = m.month
        GROUP BY a.customer_id
    )
    SELECT c.customer_id, c.full_name, c.email, c.city,
           coalesce(pc.total_spent, 0),
           coalesce(pc.order_count, 0),
           coalesce(mo.monthly_spend_12m, array_fill(0::numeric, ARRAY[12])),
           coalesce((SELECT sum(x) FROM unnest(mo.monthly_spend_12m) x), 0),
           rank() OVER (ORDER BY coalesce(pc.total_spent, 0) DESC)
    FROM customers c
    LEFT JOIN per_customer pc ON pc.customer_id = c.customer_id
    LEFT JOIN monthly      mo ON mo.customer_id = c.customer_id;
$$;

CREATE OR REPLACE VIEW v_monday_report AS
SELECT * FROM monday_report();

CREATE OR REPLACE VIEW v_top_100_customers AS
SELECT * FROM monday_report() WHERE spend_rank <= 100 ORDER BY spend_rank, customer_id;

-- The running total Adwoa keeps by hand: one row per counted order.
CREATE OR REPLACE VIEW v_customer_running_total AS
SELECT customer_id, order_id, order_date, total_amount,
       sum(total_amount) OVER (PARTITION BY customer_id ORDER BY order_date, order_id
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM v_report_orders;

COMMENT ON FUNCTION monday_report(date) IS
    'Monday customer-spending report as of a date. monthly_spend_12m = 12 months ending with that month, oldest first.';
