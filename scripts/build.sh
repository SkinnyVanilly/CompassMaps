#!/usr/bin/env bash
# Builds the map files and publishes them as one GitHub Release with a catalog.json.
# Runs on GitHub Actions (.github/workflows/build-maps.yml); the map data never passes through anyone's computer.
#
# Needs: pmtiles (go-pmtiles), python3 with shapely, gh (logged in through GH_TOKEN), curl, sha256sum.
# Env:   REPO (owner/name), ONLY (optional, space-separated country ids to build, e.g. "no se"), DRY_RUN=1 (sizes only).
set -euo pipefail

REPO="${REPO:?set REPO=owner/name}"
ONLY="${ONLY:-}"
DRY_RUN="${DRY_RUN:-0}"
WORK="${WORK:-$PWD/work}"
NE_URL="https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson"
MAX_ASSET=$((2 * 1024 * 1024 * 1024 - 1)) # GitHub release files must be under 2 GiB

mkdir -p "$WORK/regions" "$WORK/out"
rm -rf "$WORK/prev"

# The newest Protomaps world build (OpenStreetMap data, ODbL)
BUILD_KEY=$(curl -fsS https://build-metadata.protomaps.dev/builds.json | python3 -c 'import json,sys; print(json.load(sys.stdin)[-1]["key"])')
SRC="https://build.protomaps.com/${BUILD_KEY}"
DATA_DATE="${BUILD_KEY%.pmtiles}"                                  # e.g. 20261107
DATA_DATE="${DATA_DATE:0:4}-${DATA_DATE:4:2}-${DATA_DATE:6:2}"     # e.g. 2026-11-07
TAG="maps-${DATA_DATE}"
echo "Source: $SRC  ->  release $TAG"

[ -f "$WORK/ne.geojson" ] || curl -fsSL -o "$WORK/ne.geojson" "$NE_URL"

ENTRIES="$WORK/entries.jsonl"; : > "$ENTRIES"

if [ "$DRY_RUN" != 1 ]; then
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release $TAG already exists: adding / replacing files in it"
    rm -rf "$WORK/prev"; mkdir -p "$WORK/prev"
    gh release download "$TAG" --repo "$REPO" --pattern catalog.json --dir "$WORK/prev" 2>/dev/null || true
  else
    gh release create "$TAG" --repo "$REPO" --title "Maps from OpenStreetMap data of $DATA_DATE" \
      --notes "Offline map files for My Training Compass. Map data © OpenStreetMap contributors (ODbL), built with Protomaps. See LICENSE." \
      --draft
  fi
fi

# build_one <id> <name> <file> <maxzoom> <bounds-json> [extract args...]
build_one() {
  local id="$1" name="$2" file="$3" maxzoom="$4" bounds="$5"; shift 5
  local out="$WORK/out/$file"
  echo "::group::$name ($file, detail $maxzoom)"
  if [ "$DRY_RUN" = 1 ]; then
    pmtiles extract "$SRC" "$out" --maxzoom="$maxzoom" --download-threads=4 --dry-run "$@" 2>&1 | tail -1
    echo "::endgroup::"; return
  fi
  pmtiles extract "$SRC" "$out" --maxzoom="$maxzoom" --download-threads=4 "$@" 2>&1 | tail -2
  local bytes sha
  bytes=$(stat -c %s "$out")
  if [ "$bytes" -gt "$MAX_ASSET" ]; then
    echo "::error::$name is $bytes bytes, over GitHub's 2 GiB limit: split it into parts or lower its maxzoom in countries.json"
    rm -f "$out"; echo "::endgroup::"; return 1
  fi
  pmtiles verify "$out" >/dev/null
  sha=$(sha256sum "$out" | cut -d' ' -f1)
  gh release upload "$TAG" "$out" --repo "$REPO" --clobber
  rm -f "$out"
  python3 - "$id" "$name" "$file" "$maxzoom" "$bounds" "$bytes" "$sha" "$DATA_DATE" "$REPO" "$TAG" >> "$ENTRIES" <<'PY'
import json, sys
i, name, file, mz, bounds, size, sha, date, repo, tag = sys.argv[1:]
print(json.dumps({"id": i, "name": name, "file": file, "maxzoom": int(mz), "bounds": json.loads(bounds),
                  "bytes": int(size), "sha256": sha, "dataDate": date,
                  "url": f"https://github.com/{repo}/releases/download/{tag}/{file}"}))
PY
  echo "::endgroup::"
}

wanted() { [ -z "$ONLY" ] || [[ " $ONLY " == *" $1 "* ]]; }

# World backdrop
W_FILE=$(python3 -c 'import json; print(json.load(open("countries.json"))["world"]["file"])')
W_ZOOM=$(python3 -c 'import json; print(json.load(open("countries.json"))["world"]["maxzoom"])')
if wanted world; then build_one world "World backdrop" "$W_FILE" "$W_ZOOM" '[-180,-85.05,180,85.05]'; fi

# Countries
python3 -c 'import json; [print(c["id"], c["ne"], c["maxzoom"], c["name"]) for c in json.load(open("countries.json"))["countries"]]' |
while read -r id ne mz name; do
  wanted "$id" || continue
  region="$WORK/regions/$id.geojson"
  bounds=$(python3 scripts/make-region.py "$WORK/ne.geojson" "$ne" "$region" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["bounds"]))')
  build_one "$id" "$name" "$id.pmtiles" "$mz" "$bounds" --region="$region"
done

[ "$DRY_RUN" = 1 ] && exit 0

# catalog.json: what the app lists (fetched from releases/latest/download/catalog.json)
python3 - "$ENTRIES" "$DATA_DATE" "$TAG" "$WORK/out/catalog.json" "$WORK/prev/catalog.json" <<'PY'
import json, os, sys, datetime
by_id = {}
if os.path.exists(sys.argv[5]):  # a re-run that built only some files keeps the others in the list
    for e in json.load(open(sys.argv[5])).get("files", []): by_id[e["id"]] = e
for l in open(sys.argv[1]):
    if l.strip():
        e = json.loads(l); by_id[e["id"]] = e
entries = sorted(by_id.values(), key=lambda e: (e["id"] != "world", e["name"]))
cat = {"format": 1, "release": sys.argv[3], "dataDate": sys.argv[2],
       "built": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
       "attribution": "© OpenStreetMap contributors (ODbL) · Protomaps",
       "copyright": "https://www.openstreetmap.org/copyright",
       "files": entries}
json.dump(cat, open(sys.argv[4], "w"), indent=1, ensure_ascii=False)
PY
gh release upload "$TAG" "$WORK/out/catalog.json" --repo "$REPO" --clobber
gh release edit "$TAG" --repo "$REPO" --draft=false --latest
echo "Published $TAG with $(wc -l < "$ENTRIES") map files"
