#!/usr/bin/env python3
"""Flip `built: false` → `built: true` for the named regions in both
sources of truth (regions.json + lib/shared/services/region_catalog.dart).
Idempotent — flipping an already-true entry is a no-op.

Usage:
    ./mark-built.py us-or us-id us-mt ...
    ./mark-built.py --all                # everything in the manifest
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
MANIFEST = HERE / "regions.json"
CATALOG = REPO_ROOT / "lib/shared/services/region_catalog.dart"


def update_manifest(ids: set[str]) -> int:
    data = json.loads(MANIFEST.read_text())
    flipped = 0
    for r in data["regions"]:
        if r["id"] in ids and r.get("built") is False:
            r["built"] = True
            flipped += 1
    MANIFEST.write_text(json.dumps(data, indent=2) + "\n")
    return flipped


def update_catalog(ids: set[str]) -> int:
    """In region_catalog.dart, each MapRegion is bounded by `id: '...'`
    and the next `),`. We find the block, drop `built: false,` if present,
    and trust the default `built: true` from the model constructor.

    This is more invasive than the JSON edit but keeps the file readable
    (no `built: true` clutter for default-true entries).
    """
    src = CATALOG.read_text()
    # Match each MapRegion(...) block by id.
    pattern = re.compile(
        r"(MapRegion\(\s*\n\s*id: '([^']+)'.*?\n\s*\),)",
        re.DOTALL,
    )
    flipped = 0

    def replace_block(match: re.Match) -> str:
        nonlocal flipped
        block = match.group(1)
        rid = match.group(2)
        if rid not in ids:
            return block
        new_block, n = re.subn(
            r"\s*built: false,\s*\n",
            "\n          ",  # restore newline + indent for the closing `),`
            block,
        )
        if n > 0:
            # If we removed `built: false,` we want the closing `),` on
            # its own line with 8-space indent (the convention in this
            # file). The above subn might have left odd whitespace; tidy.
            new_block = re.sub(r"\n\s+\),\s*$", "\n        ),", new_block)
            flipped += 1
            return new_block
        return block

    new_src = pattern.sub(replace_block, src)
    CATALOG.write_text(new_src)
    return flipped


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print("Usage: mark-built.py <region-id> ... | --all", file=sys.stderr)
        return 2

    if args == ["--all"]:
        data = json.loads(MANIFEST.read_text())
        ids = {r["id"] for r in data["regions"]}
    else:
        ids = set(args)

    m = update_manifest(ids)
    c = update_catalog(ids)
    print(f"manifest: flipped {m} entries to built=true")
    print(f"catalog:  removed {c} built:false lines (default is true)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
