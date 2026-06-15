-- gold.facility: one decision-ready row per facility. Capability flags carry the extracted
-- claim, its confidence, and an INTERIM verified flag (claimed AND confidence >= 0.8). The
-- Phase 6 capability-verification agent will replace this confidence proxy with adjudicated
-- verification. evidence_ref points back to the source record + the exact claim sentence.
CREATE OR REPLACE TABLE mdp.gold.facility AS
SELECT
  facility_id, name, latitude, longitude,
  district_name, district_norm, state_norm, geo_inferred,
  csection_claimed,   csection_confidence,   (csection_claimed   AND csection_confidence   >= 0.8) AS csection_verified,
  obstetrics_claimed, obstetrics_confidence, (obstetrics_claimed AND obstetrics_confidence >= 0.8) AS obstetrics_verified,
  icu_claimed,        icu_confidence,        (icu_claimed        AND icu_confidence        >= 0.8) AS icu_verified,
  blood_bank_claimed, blood_bank_confidence, (blood_bank_claimed AND blood_bank_confidence >= 0.8) AS blood_bank_verified,
  emergency_claimed,  emergency_confidence,  (emergency_claimed  AND emergency_confidence  >= 0.8) AS emergency_verified,
  evidence AS claim_sentence,
  named_struct('facility_id', facility_id, 'claim_sentence', evidence) AS evidence_ref
FROM mdp.silver.facility;
