# Medical Desert Planner — CLI Build Runbook

A phase-by-phase build plan driven from the Databricks CLI, designed so each phase ends with a **checkpoint gate** you must pass before moving on. Build the boring spine first (ingest → spatial → gold → Genie), prove it works, then layer on the agents and the app.

> Golden rule: never start a phase until the previous checkpoint is green. If a checkpoint fails, fix it before adding scope. This is what keeps a 2-day hackathon from collapsing at hour 20.

---

## Repo layout (target)

```
medical-desert-planner/
├── databricks.yml              # bundle root (Declarative Automation Bundle)
├── AGENTS.md                   # context for AI coding assistants
├── .claude/skills/             # agent skills for Claude Code / Cursor
├── resources/
│   ├── catalog.yml             # UC catalog, schema, volume
│   ├── jobs.yml                # bronze/silver/gold pipelines
│   ├── lakebase.yml            # postgres_project / branch / endpoint
│   └── app.yml                 # Databricks App resource
├── src/
│   ├── pipelines/              # ingest + transforms (Lakeflow / PySpark)
│   ├── agents/                 # ResponsesAgent code, UC functions
│   └── app/                    # Streamlit/FastAPI UI
└── tests/                      # validation queries + eval sets
```

---

## Phase 0 — Toolchain and auth

**Goal:** a working CLI that can see your workspace and supports Lakebase-in-bundles.

```bash
# Install / upgrade CLI — need >= 0.287.0 for Lakebase bundle resources
databricks -v

# Python 3.11+ and the uv package manager (Apps + agent templates use uv)
python3 --version
uv --version

# Authenticate (creates a profile)
databricks auth login --host https://<your-workspace-host>
```

**Checkpoint 0 — must all pass:**
- `databricks -v` reports **0.287.0 or higher**.
- `databricks current-user me` returns your identity.
- `databricks bundle schema > /dev/null` runs without error (schema is reachable).
- Python ≥ 3.11 and `uv` present.

---

## Phase 1 — Scaffold the bundle

**Goal:** an empty but deployable Declarative Automation Bundle in source control.

```bash
# Start from a template (default-minimal is the smallest viable bundle)
databricks bundle init

git init && git add -A && git commit -m "scaffold bundle"

# Validate before deploying anything
databricks bundle validate -t dev

# Deploy the empty/hello resource to confirm the round-trip works
databricks bundle deploy -t dev
```

**Checkpoint 1:**
- `databricks bundle validate -t dev` returns no errors.
- `databricks bundle deploy -t dev` succeeds and the resource appears in the workspace.
- Repo is committed (judges reproduce from a clean clone — start clean now).

---

## Phase 2 — Unity Catalog scaffolding (governance first)

**Goal:** a governed home for every table, function, and volume. Governance before data.

Define in `resources/catalog.yml`: a catalog (e.g. `mdp`), schemas (`bronze`, `silver`, `gold`, `ops`), and a Volume for raw files. Deploy via the bundle, or bootstrap with SQL:

```bash
databricks bundle deploy -t dev
# or, quick bootstrap:
databricks sql query "CREATE CATALOG IF NOT EXISTS mdp"
```

**Checkpoint 2:**
- Catalog and all four schemas exist (`databricks schemas list mdp`).
- Volume exists and is writable.
- A teammate (second identity) can read the catalog — confirms grants work.

---

## Phase 3 — Bronze ingest (data foundation)

**Goal:** all three raw datasets landed as Delta tables with verified row counts.

```bash
# Upload raw files into the UC Volume
databricks fs cp ./data/facilities_10k.csv          dbfs:/Volumes/mdp/bronze/raw/
databricks fs cp ./data/india_post_pincode.csv      dbfs:/Volumes/mdp/bronze/raw/
databricks fs cp ./data/nfhs5_district.csv          dbfs:/Volumes/mdp/bronze/raw/

# Run the bronze ingest job defined in resources/jobs.yml
databricks bundle run bronze_ingest -t dev
```

**Checkpoint 3 — row-count assertions (write these as SQL tests in `tests/`):**
- `mdp.bronze.facilities` ≈ **10,000** rows, **51** columns.
- `mdp.bronze.pincode` = **165,627** rows.
- `mdp.bronze.nfhs5` = **706** rows.
- No fully-null rows; ingestion job is idempotent (re-run gives same counts).

---

## Phase 4 — Silver: structure, extract, spatialise

**Goal:** turn noisy free text into typed claims with confidence, and attach every facility to a district.

Key transforms (in `src/pipelines/`):
- **AI extraction** — use `ai_query` / `ai_extract` to pull structured capability flags (`does_csection`, `has_icu`, `obstetric_services`, …) from `description`, `capability`, `equipment`, each with a confidence score. Treat these as **claims**, not facts.
- **Vector Search index** over the free-text fields for semantic claim matching.
- **Enrichment cleaning** — deduplicate `pincode` → district before any join (row grain is post office, not PIN); snake_case NFHS columns; map `*` to NULL (never 0); flag parenthesised small-sample estimates as low-confidence.
- **Spatial join** — `ST_Point(lon, lat)` + `ST_Contains(district_polygon, point)` to assign each facility to a district; flag rows with missing coordinates as `geo_inferred = true`.

```bash
databricks bundle run silver_transform -t dev
```

**Checkpoint 4:**
- **Extraction quality:** hand-label 30 random facilities; extracted capability flags agree ≥ ~80% of the time. If not, fix the prompt before proceeding.
- **No fan-out:** silver facility row count still ≈ 10,000 after the PIN/NFHS joins (cardinality check — fan-out here is the classic failure).
- **Geocoding coverage:** report `% geo_inferred`; confirm inferred rows are flagged, not dropped.
- **Vector index** status is ONLINE and returns sensible neighbours for a test query.

---

## Phase 5 — Gold: unified facility + district desert score

**Goal:** decision-ready tables the agents and app read directly.

- `mdp.gold.facility` — one row per facility with verified capability flags, confidence, and an evidence pointer (source record + claim sentence).
- `mdp.gold.district_desert` — one row per district: composite **desert score** = f(verified coverage, NFHS-5 burden, accessibility proxy). Document the formula in the README.

Add data-quality expectations (Lakeflow expectations or `tests/` SQL) so bad data fails loudly.

```bash
databricks bundle run gold_build -t dev
```

**Checkpoint 5:**
- **Face validity:** known high-burden districts rank in the worst desert-score quartile. Eyeball 5 against NFHS-5 reality.
- **Coverage uses verified facilities only** — a facility that can't credibly do C-sections does not count toward maternal coverage.
- DQ expectations pass; no NULL desert scores for districts with data.

---

## Phase 6 — Agents (Agent Bricks Supervisor + specialists)

**Goal:** the agentic core, logged and evaluated in MLflow, governed by Unity Catalog.

Build order (each is a checkpoint in itself):

1. **Genie Space** over `mdp.gold.*` — confirm it answers count questions in natural language.
2. **Geo/score tools** — register the spatial + scoring logic as **Unity Catalog functions** the agent can call.
3. **Capability-verification agent** — author with the **MLflow ResponsesAgent** interface (OpenAI Agents SDK or LangGraph under the hood); uses Vector Search + AI classification; returns a credibility judgement + confidence. Log + register in UC.
4. **Supervisor Agent (Agent Bricks)** — connect Genie + the custom agent + the UC functions + **Foundation Model API web search** + **MCP** enrichment. No hard-coded routing.

```bash
# Install agent SDKs (>= these versions)
uv pip install "mlflow>=3.1.3" "databricks-agents>=1.1.0" databricks-sdk

# After logging/registering the agent in UC, deploy it.
# Preferred for new builds: deploy the agent on Databricks Apps (Phase 8).
# Interim option: deploy to Model Serving for quick endpoint testing.
```

**Checkpoint 6:**
- **MLflow eval** on a golden set of ~15 planner Q&A pairs meets your bar (define a pass threshold up front).
- **Trace inspection:** for "where to deploy a maternal unit in Bihar?", the trace shows the supervisor calling Genie + geo tools + verification agent in a sensible order.
- **Verification precision:** spot-check 20 claim judgements; false-positive rate is acceptably low (this is the safety-critical part).
- Every agent and function is registered in Unity Catalog with correct grants.

---

## Phase 7 — Lakebase (state and persistence)

**Goal:** planners' work survives restarts; the agent has memory.

Define in `resources/lakebase.yml` a `postgres_project`, a `postgres_branch`, and a `postgres_endpoint`. Create tables for `sessions`, `scenarios`, `evidence_trail`, and `reviewer_overrides`.

```bash
databricks bundle deploy -t dev      # provisions the Lakebase resources
databricks bundle run db_migrate -t dev   # applies the table DDL
```

**Checkpoint 7:**
- Write a scenario, then read it back — round-trips correctly.
- Restart the app/session; the saved scenario is still retrievable (persistence proven).
- Evidence trail row links back to the exact gold-table records used.

---

## Phase 8 — Databricks App (the UI) and end-to-end wiring

**Goal:** the planner experience, connecting UI → supervisor agent → Lakebase → gold tables.

App (Streamlit or FastAPI in `src/app/`) needs: a district choropleth shaded by desert score, a chat panel routed to the supervisor, an evidence drawer (source + claim + confidence + web corroboration), an honesty banner (field coverage, inferred-geography count), and a **Save scenario** button writing to Lakebase.

```bash
# Run locally first
uv run src/app/app.py

# Deploy via the bundle app resource
databricks bundle deploy -t prod
databricks bundle run mdp_app -t prod

# Tail logs if anything misbehaves
databricks apps logs mdp_app
```

**Checkpoint 8 — the full demo path:**
- App URL loads; map renders; chat returns a ranked district list.
- Click a district → candidate facilities show verified-capability badges + confidence.
- Honesty banner shows real coverage numbers.
- Save scenario → reload app → scenario reappears.
- `databricks apps logs mdp_app` is clean (no unhandled errors).

---

## Phase 9 — Hardening and submission

**Goal:** a judge can reproduce your demo from a clean clone.

- Turn on **MLflow tracing/monitoring** in production; route models through **AI Gateway** (OpenAI + Databricks FMs) with fallback.
- Add an eval gate to CI: the golden Q&A set must pass before deploy.
- Write the README: what it does (1–2 sentences), architecture diagram, exact run commands, demo steps.
- Record the ≤2-minute demo video; write the ≤500-character project write-up; list every Databricks technology and OSS/partner model used; publish the deployed-prototype link.

**Checkpoint 9 — judge-reproduction dry run:**
```bash
git clone <repo> fresh && cd fresh
databricks bundle validate -t prod
databricks bundle deploy -t prod
databricks bundle run mdp_app -t prod
```
- A teammate who didn't build it follows only the README and reaches a working demo.
- Repo is public and will stay public ≥ 30 days.

---

## Databricks component coverage map

| Phase | Components exercised |
|---|---|
| 0–1 | Databricks CLI, Declarative Automation Bundles, direct deploy engine |
| 2 | Unity Catalog (catalog, schema, volume, grants) |
| 3 | Volumes, Delta Lake, Lakeflow/Jobs |
| 4 | AI functions (`ai_query`/`ai_extract`), Vector Search, geospatial `ST_*` |
| 5 | Delta gold tables, Lakeflow expectations / DQ |
| 6 | Agent Bricks Supervisor, Genie, Custom Agent (MLflow ResponsesAgent), UC functions, Foundation Model API web search, MCP, MLflow eval/tracing |
| 7 | Lakebase (Postgres project/branch/endpoint), agent state |
| 8 | Databricks Apps, AI Gateway model routing |
| 9 | MLflow monitoring, CI eval gate |

---

## Notes / things to verify live in the workspace

- Exact bundle YAML field names for `apps`, `postgres_project`, and UC resources can shift between CLI versions — confirm against `databricks bundle schema` and the docs for your installed version rather than trusting any skeleton blindly.
- Lakebase and some Agent Bricks features may be region-gated; check availability in your hackathon workspace before committing the architecture in Phase 0, not Phase 7.
- Consider driving Phases 6 and 8 with an AI coding assistant (Claude Code / Cursor) using the `app-templates` repo skills and an `AGENTS.md` — Databricks ships these specifically to scaffold agent + app code from the CLI.
```