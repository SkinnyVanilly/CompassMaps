# CompassMaps

Offline map files for **My Training Compass**: a world backdrop and one file per country, made from
OpenStreetMap data, so the app's maps work with no internet.

Map data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright) (ODbL), built with
[Protomaps](https://protomaps.com). See [LICENSE](LICENSE).

## What is here

| File | What it is |
|---|---|
| `countries.json` | The list of files to build: the world backdrop and the countries, with their detail level |
| `scripts/build.sh` | Builds every file and publishes them as one GitHub Release with a `catalog.json` |
| `scripts/make-region.py` | A country's outline (Natural Earth), widened 5 km, used to cut the country out |
| `.github/workflows/build-maps.yml` | Runs the build on GitHub, every third month and on demand |

The map files themselves are not in the repository: they are files of a **Release**
(e.g. `maps-2026-11-07`), each under GitHub's 2 GiB limit.

## For the app

- The list: `https://github.com/SkinnyVanilly/CompassMaps/releases/latest/download/catalog.json`
- Each entry: `id`, `name`, `file`, `maxzoom`, `bounds` (west, south, east, north), `bytes`, `sha256`,
  `dataDate`, `url` (the file to download).
- The files are [PMTiles](https://docs.protomaps.com/pmtiles/) v3 archives of the Protomaps basemap
  (vector tiles). The countries go to detail 14, where every footpath and track is in; draw them past it.
- Show "© OpenStreetMap contributors" with the map.

## Building

On GitHub: Actions → **Build map files** → Run workflow (optionally only some ids, e.g. `no se`, or
"sizes only"). It cuts each file straight out of the newest Protomaps world build, so the 139 GB world
file is never downloaded, and nothing passes through anyone's computer.

Locally (needs `pmtiles`, Python with `shapely`, and `gh` logged in):

```sh
REPO=SkinnyVanilly/CompassMaps DRY_RUN=1 bash scripts/build.sh   # sizes only
REPO=SkinnyVanilly/CompassMaps ONLY="no" bash scripts/build.sh   # build and upload Norway
```

## Adding a country

Add a line to `countries.json` with its Natural Earth code (`ADM0_A3`, e.g. `DEU` for Germany) and run the
workflow with only that id. A country over 2 GiB at detail 14 (the USA, Canada) has to be split into parts first.

## Sizes (OpenStreetMap data of 2026-11-07)

| File | Size |
|---|---|
| World backdrop (detail 6) | 45 MB |
| Norway (with Svalbard) | 1.7 GB |
| Sweden | 1.4 GB |
| Finland | 993 MB |
| Denmark | 293 MB |
| Iceland | 151 MB |
