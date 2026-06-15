-- Provision the Databricks App's service principal as a Lakebase Postgres role so the in-app
-- "Save scenario" can authenticate (OAuth token -> Postgres role by name) and write app tables.
-- Run as the instance OWNER against mdp-pg / mdp_app (see src/db/migrate.py for connection):
--   PGHOST=<read_write_dns> PGDATABASE=mdp_app PGUSER=<owner email> PGPASSWORD=<owner token> \
--     uv run --with psycopg2-binary python3 src/db/migrate.py src/db/grant_app_sp.sql
-- Replace the id below with your app's service principal client id (databricks apps get <app>).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1') THEN
    CREATE ROLE "8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1" WITH LOGIN;
  END IF;
END $$;
GRANT USAGE ON SCHEMA public TO "8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO "8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO "8bfb7c6e-3315-4ce8-8fca-3926bfb2c7b1";
