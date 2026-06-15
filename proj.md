# Medical Desert Planner — DAIS 2026 Hackathon Plan

**Event:** Databricks Apps & Agents for Good Hackathon 2026 (Data + AI Summit, in partnership with OpenAI)
**Team:** Guduru *(2–4 members)*
**Track chosen:** Track 2 — Medical Desert Planner
**One-liner:** A non-technical planner asks, in plain language, *"Where should we send a mobile maternal-health unit in Bihar?"* — and gets a ranked, evidence-backed, uncertainty-aware answer they can save and revisit.

---

## 1. Why Track 2

The brief offers four tracks. Track 2 wins on the two judging axes that matter for this hackathon — *agentic depth* and *breadth of Databricks tooling* — while telling the strongest social-impact story.

- It is the only track that legitimately uses the full stack: geospatial joins, both enrichment datasets (PIN code directory + NFHS-5), AI extraction over the noisy free-text fields, and a multi-agent reasoning loop.
- It absorbs Track 1 as a sub-component. The dataset's core warning is "treat noisy fields as claims to verify, not ground truth." A desert planner that counts a facility toward maternal coverage *without* checking whether it can actually perform C-sections is dangerously wrong. So claim-verification becomes one specialist agent inside the planner — we get Track 1's value for free.
- "Medical deserts" is the exact framing of the VF Match product in the kickoff deck, so the output maps directly onto a real platform planners already understand.

---

## 2. What we are building

A **Databricks App** with a map-centric planner UI and a chat panel. Behind it, an **Agent Bricks Supervisor Agent** orchestrates several specialists to answer planning questions over a medallion-architected version of the 10,000-record India facility dataset, enriched with public-health and postal geography.

The four challenge requirements map cleanly:

| Requirement | How we satisfy it |
|---|---|
| Extract structure | AI functions (`ai_query`, `ai_extract`) + Vector Search turn free-text `description`, `capability`, `equipment`, `procedure` into typed capability flags |
| Show evidence | Every recommendation cites the source record, the exact claim sentence, a confidence score, and (where available) corroborating web evidence |
| Communicate uncertainty honestly | Field-coverage gaps surfaced (`year_established` 48%, `capacity` 25%); per-claim confidence; "verified vs inferred" geography flag; low-confidence matches suppressed, not hidden |
| Persist their work | Lakebase stores planner sessions, saved scenarios, the full evidence trail, and any reviewer overrides |

---

## 3. Agentic architecture

**Supervisor Agent (Agent Bricks Supervisor, GA)** sits at the centre. It interprets the planner's natural-language question, decides which specialists to call, and synthesises a single ranked answer. No hard-coded routing — the supervisor is steered by instructions and improves from natural-language feedback.

Specialists and tools it coordinates:

1. **Structured-data agent — Genie Space.** Natural language to SQL over the gold Delta tables (facility counts per district, NFHS-5 burden indicators, accessibility). Answers "how many verified obstetric facilities are in each Bihar district?"
2. **Capability-verification agent — custom agent.** Given a facility's free-text claims and a needed service, returns a credibility judgement plus a confidence score. Uses Vector Search over the `description`/`capability`/`equipment` text and AI classification. This is what keeps "claims" from being treated as "ground truth."
3. **Geo/gap tools — Unity Catalog functions.** Run the point-in-polygon spatial join (`ST_Contains`, `ST_Point`) that attaches each facility to a district, then compute the composite **desert score** = f(verified coverage, NFHS-5 burden, accessibility proxy).
4. **Web-evidence tool — Foundation Model API web search.** Grounds or corroborates a facility claim with real-time sources when the dataset is thin.
5. **Enrichment via MCP / Marketplace.** PIN code directory and NFHS-5 brought in as governed data the agents can query.

**State & persistence — Lakebase.** Serverless Postgres, natively integrated with Agent Bricks for agent memory and state. Stores conversation history, saved planning scenarios, the recommendation + evidence trail, and reviewer decisions. This is the "persist their work" requirement and the long-running-workflow memory in one place.

**Governance & observability — Unity Catalog + MLflow + AI Gateway.** UC governs tables, functions, agents, and on-behalf-of access. MLflow traces and evaluates the agent. AI Gateway routes across OpenAI and Databricks foundation models (relevant given the OpenAI partnership) with fallback and cost control.

---

## 4. Data plan (medallion)

**Bronze — raw ingest**
- 10,000 India facility records, 51 columns (structured + free text).
- India Post PIN code directory (165,627 rows).
- NFHS-5 district health indicators (706 districts, 109 columns).

**Silver — clean + structure**
- Parse and type the structured fields; treat noisy fields as claims.
- `ai_extract` / `ai_query` to pull structured capabilities (e.g. `does_csection`, `has_icu`, `obstetric_services`) from free text, each with a confidence.
- Build a Vector Search index over `description`, `capability`, `equipment` for semantic claim matching.
- Deduplicate the PIN directory before joining (row grain is post office, not PIN — a naive join fans out rows).
- Snake_case the NFHS-5 columns; map asterisk-suppressed values to NULL (never zero); flag parenthesised small-sample estimates as low-confidence.
- Spatial join: facility lat/long → district polygon via `ST_Contains` using geoBoundaries; flag facilities with missing coordinates as "inferred geography."

**Gold — decision-ready**
- One unified row per facility: verified capability flags + confidence + evidence pointer.
- One row per district: desert score combining verified coverage, NFHS-5 burden (maternal/child/anaemia/NCD), and an accessibility proxy.

---

## 5. The App (planner UX)

- **Map view** — district choropleth shaded by desert score; darkest = highest burden, lowest verified coverage.
- **Chat panel** — plain-language questions routed to the supervisor.
- **Ranked district list** — click a district to see candidate facilities with verified-capability badges and confidence scores.
- **Evidence drawer** — for each claim: the source record, the exact text, the confidence, and any web corroboration.
- **Honesty banner** — shows field coverage and how many facilities relied on inferred (vs verified) geography.
- **Save scenario** — persists the question, answer, and evidence to Lakebase; reopen later to prove persistence.

---

## 6. Two-minute demo script

1. Planner types: *"Where in Bihar should we deploy a mobile maternal-health unit?"*
2. Supervisor routes to Genie + geo tools + verification agent; map lights up the worst maternal-care deserts.
3. Click the top district → candidate facilities appear, each with a verified-capability badge ("can perform C-section — confidence 0.82") and the source sentence.
4. Open the honesty banner → "capacity known for only 25% of facilities; 3 of 12 placements use inferred geography."
5. Click **Save scenario**, reload the app, reopen the saved scenario → persistence proven.

---

## 7. Build timeline

**Day 1 (today) — foundation**
- Stand up workspace, Unity Catalog catalog/schema, Lakebase instance.
- Bronze ingest of all three datasets; first-pass silver cleaning.
- Prototype `ai_extract` on 200 records; sanity-check capability extraction quality.

**Day 1 evening — spine**
- Spatial join working; first gold district table with a naive desert score.
- Genie Space over gold; verify it answers basic count questions.

**Day 2 morning — agents**
- Build the capability-verification custom agent + Vector Search index.
- Wire the Supervisor Agent to Genie, geo UC functions, and the verification agent.
- Add Foundation Model web search as a corroboration tool.

**Day 2 midday — app + persistence**
- Databricks App shell: map + chat + evidence drawer.
- Lakebase scenario save/load; MLflow tracing on the agent.

**Day 2 afternoon — polish + submit**
- Honesty banner, confidence display, demo data path hardening.
- Record demo video, write README + architecture diagram, deploy prototype.

---

## 8. Databricks tool coverage (for judging)

| Capability | Tool |
|---|---|
| Orchestration | Agent Bricks Supervisor Agent |
| Structured Q&A | Genie Space |
| Custom reasoning | Custom Agent (capability verification) |
| Semantic search | Mosaic AI Vector Search |
| Text → structure | AI functions (`ai_query`, `ai_extract`) |
| Real-time grounding | Foundation Model API web search |
| Geospatial | `ST_Contains`, `ST_Point` UC functions |
| State / persistence | Lakebase (Postgres) |
| UI | Databricks Apps (Custom Agents on Apps) |
| Governance | Unity Catalog (tables, functions, on-behalf-of) |
| Eval / tracing | MLflow |
| Model routing | AI Gateway (OpenAI + Databricks FMs) |
| External data | MCP / Marketplace (PIN codes, NFHS-5) |

---

## 9. Submission checklist

Confirm against the official DAIS-for-Good 2026 rules page, but Databricks hackathons typically require:

- Public GitHub repo (kept public ≥30 days) with an architecture diagram and a README covering: what it does (1–2 sentences), the architecture, exact run commands, and demo steps. Judges will try to reproduce the demo from the repo.
- Project write-up, up to 500 characters.
- List of Databricks technologies and open-source / partner models used.
- Demo video, up to 2 minutes, showing the solution live.
- Link to a deployed prototype.
- Team of 2–4.

---

## 10. Risks and mitigations

- **Free-text extraction noise.** Keep a human-in-the-loop confidence threshold; surface low-confidence claims rather than acting on them silently.
- **Geocoding gaps.** ~12,600 PIN rows lack coordinates; never present inferred geography as exact — flag it.
- **Join fan-out.** Always deduplicate PIN-to-district before joining; check cardinality first.
- **Scope creep.** The spine (ingest → spatial join → gold → Genie) must work end-to-end before adding the verification agent. Build the boring path first, then the impressive one.