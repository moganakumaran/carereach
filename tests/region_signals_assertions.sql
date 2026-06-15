-- region_signals checkpoint assertions (Phase 5 rework). assert_true raises on violation.
SELECT
  -- No fan-out: facility grain is stable — state-level facility_count sums to gold.facility rows.
  assert_true((SELECT SUM(facility_count) FROM mdp.gold.region_signals WHERE geo_level='state')
              = (SELECT COUNT(*) FROM mdp.gold.facility))                                   AS no_fanout_ok,
  -- One row per region per level (no duplicate region_key within a level).
  assert_true((SELECT max(c) FROM (SELECT geo_level, region_key, count(*) c
                                   FROM mdp.gold.region_signals GROUP BY geo_level, region_key)) = 1) AS region_unique_ok,
  -- No NULL scores anywhere.
  assert_true((SELECT COUNT_IF(care_gap_score IS NULL OR data_confidence_score IS NULL)
               FROM mdp.gold.region_signals) = 0)                                           AS no_null_scores,
  -- Scores in [0,1].
  assert_true((SELECT COUNT_IF(care_gap_score NOT BETWEEN 0 AND 1
                            OR data_confidence_score NOT BETWEEN 0 AND 1)
               FROM mdp.gold.region_signals) = 0)                                           AS scores_in_range,
  -- KNOWN-THIN region: Araria, Bihar has 0 facilities → must be HIGH gap + LOW confidence
  -- (flagged data-poor / investigate), NOT low-gap. This is the core distinction.
  assert_true((SELECT care_gap_score >= 0.66 AND data_confidence_score < 0.45 AND facility_count = 0
               FROM mdp.gold.region_signals
               WHERE geo_level='district' AND upper(trim(state_ut))='BIHAR' AND upper(trim(region_label))='ARARIA')) AS araria_is_data_poor;
