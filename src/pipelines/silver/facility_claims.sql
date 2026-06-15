-- silver.facility_claims: ai_query (gpt-oss-120b, json_schema structured output) extracts
-- CLAIMED clinical capabilities from the free-text fields. These are CLAIMS, not verified facts
-- (Phase 6 verification agent adjudicates). India only (WHERE countryCode='IN') -> the ~88
-- column-misaligned rows are excluded. Each capability has a 0-1 confidence + an evidence quote.
CREATE OR REPLACE TABLE mdp.silver.facility_claims AS
WITH src AS (
  SELECT unique_id AS facility_id, name,
    try_cast(latitude AS DOUBLE) AS latitude, try_cast(longitude AS DOUBLE) AS longitude,
    nullif(trim(address_zipOrPostcode),'') AS pincode_raw,
    trim(address_stateOrRegion) AS state_raw,
    concat_ws(' | ', name, substr(description,1,1500), substr(specialties,1,500), substr(procedure,1,1500), substr(equipment,1,1000), substr(capability,1,1500)) AS claim_text
  FROM mdp.bronze.facilities
  WHERE upper(address_countryCode)='IN'
),
ext AS (
  SELECT *, ai_query('databricks-gpt-oss-120b', request => concat('You audit an Indian health-facility directory. Decide which clinical capabilities the facility CLAIMS to provide, based ONLY on explicit support in the text. Do NOT infer a capability from a generic specialty list, an unrelated mention, or the facility name. If unclear, set claimed=false. Capabilities: csection (caesarean delivery), obstetrics (maternity/delivery/labour care), icu (intensive care incl NICU), blood_bank (on-site blood bank/transfusion), emergency (24x7 emergency/casualty). Give each *_confidence 0-1. evidence = one short verbatim quote (<=150 chars) supporting the strongest claim, else empty. Text: ', claim_text), responseFormat => '{"type": "json_schema", "json_schema": {"name": "caps", "strict": true, "schema": {"type": "object", "additionalProperties": false, "properties": {"csection_claimed": {"type": "boolean"}, "csection_confidence": {"type": "number"}, "obstetrics_claimed": {"type": "boolean"}, "obstetrics_confidence": {"type": "number"}, "icu_claimed": {"type": "boolean"}, "icu_confidence": {"type": "number"}, "blood_bank_claimed": {"type": "boolean"}, "blood_bank_confidence": {"type": "number"}, "emergency_claimed": {"type": "boolean"}, "emergency_confidence": {"type": "number"}, "evidence": {"type": "string"}}, "required": ["csection_claimed", "csection_confidence", "obstetrics_claimed", "obstetrics_confidence", "icu_claimed", "icu_confidence", "blood_bank_claimed", "blood_bank_confidence", "emergency_claimed", "emergency_confidence", "evidence"]}}}') AS raw_json
  FROM src
),
parsed AS (SELECT *, from_json(raw_json, 'STRUCT<csection_claimed: BOOLEAN, csection_confidence: DOUBLE, obstetrics_claimed: BOOLEAN, obstetrics_confidence: DOUBLE, icu_claimed: BOOLEAN, icu_confidence: DOUBLE, blood_bank_claimed: BOOLEAN, blood_bank_confidence: DOUBLE, emergency_claimed: BOOLEAN, emergency_confidence: DOUBLE, evidence: STRING>') AS c FROM ext)
SELECT facility_id, name, latitude, longitude, pincode_raw, state_raw,
  trim(regexp_replace(upper(coalesce(state_raw,'')), '[^A-Z0-9]+', ' ')) AS norm_state_facility,
  c.csection_claimed, c.csection_confidence, c.obstetrics_claimed, c.obstetrics_confidence,
  c.icu_claimed, c.icu_confidence, c.blood_bank_claimed, c.blood_bank_confidence,
  c.emergency_claimed, c.emergency_confidence, c.evidence, claim_text
FROM parsed;
