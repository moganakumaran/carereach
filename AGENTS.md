# AGENTS.md — Medical Desert Planner

Context for any AI coding assistant (Claude Code, Cursor, Copilot) working in this repo.
Read this fully before running commands or editing files.

## What this is

The **Medical Desert Planner**, built for the Databricks Apps & Agents for Good
Hackathon 2026 (Data + AI Summit, with OpenAI). **Track 2.**

A non-technical planner asks, in plain language — *"Where should we send a mobile
maternal-health unit in Bihar?"* — and gets a ranked, evidence-backed,
uncertainty-aware answer they can save and revisit. The app surfaces medical
deserts: districts with high health burden and low *verified* facility coverage.

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

## Optional voice & multilingual layer (Phase 8.5)

Only if the text demo (through Phase 8) is fully working and time remains:
- Tier 1 only: browser mic → Whisper Large V3 (Model Serving) or OpenAI STT (via
  AI Gateway) → existing supervisor agent; `ai_translate` for Hindi/regional input
  and output; TTS for playback. No real-time voice, no video.
- Honesty rule: spoken output must still state confidence + caveats; map/evidence
  drawer stay the source of truth.
- Governance: transcripts (not raw audio unless needed) stored in Lakebase under
  Unity Catalog, short retention.

## Architecture (target)

- **UI:** Databricks App (map + chat + evidence drawer + honesty banner + save).
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
- `mdp.gold.district_desert` — one row per district. Columns include:
  `district_id`, `verified_coverage`, `burden_score`, `accessibility_score`,
  `desert_score`, plus the counts behind each.

## Desert-score definition

```
desert_score = w1 * burden_score
             + w2 * (1 - normalized_verified_coverage)
             + w3 * accessibility_score
```
- Higher score = worse desert (high need, low verified supply, poor access).
- `verified_coverage` counts **only** facilities whose relevant capability is
  verified — a facility that cannot credibly perform C-sections does NOT count
  toward maternal coverage.
- `burden_score` derives from NFHS-5 indicators (maternal, child, anaemia, NCD),
  normalized 0–1.
- `accessibility_score` is a travel-time proxy, normalized 0–1.
- Default weights w1=0.5, w2=0.35, w3=0.15 — tune and document any change.
- All inputs normalized 0–1 before weighting.

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

Public GitHub repo (public ≥30 days) with architecture diagram and a README
covering: what it does (1–2 sentences), architecture, exact run commands, demo
steps. Plus a ≤500-char write-up, list of Databricks tech + OSS/partner models
used, a ≤2-minute demo video, and a deployed-prototype link. Judges reproduce
from a clean clone — keep `databricks bundle deploy -t prod` working end to end.