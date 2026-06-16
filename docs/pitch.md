# CareReach — 2-minute pitch (spoken)

*~300 words ≈ 2:00 at a natural pace. Read straight through, or use it as the voiceover for the
demo video. Stage directions in (parentheses) — don't read those.*

---

(Problem — 0:00)
Every year, planners and NGOs have to decide where to send scarce maternal-health resources across
India — and they're working from messy, scraped facility data where a listing *claims* it does
C-sections but might be a dental clinic. Get it wrong, and a mobile unit goes to a district that
didn't need it, while a real desert stays uncovered.

(The honest insight — 0:25)
Most tools answer "where are the gaps?" with one score. But that quietly hides a second question:
*can we even trust the gap, or are we just data-poor there?* CareReach refuses to collapse those.
Every region gets **two independent signals** — the maternal-care gap, and how much *verified*
evidence backs it. Plotted as a 2×2: top-right in red are real deserts, act on them; top-left in
orange are high-gap but low-evidence — investigate first, don't deploy blindly. In Bihar that's
22 real deserts versus 15 data-poor districts that most tools would falsely flag.

(How it works — 1:00)
Under the hood it's a governed Databricks pipeline. We treat every scraped capability as a *claim,
not a fact* — an AI function extracts it, an LLM auditor verifies it against the facility's profile,
and a dental hospital that scraped the word "gynaecology" never counts as obstetric coverage. Every
recommendation drills down to the facilities, the confidence, and the exact source sentence.

(Reach + persistence — 1:30)
A planner can ask in plain English — or by voice, in Hindi, Bengali, Tamil — and we transcribe,
translate on Databricks, and answer. Then they save the plan, with its recommendation, to Lakebase.

(Close — 1:45)
It's built end-to-end on Databricks Free Edition — Unity Catalog, AI functions, Vector Search, Agent
Bricks, Lakebase, a hosted App — and the engine is specialty-agnostic; maternal is just the vertical
with real burden data today. CareReach: find the real deserts, and know which gaps you can trust.

---

## 60-second version
Planners decide where to send scarce maternal-health resources from messy data where a clinic *claims*
care it may not provide. CareReach scores every Indian region on **two signals — the care gap, and how
much verified evidence backs it** — so a real desert (act) is never confused with a data-poor region
(investigate first). Capabilities are claims we verify with an LLM auditor, down to the source sentence.
Ask by voice in any Indian language; save the plan to Lakebase. All on Databricks — Unity Catalog,
AI functions, Vector Search, Agent Bricks, a hosted App — and specialty-agnostic by design.
Find the real deserts, and know which gaps you can trust.
