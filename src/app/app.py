"""Medical Desert Planner — hosted Databricks App (Streamlit).

Map of maternal-care medical deserts + evidence-backed facility verification + scenario save.
Runs as a Databricks App; authenticates as the app's service principal via the SDK.
Data: mdp.gold.* (via SQL warehouse), verification via mdp.gold.fn_* (ai_query + Vector Search),
persistence via Lakebase (mdp-pg / mdp_app).
"""
import os, json, uuid
import pandas as pd
import streamlit as st
from databricks.sdk import WorkspaceClient

WAREHOUSE_ID = os.environ.get("MDP_WAREHOUSE_ID", "4248317cbefec64d")
SUPERVISOR   = os.environ.get("MDP_SUPERVISOR_ENDPOINT", "mas-e40dbc0b-endpoint")
PG_INSTANCE  = os.environ.get("MDP_PG_INSTANCE", "mdp-pg")
PG_DATABASE  = os.environ.get("MDP_PG_DATABASE", "mdp_app")

st.set_page_config(page_title="Medical Desert Planner", layout="wide")
w = WorkspaceClient()


@st.cache_resource
def _client():
    return WorkspaceClient()


def run_sql(stmt: str) -> pd.DataFrame:
    """Run SQL on the warehouse via the Statement Execution API (auth = app SP)."""
    r = _client().statement_execution.execute_statement(
        warehouse_id=WAREHOUSE_ID, statement=stmt, wait_timeout="50s")
    if r.status and r.status.state.value != "SUCCEEDED":
        msg = r.status.error.message if r.status.error else "unknown"
        raise RuntimeError(f"SQL failed: {msg}")
    cols = [c.name for c in r.manifest.schema.columns] if r.manifest and r.manifest.schema else []
    data = r.result.data_array if r.result and r.result.data_array else []
    return pd.DataFrame(data, columns=cols)


@st.cache_data(ttl=300)
def load_districts() -> pd.DataFrame:
    df = run_sql("""SELECT district_name, state_ut, CAST(desert_score AS DOUBLE) desert_score,
        CAST(burden_score AS DOUBLE) burden_score, CAST(accessibility_score AS DOUBLE) accessibility_score,
        CAST(verified_obstetric AS INT) verified_obstetric, CAST(total_facilities AS INT) total_facilities,
        CAST(centroid_lat AS DOUBLE) lat, CAST(centroid_lon AS DOUBLE) lon
        FROM mdp.gold.district_map""")
    for c in ["desert_score","burden_score","accessibility_score","lat","lon"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    for c in ["verified_obstetric","total_facilities"]:
        df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0).astype(int)
    return df


@st.cache_data(ttl=300)
def coverage_stats() -> dict:
    df = run_sql("""SELECT
        COUNT(*) n, ROUND(100.0*COUNT_IF(geo_inferred)/COUNT(*),1) pct_inferred,
        ROUND(100.0*COUNT_IF(obstetrics_verified)/COUNT(*),1) pct_ob_verified
        FROM mdp.gold.facility""")
    return df.iloc[0].to_dict()


def facilities_in_district(state: str, district: str) -> pd.DataFrame:
    return run_sql(f"""SELECT facility_id, name, obstetrics_verified, csection_verified, icu_verified,
        ROUND(obstetrics_confidence,2) ob_conf, claim_sentence, geo_inferred
        FROM mdp.gold.facility
        WHERE upper(trim(state_norm))=upper('{state}') AND upper(trim(district_norm))=upper('{district}')
        ORDER BY obstetrics_verified DESC, csection_verified DESC LIMIT 50""")


def verify(facility_id: str, service: str) -> dict:
    df = run_sql(f"SELECT mdp.gold.fn_verify_capability_json('{facility_id}','{service}') j")
    try:
        return json.loads(df.iloc[0]["j"])
    except Exception:
        return {"verdict": "unknown", "confidence": 0, "rationale": ""}


# ----------------------------------------------------------------------------- UI
st.title("🩺 Medical Desert Planner")
st.caption("Where should we send a mobile maternal-health unit? Evidence-backed, uncertainty-aware.")

try:
    cov = coverage_stats()
    c1, c2, c3 = st.columns(3)
    c1.metric("Facilities (India)", f"{int(float(cov['n'])):,}")
    c2.metric("Obstetric capability *verified*", f"{cov['pct_ob_verified']}%")
    c3.metric("Using inferred geography", f"{cov['pct_inferred']}%")
    st.info("Honesty banner: capability flags are AI-extracted **claims** verified by an LLM auditor; "
            "coverage counts only *verified* obstetric facilities. Inferred-geography rows are flagged, not dropped.")
except Exception as e:
    st.error(f"Could not load coverage stats: {e}")

districts = load_districts()
states = sorted(districts["state_ut"].dropna().unique().tolist())
default_ix = states.index("Bihar") if "Bihar" in states else 0
state = st.sidebar.selectbox("State", states, index=default_ix)
topn = st.sidebar.slider("How many districts", 3, 15, 5)

sd = districts[districts["state_ut"] == state].sort_values("desert_score", ascending=False)

left, right = st.columns([3, 2])
with left:
    st.subheader(f"Desert map — {state}")
    md = sd.dropna(subset=["lat", "lon"]).copy()
    if not md.empty:
        try:
            import pydeck as pdk
            md["r"] = (md["desert_score"] * 255).clip(0, 255).astype(int)
            md["radius"] = (md["desert_score"] * 30000 + 4000)
            layer = pdk.Layer("ScatterplotLayer", md, get_position=["lon", "lat"],
                              get_fill_color="[r, 80, 40, 160]", get_radius="radius", pickable=True)
            st.pydeck_chart(pdk.Deck(layers=[layer],
                initial_view_state=pdk.ViewState(latitude=md["lat"].mean(), longitude=md["lon"].mean(), zoom=5.5),
                tooltip={"text": "{district_name}\ndesert {desert_score}"}))
        except Exception:
            st.map(md.rename(columns={"lat": "latitude", "lon": "longitude"})[["latitude", "longitude"]])
    st.caption("Darker/larger = worse desert (high burden, low verified coverage).")

with right:
    st.subheader(f"Worst {topn} deserts")
    st.dataframe(sd.head(topn)[["district_name", "desert_score", "burden_score",
                                "verified_obstetric", "total_facilities"]],
                 hide_index=True, use_container_width=True)

st.divider()
st.subheader("District detail & evidence")
dsel = st.selectbox("District", sd["district_name"].tolist())
if dsel:
    drow = sd[sd["district_name"] == dsel].iloc[0]
    a, b, c, d = st.columns(4)
    a.metric("Desert score", f"{drow['desert_score']:.3f}")
    b.metric("Burden", f"{drow['burden_score']:.3f}")
    c.metric("Verified obstetric", int(drow["verified_obstetric"]))
    d.metric("Total facilities", int(drow["total_facilities"]))
    try:
        facs = facilities_in_district(state, dsel)
        if facs.empty:
            st.warning("No facilities mapped to this district — a candidate for a mobile unit.")
        else:
            st.write("Candidate facilities (verified-obstetric first):")
            for _, f in facs.head(15).iterrows():
                badge = "✅ obstetrics" if str(f["obstetrics_verified"]).lower() == "true" else "— obstetrics unverified"
                with st.expander(f"{f['name']} · {badge}"):
                    st.write(f"Claim: _{f['claim_sentence'] or '—'}_")
                    if st.button("Verify C-section capability", key=f"v{f['facility_id']}"):
                        v = verify(f["facility_id"], "csection")
                        st.write(f"**{v['verdict']}** (confidence {v.get('confidence')}) — {v.get('rationale','')}")
    except Exception as e:
        st.error(f"Facility lookup failed: {e}")

st.divider()
st.subheader("Ask the planner")
q = st.text_input("Question", value=f"Where in {state} should we deploy a mobile maternal-health unit?")
if st.button("Answer"):
    ranked = sd.head(topn)
    st.write(f"**Top maternal-care deserts in {state}:**")
    for _, r in ranked.iterrows():
        st.write(f"- **{r['district_name']}** — desert {r['desert_score']:.3f}, burden {r['burden_score']:.2f}, "
                 f"{int(r['verified_obstetric'])} verified obstetric / {int(r['total_facilities'])} facilities")
    st.session_state["last_answer"] = {
        "state": state,
        "question": q,
        "top_districts": ranked[["district_name", "desert_score", "verified_obstetric"]].to_dict("records"),
    }

if st.session_state.get("last_answer") and st.button("💾 Save scenario to Lakebase"):
    import psycopg2
    pg_keys = sorted([k for k in os.environ if k.startswith(("PG", "POSTGRES", "DATABRICKS_DATABASE")) or "DATABASE_URL" in k])
    try:
        if os.environ.get("PGHOST") and os.environ.get("PGUSER") and os.environ.get("PGPASSWORD"):
            # Preferred: connection injected by the Lakebase `database` app resource binding.
            conn = psycopg2.connect(
                host=os.environ["PGHOST"], port=os.environ.get("PGPORT", "5432"),
                dbname=os.environ.get("PGDATABASE", PG_DATABASE), user=os.environ["PGUSER"],
                password=os.environ["PGPASSWORD"], sslmode=os.environ.get("PGSSLMODE", "require"))
            src = "binding"
        else:
            # Fallback: mint a short-lived credential ourselves.
            cred = _client().database.generate_database_credential(
                request_id=str(uuid.uuid4()), instance_names=[PG_INSTANCE])
            inst = _client().database.get_database_instance(name=PG_INSTANCE)
            conn = psycopg2.connect(host=inst.read_write_dns, port=5432, dbname=PG_DATABASE,
                                    user=_client().current_user.me().user_name, password=cred.token, sslmode="require")
            src = "generated"
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("INSERT INTO sessions(planner,title) VALUES(%s,%s) RETURNING session_id",
                        ("app user", f"{state} maternal unit"))
            sid = cur.fetchone()[0]
            cur.execute("INSERT INTO scenarios(session_id,question,state,answer) VALUES(%s,%s,%s,%s) RETURNING scenario_id",
                        (sid, q, state, json.dumps(st.session_state["last_answer"])))
            scid = cur.fetchone()[0]
        conn.close()
        st.success(f"Saved scenario {scid} via {src} auth — reload and it persists in Lakebase.")
    except Exception as e:
        st.error(f"Save failed [pg env: {', '.join(pg_keys) or 'none'}]: {e}")
