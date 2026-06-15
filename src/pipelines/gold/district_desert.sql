-- gold.district_desert: one row per NFHS-5 district (706) = the burden spine, so districts
-- with ZERO facilities (the worst deserts) are included. Facilities are attributed by
-- (state, district) with verified alias maps for the high-volume naming mismatches
-- (MAHARASHTRA->MAHARASTRA, DELHI->NCT OF DELHI, Telangana/24-Parganas spellings, ...).
--
-- desert_score = 0.5*burden + 0.35*(1 - norm_verified_coverage) + 0.15*accessibility   (AGENTS.md)
--   burden_score        : mean of low-institutional-birth, low-ANC4, high-anaemia, high-stunting (min-max 0-1, 1=worst)
--   norm_verified_coverage : min-max of verified OBSTETRIC facility count (verified = claim AND conf>=0.8, interim)
--   accessibility_score : 1 - min-max(total facilities)  (travel-time proxy; more facilities = better access)
-- All inputs normalized 0-1; missing burden components coalesced to 0.5 so desert_score is never null.
CREATE OR REPLACE TABLE mdp.gold.district_desert AS
WITH state_alias(src, dst) AS (VALUES
  ('MAHARASHTRA','MAHARASTRA'), ('DELHI','NCT OF DELHI'), ('JAMMU AND KASHMIR','JAMMU KASHMIR'),
  ('TAMILNADU','TAMIL NADU'), ('ANDAMAN AND NICOBAR ISLANDS','ANDAMAN NICOBAR ISLANDS'),
  ('THE DADRA AND NAGAR HAVELI AND DAMAN AND DIU','DADRA AND NAGAR HAVELI DAMAN AND DIU'),
  ('ORISSA','ODISHA'), ('UTTRANCHAL','UTTARAKHAND'), ('U T OF PUDUCHERRY','PUDUCHERRY')
),
dist_alias(state, src, dst) AS (VALUES
  ('TELANGANA','HYDRABAD','HYDERABAD'), ('TELANGANA','RANGAREDDY','RANGA REDDY'),
  ('TELANGANA','MEDCHAL','MEDCHAL MALKAJGIRI'), ('TELANGANA','WARANGAL U','WARANGAL URBAN'),
  ('WEST BENGAL','NORTH TWENTY FOUR PARGANAS','NORTH TWENTY FOUR PARGANA'),
  ('WEST BENGAL','SOUTH TWENTY FOUR PARGANAS','SOUTH TWENTY FOUR PARGANA')
),
fac AS (
  SELECT f.*, coalesce(sa.dst, f.state_norm) AS nfhs_state
  FROM mdp.gold.facility f LEFT JOIN state_alias sa ON sa.src = f.state_norm
),
fac2 AS (
  SELECT f.*, coalesce(da.dst, f.district_norm) AS nfhs_district
  FROM fac f LEFT JOIN dist_alias da ON da.state = f.nfhs_state AND da.src = f.district_norm
),
cov AS (
  SELECT nfhs_state, nfhs_district,
    count(*) AS total_facilities,
    count_if(obstetrics_verified) AS verified_obstetric,
    count_if(csection_verified)   AS verified_csection
  FROM fac2 WHERE nfhs_district IS NOT NULL
  GROUP BY nfhs_state, nfhs_district
),
base AS (
  SELECT n.norm_state, n.norm_district, n.district_name, n.state_ut, n.nfhs_small_sample_cols,
    n.institutional_birth_5y_pct AS inst_birth,
    n.mothers_who_had_at_least_4_anc_visits_lb5y_pct AS anc4,
    n.all_w15_49_who_are_anaemic_pct AS anaemia,
    n.child_u5_who_are_stunted_height_for_age_18_pct AS stunting,
    coalesce(c.total_facilities, 0)  AS total_facilities,
    coalesce(c.verified_obstetric, 0) AS verified_obstetric,
    coalesce(c.verified_csection, 0)  AS verified_csection
  FROM mdp.silver.nfhs5_district n
  LEFT JOIN cov c ON c.nfhs_state = n.norm_state AND c.nfhs_district = n.norm_district
),
mm AS (
  SELECT *,
    (inst_birth - min(inst_birth) OVER()) / nullif(max(inst_birth) OVER() - min(inst_birth) OVER(), 0) AS inst_birth_mm,
    (anc4       - min(anc4) OVER())       / nullif(max(anc4) OVER()       - min(anc4) OVER(), 0)       AS anc4_mm,
    (anaemia    - min(anaemia) OVER())    / nullif(max(anaemia) OVER()    - min(anaemia) OVER(), 0)    AS anaemia_mm,
    (stunting   - min(stunting) OVER())   / nullif(max(stunting) OVER()   - min(stunting) OVER(), 0)   AS stunting_mm,
    (verified_obstetric - min(verified_obstetric) OVER()) / nullif(max(verified_obstetric) OVER() - min(verified_obstetric) OVER(), 0) AS cov_mm,
    (total_facilities   - min(total_facilities) OVER())   / nullif(max(total_facilities) OVER()   - min(total_facilities) OVER(), 0)   AS access_mm
  FROM base
),
scored AS (
  SELECT *,
    ( coalesce(1 - inst_birth_mm, 0.5) + coalesce(1 - anc4_mm, 0.5)
      + coalesce(anaemia_mm, 0.5) + coalesce(stunting_mm, 0.5) ) / 4.0 AS burden_score_raw,
    coalesce(cov_mm, 0)        AS norm_verified_coverage_raw,
    1 - coalesce(access_mm, 0) AS accessibility_score_raw
  FROM mm
)
SELECT
  norm_state, norm_district, district_name, state_ut,
  inst_birth, anc4, anaemia, stunting, nfhs_small_sample_cols,
  total_facilities, verified_obstetric, verified_csection,
  round(burden_score_raw, 4)              AS burden_score,
  round(norm_verified_coverage_raw, 4)    AS norm_verified_coverage,
  round(accessibility_score_raw, 4)       AS accessibility_score,
  round(0.50 * burden_score_raw
      + 0.35 * (1 - norm_verified_coverage_raw)
      + 0.15 * accessibility_score_raw, 4) AS desert_score
FROM scored;
