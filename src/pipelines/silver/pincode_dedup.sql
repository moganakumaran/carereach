-- silver.pincode_district: India Post directory deduplicated to ONE ROW PER PINCODE
-- (AGENTS.md gotcha #1). Bronze grain is post office, so a naive facility-pincode join
-- fans out; here we pick each pincode's majority district (by office count) and the
-- centroid of its post offices. Used to map facility pincode -> district and as a
-- coordinate fallback for facilities missing lat/long.
CREATE OR REPLACE TABLE mdp.silver.pincode_district AS
WITH base AS (
  SELECT
    pincode,
    trim(district)  AS district,
    trim(statename) AS statename,
    trim(regexp_replace(upper(trim(district)),  '[^A-Z0-9]+', ' ')) AS norm_district,
    trim(regexp_replace(upper(trim(statename)), '[^A-Z0-9]+', ' ')) AS norm_state,
    try_cast(latitude  AS DOUBLE) AS lat,
    try_cast(longitude AS DOUBLE) AS lon
  FROM mdp.bronze.pincode
  WHERE pincode IS NOT NULL
),
agg AS (
  SELECT
    pincode, norm_district, norm_state,
    max(district)  AS district,
    max(statename) AS statename,
    count(*)       AS n_offices,
    avg(lat)       AS lat,
    avg(lon)       AS lon
  FROM base
  GROUP BY pincode, norm_district, norm_state
),
ranked AS (
  SELECT *, row_number() OVER (PARTITION BY pincode ORDER BY n_offices DESC, norm_district) AS rn
  FROM agg
)
SELECT pincode, district, statename, norm_district, norm_state, n_offices, lat, lon
FROM ranked
WHERE rn = 1;
