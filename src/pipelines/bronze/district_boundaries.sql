-- bronze.district_boundaries: geoBoundaries India ADM2 (2021, open CC-BY), 735 districts.
-- The source GeoJSON is converted to NDJSON (one district per line, geometry as a JSON
-- string) and staged at /Volumes/mdp/bronze/raw/ind_adm2_ndjson.json by the one-time
-- helper src/pipelines/bronze/fetch_geoboundaries.py (see README "Local prerequisites").
CREATE OR REPLACE TABLE mdp.bronze.district_boundaries AS
SELECT shape_name, shape_id, shape_iso, geometry_json
FROM read_files('/Volumes/mdp/bronze/raw/ind_adm2_ndjson.json', format => 'json', multiLine => false);
