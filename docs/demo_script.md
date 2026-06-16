# CareReach — demo video script (≤ 3:00, hackathon limit)

**Target ≈ 2:25.** Record the app at https://mdp-planner-7474654025962366.aws.databricksapps.com
with **Care domain = Maternal & newborn**, **Bihar**, **district** preselected. Narration in **bold**,
on-screen actions in _italics_. Move slowly; let each answer land.

---

### 0:00–0:14 · Hook (the problem)
_Open on the CareReach hero — tricolor banner, India map, ambulance, "Track 2 · Medical Desert Planner"._
> **"Where should we send a mobile maternal-health unit? The honest answer has two parts: where are
> the care gaps — and can we trust that a gap is real, or are we just data-poor? Most tools collapse
> those into one map. CareReach refuses to."**

### 0:14–0:38 · The 2×2 (the core idea)
_Point to the three cards (REAL / DATA-POOR / served), then the 2×2 quadrant chart._
> **"Every region gets two independent signals. Maternal-care gap — how underserved it is. And evidence
> confidence — how much verified facility evidence backs that gap. Top-right, in red: real deserts, act.
> Top-left, in orange: high gap but almost no data — investigate first, don't deploy blindly. In Bihar:
> 22 real deserts, 15 data-poor."**

### 0:38–1:00 · Data-poor vs real desert (the payoff)
_Drill-down selector → pick **Araria**._
> **"Araria looks like the worst desert by health burden — but it has zero facilities in our data.
> CareReach flags it DATA-POOR: investigate, not deploy."**
_Now select **Saharsa** (or **Purba Champaran**)._
> **"Saharsa is a confirmed desert — facilities on record, but few with verified obstetric care.
> High gap, and we trust it."**

### 1:00–1:24 · Evidence + verification (claims, not facts)
_Expand a facility; show the badge + verbatim claim._
> **"Capabilities are claims we verify, not ground truth. Each facility shows verified, claimed-but-
> unverified, or no-claim — with a confidence score and the exact source sentence. An LLM auditor
> checks each claim, so a dental hospital that scraped the word 'gynaecology' never counts as obstetric
> coverage. Evidence over assumptions."**

### 1:24–1:52 · Ask the planner — by voice, in any language
_Scroll to "Ask the deployment planner." Pick **Hindi**, tap Record, say the question, tap Stop._
> _(speak)_ **"बिहार में मोबाइल मातृ स्वास्थ्य इकाई कहाँ भेजें?"**
_Point to "Heard (Hindi): … → English: …", then the answer._
> **"A planner asks in their own language. We transcribe, translate on Databricks, and the agent
> recommends the real deserts to act on — Saharsa, Katihar, Madhepura — while explicitly flagging
> Araria and Kishanganj as investigate-first. Grounded only in the governed gold tables."**

### 1:52–2:10 · Persist + generalize
_Click **Save plan to Lakebase**, then **Load recent plans**. Then open the **Care domain** selector._
> **"Save the plan — with the recommendation attached — to Lakebase, and reopen it later. And it's not
> just maternal care: the engine is specialty-agnostic. Maternal is live because NFHS-5 gives us real
> burden data; surgery and pediatrics are a burden signal away — no rewrite."**

### 2:10–2:25 · Close
_Back to the 2×2; point to the honesty banner._
> **"CareReach turns 10,000 messy facility records into deployment decisions a planner can trust —
> extract structure, show evidence, communicate uncertainty honestly, and persist the plan. All on
> Databricks: Unity Catalog, AI functions, Vector Search, Agent Bricks, Lakebase, and a hosted App.
> Find the real deserts — and know which gaps you can trust."**

---

## One-take checklist (pre-stage before recording)
- App open: **Care domain = Maternal & newborn**, **Bihar**, geography = **district**.
- **Warm the model:** click **Ask** once beforehand so the live answer returns fast on camera.
- **Voice:** Chrome/Edge, allow mic, speak a short clear Hindi sentence; the "Heard → English" line
  proves the speech path. Record the voice take 2–3× beforehand and keep the best (free recognizer is
  best-effort). Tested questions + outputs: `docs/voice_demo_questions.md`.
- Capture at 1080p; keep total **under 3:00**.
- Do clicks live for authenticity; pre-expand nothing.

## 45-second cut (if a short version is needed)
Hook (0:00–0:10) → 2×2 + Araria vs Saharsa (0:10–0:25) → voice Hindi question + answer (0:25–0:40) →
"two signals, decisions you can trust" close (0:40–0:45).
