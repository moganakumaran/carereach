-- silver.facility: one row per India facility with its extracted capability claims plus an
-- assigned district. District is resolved by exact spatial containment first
-- (ST_Contains over geoBoundaries ADM2), falling back to the pincode->district lookup when
-- the point is missing/out-of-range or lands in no polygon. geo_inferred=true means the
-- district did NOT come from a spatial match (AGENTS.md: flag, never drop). Must stay ~10k rows.
CREATE OR REPLACE TABLE mdp.silver.facility AS
WITH f AS (
  SELECT *,
    CASE
      WHEN latitude IS NOT NULL AND longitude IS NOT NULL
       AND latitude  BETWEEN 6  AND 38      -- India bounding box sanity check
       AND longitude BETWEEN 68 AND 98
      THEN st_setsrid(st_point(longitude, latitude), 4326)
    END AS pt
  FROM mdp.silver.facility_claims
),
spatial AS (   -- exact polygon containment; dedup to one district per facility
  SELECT f.facility_id, b.district_name AS geo_district, b.norm_district AS geo_norm_district, b.shape_id
  FROM f
  JOIN mdp.silver.district_boundaries b
    ON f.pt IS NOT NULL AND st_contains(b.geom, f.pt)
  QUALIFY row_number() OVER (PARTITION BY f.facility_id ORDER BY b.shape_id) = 1
),
pin AS (       -- pincode -> district fallback (lookup is unique on pincode, so no fan-out)
  SELECT f.facility_id, p.district AS pin_district, p.norm_district AS pin_norm_district, p.norm_state AS pin_norm_state
  FROM f
  LEFT JOIN mdp.silver.pincode_district p ON try_cast(f.pincode_raw AS BIGINT) = p.pincode
)
SELECT
  f.facility_id, f.name, f.latitude, f.longitude, f.pincode_raw, f.state_raw, f.norm_state_facility,
  f.csection_claimed, f.csection_confidence, f.obstetrics_claimed, f.obstetrics_confidence,
  f.icu_claimed, f.icu_confidence, f.blood_bank_claimed, f.blood_bank_confidence,
  f.emergency_claimed, f.emergency_confidence, f.evidence,
  s.geo_district, s.geo_norm_district, s.shape_id,
  pin.pin_district, pin.pin_norm_district, pin.pin_norm_state,
  coalesce(s.geo_norm_district, pin.pin_norm_district)          AS district_norm,
  coalesce(s.geo_district,      pin.pin_district)               AS district_name,
  coalesce(pin.pin_norm_state,  f.norm_state_facility)          AS state_norm,
  (s.facility_id IS NULL)                                       AS geo_inferred
FROM f
LEFT JOIN spatial s ON f.facility_id = s.facility_id
LEFT JOIN pin      ON f.facility_id = pin.facility_id
-- source has ~11 duplicate unique_ids; keep exactly one row per facility (prefer the spatial match)
QUALIFY row_number() OVER (PARTITION BY f.facility_id ORDER BY s.shape_id NULLS LAST) = 1;
