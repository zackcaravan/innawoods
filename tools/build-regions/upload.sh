#!/usr/bin/env bash
# Upload extracted PMTiles to the GitHub v1.0 release. Separate from
# extract.sh so you can verify file sizes locally before paying the
# bandwidth to push them.
#
# Usage:
#   ./upload.sh                # all files in out/ that match the manifest
#   ./upload.sh us-or us-id    # specific region ids
#   ./upload.sh --all          # alias for no-args
#
# After uploading, REMEMBER:
#   1. Flip `built: false` → `built: true` in regions.json
#   2. Flip the corresponding entry in
#      lib/shared/services/region_catalog.dart
#   3. Commit + push
#   4. Users see the region move from "Coming soon" to "Available now"
#      on next app open (no app rebuild required — the catalog is
#      compiled in but URLs point at the live release).

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/regions.json"
OUT_DIR="$HERE/out"
REPO="zackcaravan/innawoods"
RELEASE="v1.0"

if ! command -v gh >/dev/null; then
  echo "ERROR: gh CLI not installed" >&2
  exit 1
fi

declare -a TARGET_IDS=()
if [[ $# -eq 0 || "$1" == "--all" ]]; then
  # Default: everything that exists in out/ and matches the manifest.
  mapfile -t TARGET_IDS < <(jq -r '.regions[].id' "$MANIFEST")
else
  TARGET_IDS=("$@")
fi

uploaded=0
skipped=0
for id in "${TARGET_IDS[@]}"; do
  row="$(jq --arg id "$id" '.regions[] | select(.id == $id)' "$MANIFEST")"
  if [[ -z "$row" || "$row" == "null" ]]; then
    echo "✗ $id: not in manifest"
    continue
  fi
  filename="$(echo "$row" | jq -r '.filename')"
  file="$OUT_DIR/$filename"
  if [[ ! -f "$file" ]]; then
    echo "↷ $id: not extracted yet ($file missing) — skipping"
    skipped=$((skipped + 1))
    continue
  fi
  size="$(du -h "$file" | cut -f1)"
  echo "↑ $id: $filename ($size)"
  if gh release upload "$RELEASE" "$file" --clobber --repo "$REPO"; then
    uploaded=$((uploaded + 1))
    echo "  ✓ uploaded"
  else
    echo "  ✗ upload failed" >&2
  fi
done

echo
echo "Uploaded: $uploaded · Skipped: $skipped"
if (( uploaded > 0 )); then
  echo
  echo "REMEMBER to flip 'built: false' → 'built: true' for the uploaded"
  echo "regions in:"
  echo "  - tools/build-regions/regions.json"
  echo "  - lib/shared/services/region_catalog.dart"
  echo "and commit + push."
fi
