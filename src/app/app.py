"""CareReach — hosted Databricks App (Streamlit).

PRIMARY VIEW is a 2x2 quadrant (care_gap x data_confidence), NOT a single choropleth, so a
planner never confuses a HIGH-GAP + LOW-CONFIDENCE *data-poor* region with a confirmed desert.
Geo-level selector (state/city/district/pincode) over mdp.gold.region_signals; click-through
drill-down shows the underlying facilities, verified-capability badges, per-claim confidence,
the verbatim evidence quote, and the raw counts behind both signals. Saves scenarios to Lakebase.
"""
import os, json, uuid
import pandas as pd
import streamlit as st
from databricks.sdk import WorkspaceClient

WAREHOUSE_ID = os.environ.get("MDP_WAREHOUSE_ID", "4248317cbefec64d")
SUPERVISOR   = os.environ.get("MDP_SUPERVISOR_ENDPOINT", "mas-e40dbc0b-endpoint")
PG_INSTANCE  = os.environ.get("MDP_PG_INSTANCE", "mdp-pg")
PG_DATABASE  = os.environ.get("MDP_PG_DATABASE", "mdp_app")
GAP_T, CONF_T = 0.66, 0.45   # quadrant thresholds (match Checkpoint 5)

# Resolve each facility's NFHS (state, district) the same way region_signals does, so drill-down
# facilities match the aggregated region exactly (incl. the alias cases).
FAC_CTE = """
WITH bdedup AS (
  SELECT unique_id, max(address_city) address_city, max(address_zipOrPostcode) zip
  FROM mdp.bronze.facilities GROUP BY unique_id),
f0 AS (
  SELECT g.*, b.address_city, b.zip,
    CASE g.state_norm WHEN 'MAHARASHTRA' THEN 'MAHARASTRA' WHEN 'DELHI' THEN 'NCT OF DELHI'
      WHEN 'JAMMU AND KASHMIR' THEN 'JAMMU KASHMIR' WHEN 'TAMILNADU' THEN 'TAMIL NADU'
      WHEN 'ANDAMAN AND NICOBAR ISLANDS' THEN 'ANDAMAN NICOBAR ISLANDS' WHEN 'ORISSA' THEN 'ODISHA'
      WHEN 'UTTRANCHAL' THEN 'UTTARAKHAND' WHEN 'U T OF PUDUCHERRY' THEN 'PUDUCHERRY'
      WHEN 'THE DADRA AND NAGAR HAVELI AND DAMAN AND DIU' THEN 'DADRA AND NAGAR HAVELI DAMAN AND DIU'
      ELSE g.state_norm END AS ns
  FROM mdp.gold.facility g LEFT JOIN bdedup b ON b.unique_id = g.facility_id),
f AS (
  SELECT *, nullif(trim(regexp_replace(upper(address_city),'[^A-Z0-9]+',' ')),'') AS cn,
    CAST(try_cast(zip AS BIGINT) AS STRING) AS pc,
    CASE WHEN ns='TELANGANA' AND district_norm='HYDRABAD' THEN 'HYDERABAD'
         WHEN ns='TELANGANA' AND district_norm='RANGAREDDY' THEN 'RANGA REDDY'
         WHEN ns='TELANGANA' AND district_norm='MEDCHAL' THEN 'MEDCHAL MALKAJGIRI'
         WHEN ns='TELANGANA' AND district_norm='WARANGAL U' THEN 'WARANGAL URBAN'
         WHEN ns='WEST BENGAL' AND district_norm='NORTH TWENTY FOUR PARGANAS' THEN 'NORTH TWENTY FOUR PARGANA'
         WHEN ns='WEST BENGAL' AND district_norm='SOUTH TWENTY FOUR PARGANAS' THEN 'SOUTH TWENTY FOUR PARGANA'
         ELSE district_norm END AS nd
  FROM f0)
"""

st.set_page_config(page_title="CareReach", layout="wide")


@st.cache_resource
def w():
    return WorkspaceClient()


def run_sql(stmt: str) -> pd.DataFrame:
    r = w().statement_execution.execute_statement(warehouse_id=WAREHOUSE_ID, statement=stmt, wait_timeout="50s")
    if r.status and r.status.state.value != "SUCCEEDED":
        raise RuntimeError(r.status.error.message if r.status.error else "SQL failed")
    cols = [c.name for c in r.manifest.schema.columns] if r.manifest and r.manifest.schema else []
    return pd.DataFrame(r.result.data_array if (r.result and r.result.data_array) else [], columns=cols)


def quadrant(gap, conf):
    if gap >= GAP_T and conf >= CONF_T:
        return "REAL desert (act)"
    if gap >= GAP_T:
        return "DATA-POOR (investigate)"
    return "adequately served"


@st.cache_data(ttl=300)
def load_level(level: str) -> pd.DataFrame:
    df = run_sql(f"""SELECT region_key, region_label, state_ut,
        CAST(care_gap_score AS DOUBLE) care_gap_score, CAST(data_confidence_score AS DOUBLE) data_confidence_score,
        CAST(facility_count AS INT) facility_count, CAST(verified_count AS INT) verified_count,
        CAST(high_conf_count AS INT) high_conf_count, CAST(geocoded_count AS INT) geocoded_count,
        CAST(inferred_count AS INT) inferred_count, CAST(evidence_count AS INT) evidence_count
        FROM mdp.gold.region_signals WHERE geo_level='{level}'""")
    for c in ["care_gap_score", "data_confidence_score"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    for c in ["facility_count", "verified_count", "high_conf_count", "geocoded_count", "inferred_count", "evidence_count"]:
        df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0).astype(int)
    df["quadrant"] = [quadrant(g, c) for g, c in zip(df.care_gap_score, df.data_confidence_score)]
    return df


def drill_facilities(level: str, region_key: str) -> pd.DataFrame:
    filt = {"district": "ns||'|'||nd", "state": "ns", "city": "ns||'|'||cn", "pincode": "pc"}[level]
    rk = region_key.replace("'", "''")
    return run_sql(f"""{FAC_CTE}
        SELECT name, obstetrics_verified, csection_verified, icu_verified,
               ROUND(obstetrics_confidence,2) ob_conf, claim_sentence, geo_inferred
        FROM f WHERE {filt} = '{rk}'
        ORDER BY obstetrics_verified DESC, csection_verified DESC LIMIT 60""")


def grounded_answer(question: str, vdf: pd.DataFrame, state: str) -> str:
    """Planner-agent answer grounded ONLY in the two-signal region data (via ai_query)."""
    def fmt(r):
        return (f"{r.region_label} (gap {r.care_gap_score:.2f}, confidence {r.data_confidence_score:.2f}, "
                f"{int(r.facility_count)} facilities, {int(r.verified_count)} verified obstetric)")
    real = vdf[vdf.quadrant == "REAL desert (act)"].sort_values("care_gap_score", ascending=False).head(6)
    poor = vdf[vdf.quadrant == "DATA-POOR (investigate)"].sort_values("care_gap_score", ascending=False).head(6)
    ctx = ("REAL deserts (high gap, enough data to trust): " + ("; ".join(fmt(r) for _, r in real.iterrows()) or "none")
           + ".  DATA-POOR (high gap but too little data — investigate, do NOT deploy blindly): "
           + ("; ".join(fmt(r) for _, r in poor.iterrows()) or "none") + ".")
    prompt = ("You are CareReach, a maternal-health deployment planner for India. Answer the planner in <=160 words using ONLY the "
              "region signals provided. Recommend specific districts to deploy a mobile maternal-health unit FROM the REAL deserts. "
              "Separately and explicitly flag the DATA-POOR districts as 'investigate first - we lack facility evidence there, they are "
              "not confirmed deserts'. Cite the numbers and state uncertainty honestly. Never present a data-poor region as a confirmed gap. "
              f"State focus: {state}. Planner question: {question}. Region signals: {ctx}")
    return run_sql("SELECT ai_query('databricks-gemini-3-5-flash', '" + prompt.replace("'", "''") + "') AS a").iloc[0]["a"]


def supervisor_answer(question: str):
    """Best-effort call to the Agent Bricks supervisor endpoint (shown if it returns text)."""
    try:
        r = w().api_client.do("POST", f"/serving-endpoints/{SUPERVISOR}/invocations",
                              body={"input": [{"role": "user", "content": question}]})
        out = []
        for it in (r.get("output") or []):
            for c in (it.get("content") or []):
                if c.get("type") in ("output_text", "text"):
                    out.append(c.get("text", ""))
        return "\n".join(out).strip() or None
    except Exception:
        return None


def pg_connect():
    """Connect to Lakebase. The `database` app-resource binding injects PGHOST/PGUSER/PGPORT/
    PGDATABASE/PGSSLMODE but NOT a password, so we mint a short-lived OAuth token as the password.
    Auth is identity-based: the username MUST match the identity the token was minted for. The
    token is minted by the app's own service principal, so `current_user.me()` (the SP's app id)
    is the authoritative username — it's the federated Postgres role that actually exists. We try
    that first, then fall back to the binding's PGUSER in case the platform differs."""
    import psycopg2
    token = w().database.generate_database_credential(
        request_id=str(uuid.uuid4()), instance_names=[PG_INSTANCE]).token
    host = os.environ.get("PGHOST")
    if not host:
        host = w().database.get_database_instance(name=PG_INSTANCE).read_write_dns
    port = os.environ.get("PGPORT", "5432")
    dbname = os.environ.get("PGDATABASE", PG_DATABASE)
    sslmode = os.environ.get("PGSSLMODE", "require")
    try:
        token_identity = w().current_user.me().user_name
    except Exception:
        token_identity = None
    # Candidate usernames in priority order: token's own identity, then binding PGUSER.
    candidates, seen = [], set()
    for u in (token_identity, os.environ.get("PGUSER")):
        if u and u not in seen:
            candidates.append(u); seen.add(u)
    last_err = None
    for user in candidates:
        try:
            conn = psycopg2.connect(host=host, port=port, dbname=dbname, user=user,
                                    password=token, sslmode=sslmode)
            return conn, f"ok(user={user})"
        except Exception as e:
            last_err = e
    raise RuntimeError(f"Lakebase auth failed for users {candidates}: {last_err}")


# --------------------------------------------------------------------------- UI
st.title("🩺 CareReach")
st.caption("Find the real maternal-care deserts — and know which gaps you can trust. "
           "Two signals, never collapsed: **where are the care gaps** × **how confident are we they're real vs. just data-poor**.")

level = st.sidebar.radio("Geography level", ["district", "state", "city", "pincode"], index=0)
df = load_level(level)
states = ["(all)"] + sorted(df["state_ut"].dropna().unique().tolist())
state_filter = st.sidebar.selectbox("Filter by state", states, index=(states.index("Bihar") if "Bihar" in states else 0))
view = df if state_filter == "(all)" else df[df["state_ut"] == state_filter]

counts = view["quadrant"].value_counts().to_dict()
c1, c2, c3 = st.columns(3)
c1.metric("🔴 REAL deserts (act)", counts.get("REAL desert (act)", 0))
c2.metric("🟠 DATA-POOR (investigate)", counts.get("DATA-POOR (investigate)", 0))
c3.metric("🟢 Adequately served", counts.get("adequately served", 0))

st.subheader("💬 Ask the planner agent")
aq = st.text_input("Ask CareReach a question",
                   value=f"Where in {state_filter} should we deploy a mobile maternal-health unit, and which regions need investigation first?")
if st.button("Ask"):
    with st.spinner("Reasoning over the two-signal region data…"):
        try:
            ans = grounded_answer(aq, view, state_filter)
        except Exception as e:
            ans = f"(answer failed: {e})"
        st.session_state["agent_q"] = aq
        st.session_state["agent_answer"] = ans
        st.session_state["agent_supervisor"] = supervisor_answer(aq)
if st.session_state.get("agent_answer"):
    st.markdown(st.session_state["agent_answer"])
    if st.session_state.get("agent_supervisor"):
        with st.expander("Agent Bricks supervisor (multi-agent) response"):
            st.markdown(st.session_state["agent_supervisor"])
    st.caption("Grounded in mdp.gold.region_signals — recommends REAL deserts to act on and flags DATA-POOR regions to investigate first.")

left, right = st.columns([3, 2])
with left:
    st.subheader(f"2×2 — care gap × data confidence ({level}{'' if state_filter=='(all)' else ', '+state_filter})")
    try:
        import altair as alt
        base = alt.Chart(view)
        pts = base.mark_circle(size=90, opacity=0.6).encode(
            x=alt.X("data_confidence_score", title="Data confidence  →  (trust the gap)", scale=alt.Scale(domain=[0, 1])),
            y=alt.Y("care_gap_score", title="Care gap  →  (worse)", scale=alt.Scale(domain=[0, 1])),
            color=alt.Color("quadrant", scale=alt.Scale(
                domain=["REAL desert (act)", "DATA-POOR (investigate)", "adequately served"],
                range=["#d62728", "#ff7f0e", "#2ca02c"])),
            tooltip=["region_label", "state_ut", "care_gap_score", "data_confidence_score",
                     "facility_count", "verified_count", "inferred_count"])
        vline = alt.Chart(pd.DataFrame({"x": [CONF_T]})).mark_rule(strokeDash=[5, 5], color="gray").encode(x="x")
        hline = alt.Chart(pd.DataFrame({"y": [GAP_T]})).mark_rule(strokeDash=[5, 5], color="gray").encode(y="y")
        st.altair_chart(pts + vline + hline, use_container_width=True)
        st.caption("Top-left = HIGH gap + LOW confidence = **data-poor, investigate first** (not a confirmed desert). "
                   "Top-right = HIGH gap + HIGH confidence = **real desert, act**.")
    except Exception as e:
        st.error(f"chart error: {e}")
        st.scatter_chart(view, x="data_confidence_score", y="care_gap_score", color="quadrant")

with right:
    st.subheader("Regions")
    st.dataframe(view.sort_values("care_gap_score", ascending=False)
                 [["region_label", "quadrant", "care_gap_score", "data_confidence_score", "facility_count", "verified_count"]],
                 hide_index=True, use_container_width=True, height=360)

st.divider()
st.subheader("Drill-down — why is this region flagged?")
opts = view.sort_values("care_gap_score", ascending=False)["region_label"].tolist()
sel = st.selectbox("Region", opts)
if sel:
    r = view[view["region_label"] == sel].iloc[0]
    q = r["quadrant"]
    icon = {"REAL desert (act)": "🔴", "DATA-POOR (investigate)": "🟠", "adequately served": "🟢"}[q]
    st.markdown(f"### {icon} {sel} — **{q}**")
    fc = int(r["facility_count"])
    a, b, c, d = st.columns(4)
    a.metric("Care gap", f"{r['care_gap_score']:.3f}")
    b.metric("Data confidence", f"{r['data_confidence_score']:.3f}")
    c.metric("Facilities (evidence)", fc)
    d.metric("Verified obstetric", int(r["verified_count"]))
    # Honesty banner for THIS region
    if fc > 0:
        st.info(f"**Honesty for {sel}:** {int(r['geocoded_count'])}/{fc} geocoded "
                f"({100*r['inferred_count']/fc:.0f}% inferred geography) · "
                f"{100*r['high_conf_count']/fc:.0f}% high-confidence claims · "
                f"{100*r['evidence_count']/fc:.0f}% with an evidence quote.")
    else:
        st.warning(f"**{sel} has ZERO facilities in our data.** The high care gap is burden-driven; with no "
                   f"facility evidence we cannot confirm a true desert — this is **data-poor → investigate**, not deploy.")
    if q == "DATA-POOR (investigate)":
        st.warning("⚠️ Flagged DATA-POOR: confidence is below threshold. Investigate/collect data before deploying a unit here.")
    elif q == "REAL desert (act)":
        st.success("✅ Confirmed desert: enough facility evidence to trust the low verified coverage. Candidate for deployment.")

    if fc > 0:
        try:
            facs = drill_facilities(level, r["region_key"])
            st.write(f"Underlying facilities ({len(facs)} shown):")
            for _, f in facs.iterrows():
                ob = str(f["obstetrics_verified"]).lower() == "true"
                cs = str(f["csection_verified"]).lower() == "true"
                badges = ("✅ obstetrics" if ob else "▫️ obstetrics") + " · " + ("✅ C-section" if cs else "▫️ C-section")
                inferred = " · 📍inferred geo" if str(f["geo_inferred"]).lower() == "true" else ""
                with st.expander(f"{f['name']}  —  {badges}  (ob conf {f['ob_conf']}){inferred}"):
                    st.write(f"Verbatim claim: _{f['claim_sentence'] or '—'}_")
        except Exception as e:
            st.error(f"facility drill-down failed: {e}")

st.divider()
st.subheader("Save scenario")
agent_q = st.session_state.get("agent_q")
agent_answer = st.session_state.get("agent_answer")
note = st.text_input("Question / note", value=agent_q or f"Where in {state_filter} should we deploy a mobile maternal-health unit?")
if agent_answer:
    st.caption("✓ The planner agent's recommendation will be saved with this scenario.")
else:
    st.caption("Tip: use **Ask the planner agent** above first — its recommendation is saved with the scenario.")
if st.button("💾 Save scenario to Lakebase"):
    pg_keys = sorted([k for k in os.environ if k.startswith(("PG", "POSTGRES", "DATABRICKS_DATABASE")) or "DATABASE_URL" in k])
    payload = {"level": level, "state": state_filter, "selected_region": sel,
               "quadrant": view[view.region_label == sel]["quadrant"].iloc[0] if sel else None,
               "buckets": counts,
               "agent_question": agent_q,
               "agent_answer": agent_answer,
               "supervisor_answer": st.session_state.get("agent_supervisor")}
    try:
        conn, src = pg_connect()
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("INSERT INTO sessions(planner,title) VALUES(%s,%s) RETURNING session_id", ("app user", note[:80]))
            sid = cur.fetchone()[0]
            cur.execute("INSERT INTO scenarios(session_id,question,state,answer) VALUES(%s,%s,%s,%s) RETURNING scenario_id",
                        (sid, note, state_filter, json.dumps(payload)))
            scid = cur.fetchone()[0]
        conn.close()
        st.success(f"Saved scenario {scid} via {src} auth — including the agent's recommendation. Open it below.")
    except Exception as e:
        st.error(f"Save failed [pg env: {', '.join(pg_keys) or 'none'}]: {e}")

st.divider()
st.subheader("📂 Saved scenarios (reopen)")
if st.button("Load recent scenarios from Lakebase"):
    try:
        conn, _ = pg_connect()
        with conn.cursor() as cur:
            cur.execute("SELECT scenario_id, created_at, question, answer FROM scenarios ORDER BY created_at DESC LIMIT 10")
            rows = cur.fetchall()
        conn.close()
        if not rows:
            st.info("No saved scenarios yet — save one above.")
        for scid, ts, question, answer in rows:
            payload = answer if isinstance(answer, dict) else json.loads(answer or "{}")
            with st.expander(f"{question}  ·  {ts:%Y-%m-%d %H:%M}"):
                st.write(f"State: **{payload.get('state')}** · selected region: {payload.get('selected_region')} · buckets: {payload.get('buckets')}")
                if payload.get("agent_answer"):
                    st.markdown("**Saved agent recommendation:**")
                    st.markdown(payload["agent_answer"])
                else:
                    st.caption("(no agent recommendation saved with this scenario)")
    except Exception as e:
        st.error(f"Load failed: {e}")
