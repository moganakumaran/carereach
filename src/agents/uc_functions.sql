-- Unity Catalog functions the planner agents call as tools (mdp.gold.fn_*).
-- Governed, deterministic geo + desert-score logic over the gold tables.

-- Geo: which district polygon contains a (lat, lon) point. SRID 4326 to match boundaries.
CREATE OR REPLACE FUNCTION mdp.gold.fn_point_to_district(lat DOUBLE, lon DOUBLE)
RETURNS STRING
COMMENT 'District name whose geoBoundaries ADM2 polygon contains the (lat, lon) point; NULL if none.'
RETURN (
  SELECT district_name FROM mdp.silver.district_boundaries
  WHERE st_contains(geom, st_setsrid(st_point(lon, lat), 4326))
  LIMIT 1
);

-- Desert ranking: worst maternal-care medical-desert districts in a state.
CREATE OR REPLACE FUNCTION mdp.gold.fn_worst_deserts(p_state STRING, p_limit INT)
RETURNS TABLE (district_name STRING, desert_score DOUBLE, burden_score DOUBLE,
               verified_obstetric INT, total_facilities INT)
COMMENT 'Top medical-desert districts (highest desert_score) for maternal care in a state. Higher = worse.'
RETURN
  SELECT district_name, desert_score, burden_score, verified_obstetric, total_facilities
  FROM (SELECT *, row_number() OVER (ORDER BY desert_score DESC) AS rn
        FROM mdp.gold.district_desert WHERE upper(state_ut) = upper(p_state))
  WHERE rn <= p_limit;

-- District summary: burden + verified coverage + desert score for one district.
CREATE OR REPLACE FUNCTION mdp.gold.fn_district_summary(p_state STRING, p_district STRING)
RETURNS TABLE (district_name STRING, state_ut STRING, desert_score DOUBLE, burden_score DOUBLE,
               accessibility_score DOUBLE, verified_obstetric INT, total_facilities INT,
               nfhs_small_sample_cols INT)
COMMENT 'Desert score and its components for a single district (case-insensitive state + district match).'
RETURN
  SELECT trim(district_name), state_ut, desert_score, burden_score, accessibility_score,
         verified_obstetric, total_facilities, nfhs_small_sample_cols
  FROM mdp.gold.district_desert
  WHERE upper(trim(state_ut)) = upper(trim(p_state))
    AND upper(trim(district_name)) = upper(trim(p_district));

-- Capability verification (the "claims are not facts" safety check): adjudicate a facility's
-- claim for a service via ai_query (gemini-3-5-flash) over its text -> verdict + confidence + rationale.
CREATE OR REPLACE FUNCTION mdp.gold.fn_verify_capability(p_facility_id STRING, p_service STRING)
RETURNS TABLE (facility_id STRING, name STRING, district_name STRING, service STRING,
               verdict STRING, confidence DOUBLE, rationale STRING, claim_sentence STRING)
COMMENT 'Adjudicate whether a facility credibly provides a service (csection|obstetrics|icu|blood_bank|emergency). Verdict in {credible,uncertain,not_credible} + confidence + rationale.'
RETURN
WITH f AS (SELECT facility_id, name, district_name, claim_text FROM mdp.silver.facility_search WHERE facility_id = p_facility_id),
p AS (
  SELECT f.*, from_json(ai_query('databricks-gemini-3-5-flash',
    request => concat(
      'You are a clinical-capability auditor for an Indian health-facility directory whose text contains CLAIMS that may be scraped or exaggerated. Judge whether THIS facility credibly provides the service: ',
      p_service,
      '. Weigh explicit mention, specificity (named equipment/procedures/staff), and facility-type plausibility (a dental, eye, diagnostic, or AYUSH facility is implausible for csection/icu/blood_bank). Return verdict in {credible, uncertain, not_credible}, confidence 0-1, and a one-sentence rationale. Facility text: ',
      coalesce(claim_text, name)),
    responseFormat => '{"type":"json_schema","json_schema":{"name":"verdict","strict":true,"schema":{"type":"object","additionalProperties":false,"properties":{"verdict":{"type":"string","enum":["credible","uncertain","not_credible"]},"confidence":{"type":"number"},"rationale":{"type":"string"}},"required":["verdict","confidence","rationale"]}}}'),
    'STRUCT<verdict: STRING, confidence: DOUBLE, rationale: STRING>') AS d
  FROM f)
SELECT facility_id, name, district_name, p_service, d.verdict, d.confidence, d.rationale, substr(claim_text,1,160) FROM p;

-- Semantic retrieval over facility claim text via Mosaic AI Vector Search (self-managed gte-large-en).
CREATE OR REPLACE FUNCTION mdp.gold.fn_search_facilities(p_query STRING)
RETURNS TABLE (facility_id STRING, name STRING, district_name STRING,
               obstetrics_claimed BOOLEAN, csection_claimed BOOLEAN, score DOUBLE)
COMMENT 'Top-10 facilities most semantically similar to a free-text query (e.g. "hospital with NICU and caesarean").'
RETURN SELECT facility_id, name, district_name, obstetrics_claimed, csection_claimed, search_score
       FROM vector_search(index => 'mdp.silver.facility_vs_index',
                          query_vector => ai_query('databricks-gte-large-en', p_query),
                          num_results => 10);
