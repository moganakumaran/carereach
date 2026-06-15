-- silver.facility_claims: ai_query (gemini-3-5-flash, json_schema structured output) extracts
-- CLAIMED clinical capabilities from the free-text fields. CLAIMS, not verified facts (Phase 6
-- verification agent adjudicates). India only (countryCode='IN') excludes the ~88 misaligned rows.
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
  SELECT *, ai_query('databricks-gemini-3-5-flash', request => concat('You audit an Indian health-facility directory. Decide which clinical capabilities the facility CLAIMS, based ONLY on explicit evidence in the text. Mark claimed=true only if the text explicitly states the facility provides that service; never infer from the name, a generic specialty list, or unrelated mentions; if unclear, false. AYUSH facilities (Ayurveda, Homeopathy, Unani, Siddha, Naturopathy), dental-only clinics, diagnostic or pathology labs, prosthetics and eye-only clinics do NOT have these modern clinical capabilities unless the text explicitly names the modern service; generic Ayurveda terms (Chikitsa, Panchakarma, Kayachikitsa, Shalya, Salakya) are NOT obstetrics, emergency or icu. Definitions: csection = explicit caesarean, C-section, LSCS or obstetric surgery. obstetrics = explicit delivery, maternity, labour or childbirth care (a gynaecology-only clinic with no delivery does NOT count). icu = explicit ICU, NICU, PICU or critical care unit. blood_bank = explicit on-site blood bank or blood transfusion service. emergency = explicit emergency, casualty, accident and emergency, or trauma care (a plain 24x7 or open-24-hours mention alone does NOT count). Give each confidence 0-1, reserving above 0.8 for explicit statements. evidence = one short verbatim quote (max 150 chars) for the strongest claim, else empty. Text: ', claim_text), responseFormat => '{"type": "json_schema", "json_schema": {"name": "caps", "strict": true, "schema": {"type": "object", "additionalProperties": false, "properties": {"csection_claimed": {"type": "boolean"}, "csection_confidence": {"type": "number"}, "obstetrics_claimed": {"type": "boolean"}, "obstetrics_confidence": {"type": "number"}, "icu_claimed": {"type": "boolean"}, "icu_confidence": {"type": "number"}, "blood_bank_claimed": {"type": "boolean"}, "blood_bank_confidence": {"type": "number"}, "emergency_claimed": {"type": "boolean"}, "emergency_confidence": {"type": "number"}, "evidence": {"type": "string"}}, "required": ["csection_claimed", "csection_confidence", "obstetrics_claimed", "obstetrics_confidence", "icu_claimed", "icu_confidence", "blood_bank_claimed", "blood_bank_confidence", "emergency_claimed", "emergency_confidence", "evidence"]}}}') AS raw_json
  FROM src
),
parsed AS (SELECT *, from_json(raw_json, 'STRUCT<csection_claimed: BOOLEAN, csection_confidence: DOUBLE, obstetrics_claimed: BOOLEAN, obstetrics_confidence: DOUBLE, icu_claimed: BOOLEAN, icu_confidence: DOUBLE, blood_bank_claimed: BOOLEAN, blood_bank_confidence: DOUBLE, emergency_claimed: BOOLEAN, emergency_confidence: DOUBLE, evidence: STRING>') AS c FROM ext)
SELECT facility_id, name, latitude, longitude, pincode_raw, state_raw,
  trim(regexp_replace(upper(coalesce(state_raw,'')), '[^A-Z0-9]+', ' ')) AS norm_state_facility,
  c.csection_claimed, c.csection_confidence, c.obstetrics_claimed, c.obstetrics_confidence,
  c.icu_claimed, c.icu_confidence, c.blood_bank_claimed, c.blood_bank_confidence,
  c.emergency_claimed, c.emergency_confidence, c.evidence, claim_text
FROM parsed;
