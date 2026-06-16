# CareReach — find the real maternal-care deserts, and know which gaps you can trust

## 💡 Inspiration

The hackathon hands you 10,000 scraped Indian healthcare facility records and one blunt
warning: **treat the noisy fields as claims to verify, not ground truth.** That warning stuck
with us. A facility listing might *say* it performs C-sections — but it could be a dental clinic
that happened to scrape the word "gynaecology." If a planner trusts that listing and sends a
mobile maternal-health unit there, two things go wrong at once: resources are wasted, and a
community that genuinely has no obstetric care stays invisible.

When we looked at how "medical desert" tools usually work, we noticed they all do the same risky
thing: they collapse everything into **one score**. That score can't tell the difference between
*"this region has a confirmed gap"* and *"we just have no data about this region."* In maternal
health — where India still carries a heavy share of preventable maternal mortality — that
difference is the whole decision. So we set out to build a planner's tool that **refuses to lie by
omission**.

## 🩺 What it does

CareReach lets a non-technical planner ask, in plain language (or **by voice in their own Indian
language**), *"Where in Bihar should we send a mobile maternal-health unit?"* — and get a ranked,
**evidence-backed, uncertainty-aware** answer they can save and revisit.

Its core idea is **two signals, never collapsed**: every region gets a **care gap** score *and* an
independent **evidence confidence** score, plotted on a 2×2. Top-right (red) = real deserts, act.
Top-left (orange) = high gap but almost no data — *investigate first, don't deploy blindly.* In
Bihar that's **22 real deserts vs. 15 data-poor districts** that a one-score tool would falsely
flag as confirmed gaps.

## 🧮 The math behind the two signals

For each region we compute two normalized scores in $[0,1]$.

**Care gap** (need + unmet supply). At the district level:

$$
\text{care\_gap} = 0.5\,\underbrace{B}_{\text{NFHS burden}} \;+\; 0.35\,\bigl(1 - C_v\bigr) \;+\; 0.15\,A
$$

where $C_v$ is **verified** obstetric coverage (a facility only counts if its capability is
verified) and $A$ is an accessibility proxy.

**Evidence confidence** (can we trust the gap?):

$$
\text{data\_conf} = 0.40\,S_{\text{count}} + 0.25\,S_{\text{high\_conf}} + 0.20\,S_{\text{geocoded}} + 0.15\,S_{\text{evidence}}
$$

A region is then assigned to a quadrant using two thresholds:

$$
\text{quadrant} =
\begin{cases}
\textbf{REAL desert} & \text{if } \text{care\_gap} \ge 0.66 \;\wedge\; \text{data\_conf} \ge 0.45\\[2pt]
\textbf{DATA-POOR} & \text{if } \text{care\_gap} \ge 0.66 \;\wedge\; \text{data\_conf} < 0.45\\[2pt]
\textbf{adequately served} & \text{otherwise}
\end{cases}
$$

The key property: a high gap with low evidence is **never** rendered as a confirmed desert.

## 🛠️ How we built it

Everything runs on **Databricks Free Edition**, governed end-to-end by **Unity Catalog**, deployed
as a **Declarative Asset Bundle** (direct engine, Terraform-free) so it reproduces from a clean clone.

A **medallion pipeline** does the heavy lifting:

- **Bronze** — land the three sources (10k facilities, the India-Post PIN directory, NFHS-5 survey),
  plus open **geoBoundaries** district polygons.
- **Silver** — the hard part. An **AI function** (`ai_query` with a JSON schema) reads each facility's
  free text into typed capability *claims with confidence*. A second AI step acts as an **auditor**,
  checking each claim against the facility's profile — so an eye hospital claiming C-sections is
  marked *not-credible* and never counts toward coverage. We clean NFHS (`*` → `NULL`, not zero),
  deduplicate the PIN directory, place every facility in a district via `ST_Contains`, and build a
  **Mosaic AI Vector Search** index over the text.
- **Gold** — compute the two signals per region per geography level into `region_signals`, the table
  the app reads.

On top sits a hosted **Databricks App** (Streamlit): the 2×2 quadrant, drill-down to verified
evidence and the verbatim source sentence, **voice questions** (browser capture → translation on
Databricks → grounded answer), and **Save/Load to Lakebase** (serverless Postgres). **Agent Bricks**
and a **Genie Space** expose the governed tables to natural-language questions, and verification
ships as scalar **UC function tools**.

## 🧗 Challenges we ran into

- **The "one score lies" problem.** Our first version *had* a single desert score — and it confidently
  ranked zero-facility districts as the worst deserts. That was the moment we tore it up and rebuilt
  around two independent signals. It's now the heart of the project.
- **Join fan-out.** The PIN directory's grain is *post office*, not PIN code; a naive join silently
  ballooned our facility count. We had to dedup to district grain (165,627 → 19,586) *before* joining,
  and added SQL assertions so it can never regress.
- **Picking an extraction model — empirically.** `gpt-oss-120b` would've taken ~4.7 hours on 10k rows;
  `llama-3.1-8b` was fast but **over-claimed** (60% C-section!); `gemini-3-5-flash` did it in ~5 minutes
  and passed a 30-facility hand-labeled gate. We only trusted it after measuring it.
- **Vector Search at the wrong speed.** Auto-embedding via delta-sync crawled at ~1 row/sec (~3 hours).
  We switched to **self-managed embeddings** precomputed with `ai_query` (~7 min); the index then
  ingested in ~40 seconds.
- **Geography that doesn't match itself.** District names differ across geoBoundaries, NFHS, and the
  facility data (MAHARASHTRA vs MAHARASTRA, the 24-Parganas spellings…). Alias maps got us to ~98%
  facility attribution.
- **Models disappearing mid-build.** The premium endpoints (gemini, claude) got rate-limited to 0 on
  our Free Edition workspace. We moved the live app to `llama-3-3-70b` via the chat-completions
  endpoint — and discovered that a single blended prompt made the model *answer* a translated question
  instead of translating it. Splitting **system vs. user roles** fixed it.
- **Service-principal auth to Lakebase.** Getting the app's service principal to authenticate to
  Postgres took real digging: the fix was to mint a short-lived **OAuth database credential** and
  connect as the SP's *own* federated role (the token's identity), plus explicit table grants.
- **Voice failing silently.** The off-the-shelf speech component swallowed every error and returned
  nothing, so a failed clip looked like a frozen app. We took over the transcription step, wrapped it
  in a spinner, and made failures show a clear "try again" — never silence.

## 📚 What we learned

- **Honesty is a feature, not a disclaimer.** Modeling uncertainty as a *first-class, separate signal*
  changed the entire product for the better — and it's also the most defensible design decision.
- **Measure models, don't assume them.** Speed and over-claiming are real, measurable risks; a tiny
  hand-labeled gate saved us from building on bad extractions.
- **The data is the project.** Fan-out, suppressed values, inferred geography, name harmonization —
  the unglamorous data-prep work is what makes the answer trustworthy.
- **Build for the platform you actually have.** Endpoints get disabled, instances suspend; designing
  graceful fallbacks (and honest captions about them) beats assuming the happy path.

## 🚀 What's next

The engine is **specialty-agnostic** — the same extract → verify → two-signal method works for general
surgery, pediatrics, or cardiac care. Maternal care is live today because **NFHS-5 gives us real
district-level burden** to ground demand; adding a specialty is a matter of wiring in *that* domain's
burden signal, not rewriting the system. Beyond that: a hosted Whisper endpoint to bring the voice
step fully onto Databricks, and richer accessibility/travel-time data for the gap score.

> **CareReach: find the real deserts — and know which gaps you can trust.**
