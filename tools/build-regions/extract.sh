#!/usr/bin/env bash
# Extract one or more PMTiles regions from the Protomaps planet file.
#
# Usage:
#   ./extract.sh                # all unbuilt regions
#   ./extract.sh us-or us-id    # specific regions by id
#   ./extract.sh --all          # every region (rebuild everything)
#
# Requires:
#   - `pmtiles` CLI from go-pmtiles (https://github.com/protomaps/go-pmtiles)
#     Install: `go install github.com/protomaps/go-pmtiles@latest`
#     Binary lands as `go-pmtiles`; symlink it to `pmtiles` for the
#     script to find it: `ln -sf ~/go/bin/go-pmtiles ~/go/bin/pmtiles`
#   - `jq` for JSON parsing
#   - PLANET_PMTILES env var pointing at the source archive. Two modes:
#       LOCAL: /path/to/planet.pmtiles (faster, but ~120 GB on disk)
#       REMOTE: https://build.protomaps.com/<YYYYMMDD>.pmtiles
#               (no download required — pmtiles streams only the bytes
#                needed via HTTP range requests). DEFAULT if unset:
#                today's build URL.
#
# Output: tools/build-regions/out/<filename>.pmtiles
# The upload step is separate — see upload.sh.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/regions.json"
OUT_DIR="$HERE/out"
mkdir -p "$OUT_DIR"

# Source: local file path OR remote URL. Default = today's build.
PLANET="${PLANET_PMTILES:-https://build.protomaps.com/$(date -u +%Y%m%d).pmtiles}"
if [[ "$PLANET" =~ ^https?:// ]]; then
  echo "Source: remote ($PLANET)"
  echo "  Streaming via HTTP range requests; no local download required."
  # Verify it's reachable before kicking off long-running extracts.
  status="$(curl -I -s -o /dev/null -w '%{http_code}' "$PLANET")"
  if [[ "$status" != "200" ]]; then
    echo "ERROR: planet URL returned HTTP $status" >&2
    echo "Pick a recent date from https://build.protomaps.com/ and set" >&2
    echo "  export PLANET_PMTILES=https://build.protomaps.com/<YYYYMMDD>.pmtiles" >&2
    exit 1
  fi
elif [[ ! -f "$PLANET" ]]; then
  echo "ERROR: planet PMTiles not found at $PLANET" >&2
  echo "Either: download it locally, or use the default remote URL by" >&2
  echo "unsetting PLANET_PMTILES." >&2
  exit 1
else
  echo "Source: local ($PLANET, $(du -h "$PLANET" | cut -f1))"
fi

if ! command -v pmtiles >/dev/null; then
  echo "ERROR: 'pmtiles' CLI not in PATH" >&2
  echo "Install: go install github.com/protomaps/go-pmtiles@latest" >&2
  echo "Then: ln -sf ~/go/bin/go-pmtiles ~/go/bin/pmtiles" >&2
  exit 1
fi
if ! command -v jq >/dev/null; then
  echo "ERROR: jq not installed" >&2
  exit 1
fi

# Decide which regions to extract.
declare -a TARGET_IDS=()
if [[ $# -eq 0 ]]; then
  # Default: only unbuilt regions.
  mapfile -t TARGET_IDS < <(jq -r '.regions[] | select(.built == false) | .id' "$MANIFEST")
  echo "Extracting unbuilt regions (use --all to rebuild built ones too)"
elif [[ "$1" == "--all" ]]; then
  mapfile -t TARGET_IDS < <(jq -r '.regions[].id' "$MANIFEST")
else
  TARGET_IDS=("$@")
fi

if [[ ${#TARGET_IDS[@]} -eq 0 ]]; then
  echo "Nothing to extract — all regions in manifest are marked built."
  exit 0
fi

echo "Output: $OUT_DIR"
echo "Regions: ${TARGET_IDS[*]}"
echo

for id in "${TARGET_IDS[@]}"; do
  # Pull the manifest row for this id.
  row="$(jq --arg id "$id" '.regions[] | select(.id == $id)' "$MANIFEST")"
  if [[ -z "$row" || "$row" == "null" ]]; then
    echo "✗ $id: not in manifest, skipping"
    continue
  fi

  name="$(echo "$row" | jq -r '.name')"
  filename="$(echo "$row" | jq -r '.filename')"
  bbox="$(echo "$row" | jq -r '.bbox | join(",")')"
  max_zoom="$(echo "$row" | jq -r '.maxZoom // empty')"

  out_file="$OUT_DIR/$filename"
  echo "→ $id ($name)"
  echo "  bbox: $bbox"

  # Build pmtiles extract args.
  args=(extract "$PLANET" "$out_file" --bbox="$bbox")
  if [[ -n "$max_zoom" ]]; then
    args+=(--maxzoom="$max_zoom")
    echo "  maxzoom: $max_zoom"
  fi

  # Run it.
  if pmtiles "${args[@]}"; then
    size="$(du -h "$out_file" | cut -f1)"
    bytes="$(stat -c%s "$out_file")"
    echo "  ✓ $size ($bytes bytes)"
    # Hard fail if over GitHub's 2 GB per-asset limit.
    if (( bytes > 2147483648 )); then
      echo "  ⚠ FILE EXCEEDS 2 GB — upload to GitHub releases will fail." >&2
      echo "    Lower maxZoom in regions.json or split the region." >&2
    fi
  else
    echo "  ✗ pmtiles extract failed for $id" >&2
  fi
  echo
done

echo "Done. Files in: $OUT_DIR"
echo "Next: tools/build-regions/upload.sh <region-id-or-all>"
