-- Bronze ingest: raw copy of Virtue Foundation facilities (51 cols, ~10k rows).
-- Idempotent: CREATE OR REPLACE regenerates the table identically on every run.
-- Raw landing only — no filtering/typing here (that is silver's job).
CREATE OR REPLACE TABLE mdp.bronze.facilities AS
SELECT *
FROM databricks_virtue_foundation_dataset_dais_2026.virtue_foundation_dataset.facilities;
