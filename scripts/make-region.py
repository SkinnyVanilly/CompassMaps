"""Write one country's outline, widened a little, as a GeoJSON region for `pmtiles extract --region`.

Usage: python3 make-region.py <natural-earth-countries.geojson> <ADM0_A3> <out.geojson> [margin_km]

The outline comes from Natural Earth (public domain). It is widened by margin_km (default 5) so paths and
coast near the border are not cut off, then simplified to keep the file small.
"""
import json
import sys

from shapely.geometry import mapping, shape
from shapely.ops import unary_union

src, code, out = sys.argv[1], sys.argv[2], sys.argv[3]
margin_km = float(sys.argv[4]) if len(sys.argv) > 4 else 5.0

with open(src, encoding="utf-8") as f:
    data = json.load(f)

parts = [shape(ft["geometry"]) for ft in data["features"] if ft["properties"].get("ADM0_A3") == code]
if not parts:
    sys.exit(f"no country with ADM0_A3 = {code} in {src}")

geom = unary_union(parts)
deg = margin_km / 111.0  # about 111 km per degree; wide enough for a margin, also in the north
geom = geom.buffer(deg, resolution=4).simplify(deg / 4)

with open(out, "w", encoding="utf-8") as f:
    json.dump({"type": "Feature", "properties": {"ADM0_A3": code}, "geometry": mapping(geom)}, f)

minx, miny, maxx, maxy = geom.bounds
print(json.dumps({"bounds": [round(minx, 4), round(miny, 4), round(maxx, 4), round(maxy, 4)]}))
