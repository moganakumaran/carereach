-- silver.facility_search: one row per facility (unique PK), source for the Vector Search index.
-- We use SELF-MANAGED embeddings: the `embedding` column is computed here in a parallel SQL batch
-- (ai_query over gte-large-en, ~minutes for 10k) instead of letting the Vector Search delta-sync
-- pipeline auto-embed serially (~1 row/s, hours). The index then just ingests these vectors.
-- embed_text is trimmed to <=1500 chars (within the model's 512-token limit). CDF + 30-day
-- deleted-file retention are required for / keep TRIGGERED delta-sync working.
CREATE OR REPLACE TABLE mdp.silver.facility_search
TBLPROPERTIES (
  delta.enableChangeDataFeed = true,
  delta.deletedFileRetentionDuration = 'interval 30 days'
) AS
WITH base AS (
  SELECT
    f.facility_id, f.name, f.district_name, f.state_norm, f.latitude, f.longitude,
    f.csection_claimed, f.obstetrics_claimed, f.icu_claimed, f.blood_bank_claimed, f.emergency_claimed,
    c.claim_text,
    coalesce(nullif(substr(c.claim_text, 1, 1500), ''), f.name, 'unknown') AS embed_text
  FROM mdp.silver.facility f
  LEFT JOIN (SELECT facility_id, max(claim_text) AS claim_text FROM mdp.silver.facility_claims GROUP BY facility_id) c
    ON f.facility_id = c.facility_id
)
SELECT *,
  CAST(ai_query('databricks-gte-large-en', embed_text) AS ARRAY<FLOAT>) AS embedding
FROM base;
