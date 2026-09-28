-- A satellite should never store the same (hash key, hashdiff) pair twice.
-- Catches duplicate inserts from re-runs, duplicate files in the landing zone,
-- or a broken incremental filter.
--
-- Caveat: a genuine A -> B -> A change history would also repeat a hashdiff
-- and trip this test. TPC-H data never does that, so here it only flags bugs.

SELECT 'sat_order_details' AS SATELLITE, ORDER_HK AS HK, ORDER_HASHDIFF AS HASHDIFF, COUNT(*) AS N
FROM {{ ref('sat_order_details') }}
GROUP BY 1, 2, 3
HAVING COUNT(*) > 1

UNION ALL

SELECT 'sat_customer_details', CUSTOMER_HK, CUSTOMER_HASHDIFF, COUNT(*)
FROM {{ ref('sat_customer_details') }}
GROUP BY 1, 2, 3
HAVING COUNT(*) > 1
