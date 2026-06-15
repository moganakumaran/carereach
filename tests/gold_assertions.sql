-- Gold checkpoint assertions (Checkpoint 5). assert_true raises (failing the task) on violation.
SELECT
  assert_true((SELECT COUNT(*) FROM mdp.gold.district_desert) = 706)                         AS desert_rows_ok,
  assert_true((SELECT COUNT_IF(desert_score IS NULL) FROM mdp.gold.district_desert) = 0)      AS no_null_desert,   -- no NULL score where district data exists
  assert_true((SELECT max(c) FROM (SELECT norm_state, norm_district, count(*) c FROM mdp.gold.district_desert GROUP BY norm_state, norm_district)) = 1) AS desert_unique_ok,  -- no fan-out
  assert_true((SELECT max(c) FROM (SELECT facility_id, count(*) c FROM mdp.gold.facility GROUP BY facility_id)) = 1) AS facility_unique_ok,
  assert_true((SELECT min(desert_score) FROM mdp.gold.district_desert) >= 0
          AND (SELECT max(desert_score) FROM mdp.gold.district_desert) <= 1)                  AS desert_in_range,
  -- coverage must use VERIFIED facilities only: verified_obstetric can never exceed total_facilities
  assert_true((SELECT COUNT_IF(verified_obstetric > total_facilities) FROM mdp.gold.district_desert) = 0) AS coverage_subset_ok;
