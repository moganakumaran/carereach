-- Bronze ingest: India Post PIN code directory (165,627 rows; grain = post office, NOT pincode).
-- Idempotent: CREATE OR REPLACE regenerates the table identically on every run.
CREATE OR REPLACE TABLE mdp.bronze.pincode AS
SELECT *
FROM databricks_virtue_foundation_dataset_dais_2026.virtue_foundation_dataset.india_post_pincode_directory;
