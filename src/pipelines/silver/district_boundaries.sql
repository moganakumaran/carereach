-- silver.district_boundaries: parsed district polygons as GEOMETRY (SRID 4326) + centroids.
-- Spatial joins must align SRID: use st_setsrid(st_point(lon,lat), 4326) for the point side.
-- NOTE: geoBoundaries ADM2 carries no parent state, so district_name is not unique across
-- states. Facility->district assignment uses ST_Contains (location-correct regardless of
-- name); the STATE used for the NFHS-5 join comes from the facility side (address/pincode).
CREATE OR REPLACE TABLE mdp.silver.district_boundaries AS
SELECT
  shape_name AS district_name,
  shape_id,
  trim(regexp_replace(upper(trim(shape_name)), '[^A-Z0-9]+', ' ')) AS norm_district,
  st_geomfromgeojson(geometry_json)                       AS geom,
  st_y(st_centroid(st_geomfromgeojson(geometry_json)))    AS centroid_lat,
  st_x(st_centroid(st_geomfromgeojson(geometry_json)))    AS centroid_lon,
  geometry_json
FROM mdp.bronze.district_boundaries;
