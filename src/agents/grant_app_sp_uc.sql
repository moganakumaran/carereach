-- Unity Catalog grants the CareReach app's service principal needs to query the data layer.
-- Replace the id with your app's SP client id (databricks apps get mdp-planner -> service_principal_client_id).
-- Run on the SQL warehouse as a catalog/schema owner.
GRANT USE CATALOG ON CATALOG mdp TO `8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1`;
GRANT USE SCHEMA  ON SCHEMA  mdp.gold   TO `8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1`;
GRANT USE SCHEMA  ON SCHEMA  mdp.silver TO `8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1`;
GRANT USE SCHEMA  ON SCHEMA  mdp.bronze TO `8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1`;
GRANT SELECT      ON SCHEMA  mdp.gold   TO `8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1`;
GRANT SELECT      ON SCHEMA  mdp.silver TO `8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1`;
GRANT SELECT      ON SCHEMA  mdp.bronze TO `8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1`;
GRANT EXECUTE     ON SCHEMA  mdp.gold   TO `8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1`;  -- fn_* tools
