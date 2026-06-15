-- Bronze checkpoint assertions (Checkpoint 3).
-- assert_true(expr) returns NULL when true and RAISES (failing the SQL task) when false,
-- so this doubles as the bronze_ingest job's validation gate and a standalone test.
SELECT
  assert_true((SELECT COUNT(*) FROM mdp.bronze.facilities) BETWEEN 9900 AND 10200) AS facilities_rows_ok,   -- ~10,000
  assert_true((SELECT COUNT(*) FROM mdp.bronze.pincode)  = 165627)                  AS pincode_rows_ok,
  assert_true((SELECT COUNT(*) FROM mdp.bronze.nfhs5)    = 706)                     AS nfhs5_rows_ok,
  assert_true((SELECT COUNT(*) FROM mdp.information_schema.columns
                WHERE table_schema='bronze' AND table_name='facilities') = 51)      AS facilities_cols_ok,
  assert_true((SELECT COUNT(*) FROM mdp.information_schema.columns
                WHERE table_schema='bronze' AND table_name='nfhs5') = 109)          AS nfhs5_cols_ok,
  assert_true((SELECT COUNT(*) FROM mdp.information_schema.columns
                WHERE table_schema='bronze' AND table_name='pincode') = 11)         AS pincode_cols_ok,
  assert_true((SELECT COUNT_IF(unique_id IS NULL) FROM mdp.bronze.facilities) = 0)  AS facilities_key_ok,
  assert_true((SELECT COUNT_IF(pincode IS NULL)   FROM mdp.bronze.pincode)   = 0)   AS pincode_key_ok,
  assert_true((SELECT COUNT_IF(district_name IS NULL) FROM mdp.bronze.nfhs5) = 0)   AS nfhs5_key_ok;
