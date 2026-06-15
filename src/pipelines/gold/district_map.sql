-- gold.district_map: desert scores + a representative centroid per district, for the app map.
-- Joins district_desert (NFHS spine) to geoBoundaries centroids on the normalized district name
-- (averaged when a name repeats). Districts with no centroid match still appear (null lat/lon).
CREATE OR REPLACE TABLE mdp.gold.district_map AS
WITH cen AS (
  SELECT norm_district, avg(centroid_lat) AS lat, avg(centroid_lon) AS lon
  FROM mdp.silver.district_boundaries GROUP BY norm_district
)
SELECT d.norm_state, d.norm_district, trim(d.district_name) AS district_name, trim(d.state_ut) AS state_ut,
       d.desert_score, d.burden_score, d.accessibility_score,
       d.verified_obstetric, d.total_facilities, d.nfhs_small_sample_cols,
       c.lat AS centroid_lat, c.lon AS centroid_lon
FROM mdp.gold.district_desert d
LEFT JOIN cen c ON c.norm_district = d.norm_district;
