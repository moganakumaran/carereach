# AGENTS.md — CareReach (Track 2: Medical Desert Planner)

Context for any AI coding assistant (Claude Code, Cursor, Copilot) working in this repo.
Read this fully before running commands or editing files.

## What this is

**CareReach** (product name; Track 2 brief = "Medical Desert Planner"), built for the
Databricks Apps & Agents for Good Hackathon 2026 (Data + AI Summit, with OpenAI). **Track 2.**
Tagline: *Find India's real, highest-risk maternal-care gaps — and know which you can trust.*

A non-technical planner asks, in plain language (or by **voice, in their own Indian
language**) — *"Where should we send a mobile maternal-health unit in Bihar?"* — and gets a
ranked, evidence-backed, uncertainty-aware answer they can save and revisit. The app surfaces
maternal-care deserts using **two signals, never collapsed** (care gap × evidence confidence),
so a region we're simply *data-poor* about is never mislabeled a confirmed desert. Maternal is
the live, NFHS-grounded vertical; the engine is specialty-agnostic (a *Care domain* selector
makes this explicit). See `README.md` for the as-built description.

## Operating rules (do not violate)

- **Incremental with checkpoints.** Work one phase at a time. After each phase,
  run its checkpoint, report pass/fail with actual command output, and STOP.
  Do not begin the next phase until the human confirms the checkpoint is green.
- **Never run destructive commands** (drop, delete, overwrite, force-push)
  without explicit confirmation.
- **Governance before data.** Everything lives under Unity Catalog — tables,
  functions, volumes, agents.
- **Bundles over ad-hoc edits.** Prefer `databricks bundle` (Declarative
  Automation Bundles) so the whole project reproduces from a clean clone.
- **Verify, don't guess.** If a CLI field name or resource schema is uncertain,
  check `databricks bundle schema` and the docs for the installed CLI version.
- **Treat noisy fields as claims, not facts.** The free-text capability/equipment/
  procedure fields are scraped claims. They must be verified before a facility
  counts toward coverage.

## Environment

- Databricks CLI **>= 0.287.0** (required for Lakebase bundle resources).
- Python **>= 3.11**; `uv` package manager.
- Agent SDKs: `mlflow>=3.1.3`, `databricks-agents>=1.1.0`, `databricks-sdk`.
- Lakebase and Agent Bricks Supervisor may be **region-gated** — confirm they
  are enabled in this workspace before relying on them.

## Installed Databricks skills

This repo expects the official Databricks agent skills to be installed so the
coding assistant has accurate, current platform guidance:
`npx skills add databricks/databricks-agent-skills --skill databricks-apps --skill databricks-pipelines`
(or `databricks aitools install databricks-agent-skills`). These cover Databricks
CLI, app development, job orchestration, Lakebase, and Spark Declarative Pipelines.
Division of labour: **the skills know how Databricks works; this AGENTS.md knows
how this project works.** Prefer the skills for command/syntax details.

## Voice & multilingual layer (shipped)

- Planner can **ask by voice in a native Indian language** (Hindi, Bengali, Tamil, Telugu,
  Marathi, …). In-browser capture (Chrome/Edge) → transcript → **translation on Databricks**
  (chat endpoint, system/user roles) → fed into the same grounded planner flow. The "Heard
  (lang) → English" line is shown so the planner can confirm before asking.
- Honesty rule: the translated question runs through the same evidence-grounded path; the 2×2,
  drill-down, and honesty banners stay the source of truth. A failed transcription shows a retry
  prompt, never a silent no-op.
- Caveat: transcription uses a free best-effort browser recognizer; production would swap in a
  hosted Whisper endpoint. Translation is governed on Databricks.

## Architecture

> **As built:** the planner answer is a **deterministic, evidence-only LLM call grounded in
> `mdp.gold.region_signals`** (chat endpoint) — fast and reproducible for the demo. The Agent
> Bricks Supervisor + Genie Space exist and are demoed in the playground; verification ships as
> scalar **UC functions** (`fn_verify_capability`, `fn_search_facilities`) rather than a full
> MLflow ResponsesAgent. The items below are the original target design.

- **UI:** Databricks App (2×2 quadrant + drill-down + voice + evidence + honesty banner + save plan).
- **Orchestration:** Agent Bricks Supervisor Agent (no hard-coded routing).
- **Specialists the supervisor coordinates:**
  - Genie Space over `mdp.gold.*` (natural language to SQL).
  - Capability-verification custom agent (MLflow ResponsesAgent; Vector Search +
    AI classification; returns credibility judgement + confidence).
  - Geo/score tools registered as Unity Catalog functions (`ST_*`, desert score).
  - Foundation Model API web search (corroboration).
  - MCP / Marketplace enrichment (PIN codes, NFHS-5).
- **State:** Lakebase (Postgres) — sessions, scenarios, evidence trail, overrides.
- **Cross-cutting:** Unity Catalog governance, MLflow tracing/eval, AI Gateway
  model routing (OpenAI + Databricks foundation models).

## Data model

Catalog `mdp`. Schemas: `bronze`, `silver`, `gold`, `ops`.

**Bronze (raw):**
- `mdp.bronze.facilities` — ~10,000 rows, 51 columns (structured + free text).
- `mdp.bronze.pincode` — 165,627 rows (India Post PIN directory).
- `mdp.bronze.nfhs5` — 706 rows (NFHS-5 district indicators).

**Silver (cleaned + structured):**
- AI-extracted capability flags from free text, each with a confidence score
  (e.g. `does_csection`, `has_icu`, `obstetric_services`).
- Vector Search index over `description`, `capability`, `equipment`.
- PIN directory deduplicated to district grain **before any join**.
- NFHS columns snake_cased; `*` mapped to NULL (never 0); parenthesised
  small-sample estimates flagged low-confidence.
- Each facility assigned to a district via `ST_Contains(polygon, ST_Point(lon,lat))`;
  rows with missing coordinates flagged `geo_inferred = true`.

**Gold (decision-ready) — contracts:**
- `mdp.gold.facility` — one row per facility. Columns include: `facility_id`,
  `district_id`, capability flags + per-flag `confidence`, `geo_inferred`,
  `evidence_ref` (pointer to source record + claim sentence).
- `mdp.gold.region_signals` — **one row per region per geo level** (state/city/district/pincode).
  Columns: `geo_level`, `region_key`, `region_label`, `state_ut`, **`care_gap_score`**,
  **`data_confidence_score`**, plus the raw counts behind both (`facility_count`,
  `verified_count`, `high_conf_count`, `geocoded_count`, `inferred_count`, `evidence_count`).
  This is the table the app reads.

## Two-signal definition (never collapse them)

The headline design choice: **need** and **evidence** are scored separately so a data-poor
region is never mislabeled a confirmed desert.

```
care_gap_score (district)   = 0.5 * burden + 0.35 * (1 - verified_coverage) + 0.15 * accessibility
care_gap_score (other levels) = 0.55 * burden_norm + 0.45 * (1 - verified_norm)
data_confidence_score       = 0.40 * count_score + 0.25 * high_conf_share
                            + 0.20 * geocoded_share + 0.15 * evidence_share
```
- Higher `care_gap_score` = more underserved (high need, low *verified* supply, poor access).
- `verified_coverage` counts **only** facilities whose relevant capability is verified — a
  facility that cannot credibly perform C-sections does NOT count toward maternal coverage.
- `burden` derives from NFHS-5 indicators (maternal/child/anaemia/NCD), normalized 0–1.
- `data_confidence_score` = how much verified facility evidence backs the gap.
- **Quadrants** (thresholds gap ≥ 0.66, confidence ≥ 0.45): `REAL desert (act)` =
  high gap + high confidence · `DATA-POOR (investigate)` = high gap + low confidence ·
  `adequately served` = low gap. All inputs normalized 0–1 before weighting.
- **Models:** silver extraction/verification built with `databricks-gemini-3-5-flash`; the live
  app's planner answer + native-language translation use `databricks-meta-llama-3-3-70b-instruct`
  (premium endpoints are rate-limited to 0 on this Free Edition workspace).

## Naming conventions

- Tables: `mdp.<layer>.<entity>` (e.g. `mdp.silver.facility_claims`).
- UC functions: `mdp.gold.fn_<verb>` (e.g. `mdp.gold.fn_desert_score`).
- Agents/endpoints: `mdp_<role>` (e.g. `mdp_supervisor`, `mdp_verify_agent`).
- Bundle targets: `dev` (default during build), `prod` (demo + submission).
- App resource: `mdp_app`.

## Critical gotchas (these break projects)

1. **PIN join fan-out.** Row grain of the PIN directory is post office, not PIN.
   Deduplicate to district grain before joining or silver facility count balloons.
   Checkpoint: silver facility rows must stay ~10,000.
2. **Asterisks are NULL, not zero.** NFHS `*` means suppressed/unavailable.
3. **Inferred geography is flagged, never dropped and never presented as exact.**
4. **Coverage uses verified facilities only** (see desert score).
5. **Extraction quality gate:** hand-label 30 facilities; flags must agree ≥80%
   before building gold on top of them.

## Submission requirements (keep the repo ready)

Public, **open-source-licensed** GitHub repo that shows the project was **built during the
Project Period** (June 15 8am PT – June 16 2:30pm PT) — *new projects only; not created before
the event* (Official Rules 4.2(d), 4.3(d)). README covers: what it does (1–2 sentences),
architecture diagram, exact run commands, demo steps. Plus a ≤500-char write-up, list of
Databricks tech + OSS/partner models used, a **≤3-minute** demo video (YouTube/Vimeo, public),
and a deployed-prototype link with test access. Judges reproduce from a clean clone — keep
`databricks bundle deploy -t prod` working end to end.