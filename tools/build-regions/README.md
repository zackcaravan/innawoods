# Region build pipeline

How to extract a new PMTiles region and ship it to users without an app
rebuild.

## One-time setup

1. **Install go-pmtiles CLI:**
   ```bash
   go install github.com/protomaps/go-pmtiles/v2@latest
   # binary lands in $GOPATH/bin (usually ~/go/bin); add to PATH if needed
   pmtiles version  # sanity check
   ```

2. **Install `jq` and `gh`** (likely already installed):
   ```bash
   sudo dnf install jq gh
   gh auth status
   ```

3. **Download the Protomaps planet PMTiles** (the source we extract from):
   ```bash
   # Pick the latest daily build at https://maps.protomaps.com/builds
   # File is ~120 GB; download takes hours over residential broadband.
   curl -L -o /var/cache/protomaps/planet.pmtiles \
     https://build.protomaps.com/<DATE>.pmtiles

   # Point the pipeline at it
   export PLANET_PMTILES=/var/cache/protomaps/planet.pmtiles
   # or symlink into tools/build-regions/planet.pmtiles
   ```

   Run this every ~3 months to refresh OSM data (new trails, road
   updates, POI changes). The catalog URL doesn't change between
   refreshes — just upload the new file with `--clobber`.

## Build one region

```bash
cd tools/build-regions
./extract.sh us-or      # extract Oregon by id
./upload.sh us-or       # push it to the GitHub v1.0 release
```

Then flip `built: false` → `built: true` in:
- `regions.json` (this directory)
- `lib/shared/services/region_catalog.dart`

Commit + push. Users see the region move from "Coming soon" to
"Available now" the next time they open the maps screen — **no app
rebuild required**, because the URL is already in the compiled
catalog.

## Build everything unbuilt

```bash
./extract.sh            # extracts all built:false regions
./upload.sh             # pushes everything that exists in out/
```

Then bulk-edit the two source files to flip the `built` flags.

## Filesize sanity

| Region | Estimated | GitHub 2 GB limit |
|---|---|---|
| WA (built) | 569 MB actual | ✓ |
| OR | ~720 MB | ✓ |
| ID | ~620 MB | ✓ |
| MT | ~950 MB | ✓ |
| WY | ~550 MB | ✓ |
| CO | ~780 MB | ✓ |
| UT | ~650 MB | ✓ |
| NV | ~620 MB | ✓ |
| CA | ~1.4 GB | ✓ |
| AZ + NM | ~1.3 GB | ✓ |
| AK | ~1.9 GB (zoom 12) | ⚠ tight |
| Northern NE | ~480 MB | ✓ |
| NY + PA | ~1.2 GB | ✓ |
| Southern Appalachia | ~1.5 GB | ✓ |
| Upper Midwest | ~1.3 GB | ✓ |
| Plains | ~1.4 GB | ✓ |
| TX + OK + AR | ~1.7 GB | ⚠ tight |
| Southeast | ~1.5 GB | ✓ |

Estimates extrapolated from WA's actual 569 MB. Real builds will vary
±25% — `extract.sh` warns if the output crosses 2 GB.

**If a region exceeds 2 GB:**
- Lower `maxZoom` in `regions.json` from 14 → 13 (cuts size ~3-4×)
- Or split the region into two (north/south, east/west)

## Phased rollout plan

Don't build all 17 unbuilt regions at once. Suggested phasing:

| Phase | Regions | When |
|---|---|---|
| **v1 launch (DONE)** | WA | shipped |
| **v1.1** | OR, ID, MT, WY, CO | within 1 week of public launch |
| **v1.2** | UT, NV, CA, AZ-NM, AK | when v1.1 download data justifies |
| **v1.3** | Northern New England, NY-PA, Southern Appalachia | weeks 4-6 |
| **v1.4** | Upper Midwest, TX-OK-AR, Plains, Southeast | weeks 6-8 |
| **v1.5+** | HI, Mid-Atlantic + Lower NE | only if users ask |

Reasons for phasing:

1. **Launch isn't gated on 17 extracts.** Ship WA, get users, learn.
2. **Download data tells you what to build next.** If 80% of v1.1
   downloads are CO + MT, ID and OR were the right early-tier picks.
3. **Pipeline iteration.** First few extracts will reveal config
   issues (size estimates, zoom caps, etc.). Better to fix them after
   5 regions than 17.

## How users discover regions

The maps screen shows two sections:

- **Available now** — `built: true` regions, downloadable.
- **Coming soon** — `built: false` regions, greyed out with a "SOON"
  badge, non-interactive. Signals the roadmap without letting users
  tap into a 404.

When you flip a `built` flag and push the catalog change, the user's
next app open moves that region from Coming Soon → Available Now. They
don't need a new APK/IPA build — the URL it downloads from is already
hardcoded in the binary.

## Notes per region

### Alaska
- `maxZoom: 12` because zoom 14 would be ~3.5 GB (over GitHub's limit).
- Zoom 12 = ~150m per pixel, still resolves individual trails. Fine
  for backcountry; no city-level detail (which Alaska barely has anyway).
- Bbox doesn't cross the antimeridian — Aleutians past -180 get clipped.
  If users in Adak / Attu complain, split AK into Mainland + Aleutians.

### Multi-state groups
- Northern New England (ME+NH+VT): hunters cross these lines routinely.
- NY+PA: Adirondacks span both; Allegheny too.
- Southern Appalachia: VA-WV-NC-TN-KY share the same mountain corridor.
- Upper Midwest: MI UP, Northern WI, BWCA in MN — backcountry country.
- Plains: low backcountry use but shipped as one for big-game hunters.

### Deferred regions
- **Hawaii** — small islands, low off-grid-crew demand. Add when one
  asks.
- **Mid-Atlantic urban (NJ+DE+MD)** — backcountry audience near zero.
- **Lower New England (MA+CT+RI)** — same.

Combined these would be ~500 MB; trivial to add later as a single
`us-coastal-ne-mid-atl` region if demand emerges.

## Refresh cadence

Re-extract every ~3 months to pick up:
- New / changed OSM trails (frequent in popular areas)
- Updated road geometries
- New POIs
- Fixed errors in the prior daily build

To refresh:
1. Re-download the latest planet PMTiles
2. `./extract.sh --all` (rebuilds every region)
3. `./upload.sh --all` (re-uploads with `--clobber`)

URLs don't change, so users get the fresh data automatically next time
they re-download a region. (Or proactively: tag a v1.1 release in
GitHub and add a "Refresh" button to the maps screen — not built yet,
add when user feedback says it's needed.)
