-- Point-in-time table for customers.
-- For every customer and every as-of date it stores which satellite row was
-- current at that moment (the sat's hash key + LOAD_DATETIME). Downstream
-- queries can then equi-join to the satellite for "state as of date X"
-- instead of running a range join / window function every time.
-- With one satellite it mostly shows the pattern; its value grows with each
-- satellite added to the hub (one pointer pair per satellite).
--
-- Hand-written rather than automate_dv.pit(): AutomateDV deprecated pit() and
-- bridge() in v0.11.0 ("not currently fit-for-purpose"). Rebuilt in full each
-- run; it's small and deterministic.
-- Pointers are NULL when the customer had no satellite row yet at that date.

{{ config(materialized='table') }}

WITH spine AS (

    SELECT h.CUSTOMER_HK, d.AS_OF_DATE
    FROM {{ ref('hub_customer') }} h
    CROSS JOIN {{ ref('as_of_dates') }} d

)

SELECT
    spine.CUSTOMER_HK
  , spine.AS_OF_DATE
  , s.CUSTOMER_HK       AS SAT_CUSTOMER_DETAILS_PK
  , s.LOAD_DATETIME     AS SAT_CUSTOMER_DETAILS_LDTS
FROM spine
LEFT JOIN {{ ref('sat_customer_details') }} s
    ON  s.CUSTOMER_HK   = spine.CUSTOMER_HK
    AND s.LOAD_DATETIME <= spine.AS_OF_DATE
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY spine.CUSTOMER_HK, spine.AS_OF_DATE
    ORDER BY s.LOAD_DATETIME DESC NULLS LAST
) = 1
