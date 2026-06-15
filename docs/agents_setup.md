# Phase 6 — Agent setup (Genie + Agent Bricks Supervisor)

The data spine, gold tables, Vector Search index, and governed UC tool functions are built
from the CLI. The two remaining pieces are created in the Databricks **UI** (no provisioning
API today). This guide makes those steps turnkey. Workspace: `dbc-d2cc8242-7697`, catalog `mdp`.

## Governed tools already registered (UC functions in `mdp.gold`)

| Function | Purpose |
|---|---|
| `fn_point_to_district(lat, lon)` | Geo: which district polygon contains a point (ST_Contains) |
| `fn_worst_deserts(state, limit)` | Ranked worst maternal-care desert districts in a state |
| `fn_district_summary(state, district)` | Desert score + components for one district |
| `fn_verify_capability(facility_id, service)` | Adjudicate a facility's claim → verdict + confidence + rationale |
| `fn_search_facilities(query)` | Semantic search over facility claim text (Vector Search) |

Tables: `mdp.gold.facility` (9,989 facilities, verified flags + evidence), `mdp.gold.district_desert`
(706 districts, desert_score + burden + coverage).

---

## 6b — Genie Space (structured Q&A over `mdp.gold.*`)

**Create:** Databricks UI → **Genie** → New space → name `MDP Planner`.
**Add tables:** `mdp.gold.district_desert`, `mdp.gold.facility`.
**General instructions (paste):**
> This space answers planning questions about medical deserts in India for maternal-health
> care. `district_desert` has one row per district with `desert_score` (0–1, higher = worse:
> high health burden + low *verified* facility coverage), `burden_score`, `verified_obstetric`,
> and `total_facilities`. `facility` has one row per facility with verified capability flags
> (`obstetrics_verified`, `csection_verified`, …) and `district_name`/`state_norm`.
> Coverage counts **verified** facilities only. When ranking deserts, order by `desert_score`
> descending. State names use NFHS spellings (e.g. Maharastra). Always show the numbers behind
> a ranking (burden, verified coverage).

**Sample questions (add as examples):**
- How many verified obstetric facilities are in each Bihar district?
- Which 5 districts in Bihar have the worst desert_score?
- What is the desert score and burden for Araria?
- Which districts have high burden but zero verified obstetric facilities?

**Checkpoint:** ask "how many verified obstetric facilities in Patna?" → expect ~36; "worst 5
deserts in Bihar" → Sitamarhi, Araria, Kishanganj, Purnia, Katihar.

---

## 6d — Agent Bricks Supervisor

**Create:** UI → **Agent Bricks** → Supervisor (Multi-agent) → name `mdp_supervisor`.
**Attach tools / agents:**
1. **Genie space** `MDP Planner` (structured Q&A).
2. **UC functions** (add as tools) — IMPORTANT: agent tools must be **scalar** functions, so
   register the `*_json` variants (the table-valued functions are for Genie/SQL only):
   `mdp.gold.fn_point_to_district`, `fn_worst_deserts_json`, `fn_district_summary_json`,
   `fn_verify_capability_json`, `fn_search_facilities_json`. Each returns a JSON string the
   supervisor parses.
3. **Foundation Model web search** (corroboration) — optional.
4. **MCP / Marketplace enrichment** — optional.

**Supervisor instructions (paste):**
> You help a non-technical planner decide where to send mobile maternal-health units in India.
> For "where should we deploy in <state>?": call `fn_worst_deserts` to rank desert districts,
> then for the top districts use Genie / `fn_district_summary` for the burden + verified-coverage
> numbers. When recommending specific facilities, call `fn_search_facilities` then
> `fn_verify_capability` for the relevant service — **never present an unverified claim as fact**;
> report each capability's verdict + confidence and cite the claim sentence. Always state
> uncertainty: field-coverage gaps, low-confidence verdicts, and any facility using inferred
> geography. Do not hard-code routing — choose tools based on the question.

**Checkpoint 6:**
- Trace for "where to deploy a maternal unit in Bihar?" shows the supervisor calling
  `fn_worst_deserts` + Genie + `fn_verify_capability` in a sensible order.
- Verification precision: spot-check ~20 `fn_verify_capability` judgements (low false-positive).
- MLflow eval on a ~15-pair golden Q&A set meets the bar.
- All agents/functions registered in UC with correct grants.
