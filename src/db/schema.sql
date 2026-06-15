-- Lakebase (Postgres) app-state schema for the Medical Desert Planner.
-- Applied by the db_migrate step against the mdp-pg instance / mdp_app database.
-- Persists planner sessions, saved scenarios, the evidence trail, and reviewer overrides.

CREATE TABLE IF NOT EXISTS sessions (
  session_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  planner      TEXT,
  title        TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS scenarios (
  scenario_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id   UUID REFERENCES sessions(session_id),
  question     TEXT NOT NULL,           -- the planner's natural-language question
  state        TEXT,                    -- e.g. 'Bihar'
  answer       JSONB,                   -- ranked districts + recommendation payload
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS evidence_trail (
  evidence_id    BIGSERIAL PRIMARY KEY,
  scenario_id    UUID REFERENCES scenarios(scenario_id),
  facility_id    TEXT,                  -- -> mdp.gold.facility.facility_id
  district_name  TEXT,
  capability     TEXT,                  -- csection|obstetrics|icu|blood_bank|emergency
  verdict        TEXT,                  -- credible|uncertain|not_credible
  confidence     DOUBLE PRECISION,
  claim_sentence TEXT,                  -- the exact source claim
  gold_ref       TEXT,                  -- pointer to the gold record used
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS reviewer_overrides (
  override_id  BIGSERIAL PRIMARY KEY,
  scenario_id  UUID REFERENCES scenarios(scenario_id),
  facility_id  TEXT,
  capability   TEXT,
  decision     TEXT,                    -- approve|reject|flag
  reviewer     TEXT,
  note         TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
