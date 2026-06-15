-- silver.facility_search: one row per facility (unique PK) carrying the free-text claim_text,
-- used as the source for the Mosaic AI Vector Search delta-sync index (mdp.silver.facility_vs_index).
-- TBLPROPERTIES: Change Data Feed is required by delta-sync indexes; deletedFileRetentionDuration
-- is extended to 30 days so TRIGGERED syncs don't fail when the sync interval exceeds the 7-day default.
CREATE OR REPLACE TABLE mdp.silver.facility_search
TBLPROPERTIES (
  delta.enableChangeDataFeed = true,
  delta.deletedFileRetentionDuration = 'interval 30 days'
) AS
SELECT
  f.facility_id, f.name, f.district_name, f.state_norm, f.latitude, f.longitude,
  f.csection_claimed, f.obstetrics_claimed, f.icu_claimed, f.blood_bank_claimed, f.emergency_claimed,
  c.claim_text
FROM mdp.silver.facility f
LEFT JOIN (SELECT facility_id, max(claim_text) AS claim_text FROM mdp.silver.facility_claims GROUP BY facility_id) c
  ON f.facility_id = c.facility_id;
