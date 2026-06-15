# CareReach — 2-minute demo video script

**Total ≈ 1:55.** Record the app at https://mdp-planner-7474654025962366.aws.databricksapps.com
(have Bihar pre-selected). Narration in **bold**, on-screen actions in _italics_. Keep cursor moves slow.

---

### 0:00–0:12 · Hook (problem)
_Open on the CareReach app, title visible._
> **"Where should we send a mobile maternal-health unit? The honest answer has two parts:
> where are the care gaps — and can we actually trust that a gap is real, or are we just
> data-poor? Most tools collapse those into one map. CareReach refuses to."**

### 0:12–0:35 · The 2×2 (the core idea)
_Point to the three metric cards, then the 2×2 quadrant chart._
> **"Every district gets two independent scores. Care gap — how little verified maternal
> capability exists. And data confidence — how much facility evidence backs that gap.
> Top-right, in red: real deserts, act on them. Top-left, in orange: high gap but almost no
> data — investigate first, don't deploy blindly."**

### 0:35–0:55 · Data-poor vs real desert (the payoff)
_In the drill-down selector, pick **Araria**._
> **"Araria looks like the worst desert by health burden — but it has zero facilities in our
> data. CareReach flags it DATA-POOR: investigate, not deploy."**
_Now select **Purba Champaran**._
> **"Purba Champaran is a confirmed desert: ten facilities on record, but only one with verified
> obstetric care. High gap, and we trust it."**

### 0:55–1:20 · Evidence + verification (claims, not facts)
_Expand a facility in Purba Champaran; show the badge + verbatim claim._
> **"Drill in and every capability is a claim with a confidence score and the exact source
> sentence. An LLM auditor verifies each claim against the facility's profile — so an eye
> hospital that scrapes the word 'gynaecology' is marked not-credible and never counts toward
> coverage. Evidence over assumptions."**

### 1:20–1:42 · Ask the planner agent
_Scroll to "Ask the planner agent"; the Bihar question is pre-filled; click **Ask**._
> **"Ask in plain language..."** _(answer appears)_ **"...and the agent recommends the real
> deserts to act on — Saharsa, Katihar, Purba Champaran — while explicitly flagging Araria and
> Kishanganj as investigate-first. Grounded entirely in the governed gold tables."**

### 1:42–1:55 · Honesty + persistence + close
_Point to the per-region honesty banner; click **Save scenario**, then **Load recent scenarios**._
> **"Field-coverage and inferred-geography are shown up front, scenarios save to Lakebase with
> the recommendation attached, and it all runs on Databricks — Unity Catalog, AI functions,
> Vector Search, Agent Bricks, and a hosted App. CareReach: find the real deserts, and know
> which gaps you can trust."**

---

## One-take checklist (pre-stage before recording)
- App open, **Bihar** selected, geography level = **district**.
- Run **Ask** once beforehand so the model is warm (answer returns in ~2–3s on camera).
- Pre-expand nothing; do each click live for authenticity.
- Capture at 1080p; keep total under 2:00 (hackathon limit).

## 30-second cut (if a short version is needed)
Hook (0:00–0:08) → 2×2 + Araria vs Purba Champaran (0:08–0:20) → Ask-the-agent answer (0:20–0:30).
