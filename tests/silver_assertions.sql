-- Silver checkpoint assertions (Checkpoint 4). assert_true raises (failing the task) on violation.
SELECT
  assert_true((SELECT COUNT(*) FROM mdp.silver.facility) BETWEEN 9900 AND 10100)            AS facility_rows_ok,   -- ~10k, no fan-out
  assert_true((SELECT max(c) FROM (SELECT facility_id, count(*) c FROM mdp.silver.facility GROUP BY facility_id)) = 1) AS facility_unique_ok,
  assert_true((SELECT COUNT(*) FROM mdp.silver.facility_claims) BETWEEN 9900 AND 10100)     AS claims_rows_ok,
  assert_true((SELECT COUNT(*) FROM mdp.silver.nfhs5_district) = 706)                       AS nfhs5_rows_ok,
  assert_true((SELECT COUNT(*) FROM mdp.silver.district_boundaries) = 735)                  AS boundaries_rows_ok,
  assert_true((SELECT max(c) FROM (SELECT pincode, count(*) c FROM mdp.silver.pincode_district GROUP BY pincode)) = 1) AS pincode_unique_ok;
