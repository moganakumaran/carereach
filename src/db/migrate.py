#!/usr/bin/env python3
"""Apply the Lakebase Postgres schema for CareReach.

Connects to the mdp-pg instance using a short-lived OAuth credential and applies
src/db/schema.sql (idempotent CREATE TABLE IF NOT EXISTS), then lists the tables.

Usage (credential is an OAuth token from `databricks database generate-database-credential`):
  PGHOST=<instance read_write_dns> PGDATABASE=mdp_app PGUSER=<email> PGPASSWORD=<token> \
    uv run --with psycopg2-binary python3 src/db/migrate.py src/db/schema.sql
"""
import os, sys, psycopg2

schema_path = sys.argv[1] if len(sys.argv) > 1 else "src/db/schema.sql"
sql = open(schema_path).read()

conn = psycopg2.connect(
    host=os.environ["PGHOST"], port=int(os.environ.get("PGPORT", "5432")),
    dbname=os.environ["PGDATABASE"], user=os.environ["PGUSER"],
    password=os.environ["PGPASSWORD"], sslmode="require",
)
conn.autocommit = True
with conn.cursor() as cur:
    cur.execute(sql)
    cur.execute("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY 1")
    print("tables:", [r[0] for r in cur.fetchall()])
conn.close()
