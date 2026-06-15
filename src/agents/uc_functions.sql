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
