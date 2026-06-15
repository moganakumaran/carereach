-- gold.region_signals: TWO INDEPENDENT signals per region, at four geo levels.
--   A) care_gap_score      — how little VERIFIED capability exists (the AGENTS.md desert score).
--   B) data_confidence_score — how much we can TRUST signal A here (facility_count, high-confidence
--      share, geocoded share, evidence/field coverage). LOW = data-poor, NOT "no gap".
-- Aggregated from FACILITY grain (gold.facility is already one row per facility — no PIN fan-out).
-- Facilities are attributed to NFHS districts with the same state+district ALIAS maps used in
-- district_desert (so attribution matches, ~98%). District level is built on the NFHS 706-district
-- spine so zero-facility high-burden districts surface as HIGH gap + LOW confidence (data-poor).
CREATE OR REPLACE TABLE mdp.gold.region_signals AS
WITH state_alias(src, dst) AS (VALUES
  ('MAHARASHTRA','MAHARASTRA'), ('DELHI','NCT OF DELHI'), ('JAMMU AND KASHMIR','JAMMU KASHMIR'),
  ('TAMILNADU','TAMIL NADU'), ('ANDAMAN AND NICOBAR ISLANDS','ANDAMAN NICOBAR ISLANDS'),
  ('THE DADRA AND NAGAR HAVELI AND DAMAN AND DIU','DADRA AND NAGAR HAVELI DAMAN AND DIU'),
  ('ORISSA','ODISHA'), ('UTTRANCHAL','UTTARAKHAND'), ('U T OF PUDUCHERRY','PUDUCHERRY')),
dist_alias(state, src, dst) AS (VALUES
  ('TELANGANA','HYDRABAD','HYDERABAD'), ('TELANGANA','RANGAREDDY','RANGA REDDY'),
  ('TELANGANA','MEDCHAL','MEDCHAL MALKAJGIRI'), ('TELANGANA','WARANGAL U','WARANGAL URBAN'),
  ('WEST BENGAL','NORTH TWENTY FOUR PARGANAS','NORTH TWENTY FOUR PARGANA'),
  ('WEST BENGAL','SOUTH TWENTY FOUR PARGANAS','SOUTH TWENTY FOUR PARGANA')),
fac0 AS (
  SELECT g.facility_id, g.state_norm AS raw_state, g.district_norm AS raw_district,
         nullif(trim(regexp_replace(upper(b.address_city), '[^A-Z0-9]+', ' ')), '') AS city_norm,
         try_cast(b.address_zipOrPostcode AS BIGINT) AS pincode,
         (NOT g.geo_inferred) AS geocoded, g.geo_inferred,
         g.obstetrics_verified AS verified,
         (greatest(coalesce(g.obstetrics_confidence,0), coalesce(g.csection_confidence,0),
                   coalesce(g.icu_confidence,0), coalesce(g.blood_bank_confidence,0),
                   coalesce(g.emergency_confidence,0)) >= 0.8) AS high_conf,
         (g.claim_sentence IS NOT NULL AND length(trim(g.claim_sentence)) > 0) AS has_evidence
  FROM mdp.gold.facility g
  -- dedup bronze to ONE row per facility before joining (bronze has ~11 duplicate unique_ids;
  -- joining raw would fan out facility grain and corrupt both scores — the exact PIN-grain trap).
  LEFT JOIN (SELECT unique_id, max(address_city) AS address_city, max(address_zipOrPostcode) AS address_zipOrPostcode
             FROM mdp.bronze.facilities GROUP BY unique_id) b ON b.unique_id = g.facility_id
),
fac1 AS (SELECT f.*, coalesce(sa.dst, raw_state) AS state_norm FROM fac0 f LEFT JOIN state_alias sa ON sa.src = f.raw_state),
fac2 AS (SELECT f.*, coalesce(da.dst, raw_district) AS district_norm FROM fac1 f LEFT JOIN dist_alias da ON da.state = f.state_norm AND da.src = f.raw_district),
fac AS (
  SELECT f.facility_id, f.state_norm, f.district_norm, f.city_norm, f.pincode,
         f.geocoded, f.geo_inferred, f.verified, f.high_conf, f.has_evidence, dd.burden_score AS burden
  FROM fac2 f
  LEFT JOIN mdp.gold.district_desert dd ON dd.norm_state = f.state_norm AND dd.norm_district = f.district_norm
),
fa_dist AS (
  SELECT state_norm, district_norm, count(*) fc, count_if(verified) vc, count_if(high_conf) hc,
         count_if(geocoded) gc, count_if(geo_inferred) ic, count_if(has_evidence) ec
  FROM fac GROUP BY state_norm, district_norm
),
lvl_district AS (
  SELECT 'district' AS geo_level, dd.norm_state || '|' || dd.norm_district AS region_key,
         trim(dd.district_name) AS region_label, trim(dd.state_ut) AS state_ut,
         coalesce(fa.fc,0) AS facility_count, coalesce(fa.vc,0) AS verified_count,
         coalesce(fa.hc,0) AS high_conf_count, coalesce(fa.gc,0) AS geocoded_count,
         coalesce(fa.ic,0) AS inferred_count, coalesce(fa.ec,0) AS evidence_count,
         dd.burden_score AS burden, dd.desert_score AS care_gap_in
  FROM mdp.gold.district_desert dd
  LEFT JOIN fa_dist fa ON fa.state_norm = dd.norm_state AND fa.district_norm = dd.norm_district
),
lvl_state AS (
  SELECT 'state', state_norm, state_norm, state_norm, count(*), count_if(verified), count_if(high_conf),
         count_if(geocoded), count_if(geo_inferred), count_if(has_evidence), avg(burden), CAST(NULL AS DOUBLE)
  FROM fac WHERE state_norm IS NOT NULL GROUP BY state_norm
),
lvl_city AS (
  SELECT 'city', state_norm || '|' || city_norm, city_norm, state_norm, count(*), count_if(verified), count_if(high_conf),
         count_if(geocoded), count_if(geo_inferred), count_if(has_evidence), avg(burden), CAST(NULL AS DOUBLE)
  FROM fac WHERE city_norm IS NOT NULL GROUP BY state_norm, city_norm
),
lvl_pincode AS (
  SELECT 'pincode', CAST(pincode AS STRING), CAST(pincode AS STRING), max(state_norm), count(*), count_if(verified), count_if(high_conf),
         count_if(geocoded), count_if(geo_inferred), count_if(has_evidence), avg(burden), CAST(NULL AS DOUBLE)
  FROM fac WHERE pincode IS NOT NULL GROUP BY pincode
),
u AS (
  SELECT * FROM lvl_district
  UNION ALL SELECT * FROM lvl_state
  UNION ALL SELECT * FROM lvl_city
  UNION ALL SELECT * FROM lvl_pincode
),
norm AS (
  SELECT *,
    (ln(1+facility_count) - min(ln(1+facility_count)) OVER (PARTITION BY geo_level))
      / nullif(max(ln(1+facility_count)) OVER (PARTITION BY geo_level) - min(ln(1+facility_count)) OVER (PARTITION BY geo_level), 0) AS count_score,
    (verified_count - min(verified_count) OVER (PARTITION BY geo_level))
      / nullif(max(verified_count) OVER (PARTITION BY geo_level) - min(verified_count) OVER (PARTITION BY geo_level), 0) AS verified_norm,
    (burden - min(burden) OVER (PARTITION BY geo_level))
      / nullif(max(burden) OVER (PARTITION BY geo_level) - min(burden) OVER (PARTITION BY geo_level), 0) AS burden_norm
  FROM u
)
SELECT geo_level, region_key, region_label, state_ut,
       facility_count, verified_count, high_conf_count, geocoded_count, inferred_count, evidence_count,
       round(coalesce(care_gap_in, 0.55*coalesce(burden_norm,0.5) + 0.45*(1 - coalesce(verified_norm,0))), 4) AS care_gap_score,
       round(least(1.0, greatest(0.0,
            0.40*coalesce(count_score,0)
          + 0.25*coalesce(high_conf_count/nullif(facility_count,0),0)
          + 0.20*coalesce(geocoded_count/nullif(facility_count,0),0)
          + 0.15*coalesce(evidence_count/nullif(facility_count,0),0))), 4) AS data_confidence_score,
       round(burden,4) AS burden_score
FROM norm;
