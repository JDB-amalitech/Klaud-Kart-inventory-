-- Customers. Run via diagnosis.sql (sets read-only).

-- C1 Customer headline counts
SELECT count(*) - count(DISTINCT lower(btrim(email)))                       AS surplus_duplicate_accounts,
       count(*) FILTER (WHERE email <> btrim(email))                        AS untrimmed_emails,
       count(*) FILTER (WHERE btrim(email) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') AS invalid_after_trim,
       count(DISTINCT regexp_replace(phone, '\d', '9', 'g'))                AS phone_formats,
       count(DISTINCT city) || ' -> ' || count(DISTINCT initcap(btrim(city))) AS city_spellings,
       count(*) FILTER (WHERE full_name <> initcap(btrim(full_name)))       AS names_not_title_case
FROM customers;

-- C2 Does one person's spending sit on several accounts? Effect on the top-100 ranking.
WITH spend AS (
    SELECT c.customer_id, lower(btrim(c.email)) AS person, coalesce(sum(o.total_amount), 0) AS spent
    FROM customers c LEFT JOIN orders o USING (customer_id)
    GROUP BY 1, 2
), people AS (
    SELECT person, count(*) FILTER (WHERE spent > 0) AS accounts_with_orders, sum(spent) AS spent
    FROM spend GROUP BY 1
), top_accounts AS (SELECT person FROM spend ORDER BY spent DESC LIMIT 100),
   top_people   AS (SELECT person FROM people ORDER BY spent DESC LIMIT 100)
SELECT count(*) FILTER (WHERE accounts_with_orders > 1)               AS people_with_split_spend,
       round(sum(spent) FILTER (WHERE accounts_with_orders > 1), 2)  AS split_spend,
       (SELECT count(*) FROM top_people
        WHERE person NOT IN (SELECT person FROM top_accounts))       AS top100_changes_when_merged
FROM people;
