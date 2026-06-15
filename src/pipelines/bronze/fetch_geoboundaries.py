#!/usr/bin/env python3
"""One-time fetch of geoBoundaries India ADM2 district polygons into the UC volume.

This is a manual prerequisite for the silver spatial join (run once per workspace,
re-run only to refresh boundaries). It is intentionally outside the bundle job graph
because it needs outbound internet to GitHub.

  python3 src/pipelines/bronze/fetch_geoboundaries.py --profile mdp

Steps: resolve the geoBoundaries gbOpen IND ADM2 GeoJSON download URL, download it,
convert to NDJSON (one feature per line; geometry serialized as a JSON string so
Spark's st_geomfromgeojson can parse it), and upload to
/Volumes/mdp/bronze/raw/ind_adm2_ndjson.json. Then build the tables with:
  databricks bundle run silver_transform -t dev   (tasks: ingest_boundaries -> clean_boundaries)
"""
import argparse, json, subprocess, sys, tempfile, urllib.request

API = "https://www.geoboundaries.org/api/current/gbOpen/IND/ADM2/"
VOLUME_PATH = "dbfs:/Volumes/mdp/bronze/raw/ind_adm2_ndjson.json"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", default="mdp")
    args = ap.parse_args()

    meta = json.load(urllib.request.urlopen(API, timeout=60))
    if isinstance(meta, list):
        meta = meta[0]
    url = meta["gjDownloadURL"]
    print(f"geoBoundaries {meta.get('boundaryType')} {meta.get('boundaryYearRepresented')} -> {url}")

    geojson = json.load(urllib.request.urlopen(url, timeout=180))
    feats = geojson["features"]
    print(f"features: {len(feats)}")

    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        for f in feats:
            p = f.get("properties", {})
            fh.write(json.dumps({
                "shape_name": p.get("shapeName"),
                "shape_id": p.get("shapeID"),
                "shape_iso": p.get("shapeISO"),
                "geometry_json": json.dumps(f.get("geometry")),
            }) + "\n")
        local = fh.name

    print(f"uploading {local} -> {VOLUME_PATH}")
    subprocess.run(
        ["databricks", "fs", "cp", local, VOLUME_PATH, "--overwrite", "-p", args.profile],
        check=True,
    )
    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
