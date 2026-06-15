-- Bronze ingest: NFHS-5 district health indicators (706 districts, 109 cols).
-- Idempotent: CREATE OR REPLACE regenerates the table identically on every run.
-- Note: many *_pct columns are typed string because of suppressed ('*') / small-sample
-- ('(n)') values in the source; cleaning to NULL happens in silver, not here.
CREATE OR REPLACE TABLE mdp.bronze.nfhs5 AS
SELECT *
FROM databricks_virtue_foundation_dataset_dais_2026.virtue_foundation_dataset.nfhs_5_district_health_indicators;
