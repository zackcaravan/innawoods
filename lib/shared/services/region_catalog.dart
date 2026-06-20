// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import '../models/map_region.dart';

/// The hardcoded list of regions the user can download.
///
/// File-size estimates were extrapolated from WA's actual 569 MB build at
/// max zoom 14, scaled by land area + a density factor that accounts for
/// road / POI density (dense Northeast scales heavier per square mile,
/// the Mountain West and Plains scale lighter). Real builds will likely
/// vary ±25%; the catalog gets corrected to actual size on first upload.
///
/// 18 regions cover 44 of the lower 48 + Alaska. Hawaii and the dense
/// Mid-Atlantic / Lower New England urban corridor are deferred to v1.5+
/// — the off-grid-crew audience for those areas is small enough that
/// shipping a 50-state-complete catalog isn't worth the extract labor
/// until someone actually asks.
///
/// To add a new region:
///   1. Build with `tools/build-regions/extract.sh <region-id>` — uses the
///      bbox from `tools/build-regions/regions.json` (same source the
///      catalog reads from in spirit).
///   2. Upload to the v1.0 release:
///      `gh release upload v1.0 us-XX.pmtiles --clobber`
///   3. Flip `built: false` to `built: true` in this file.
class RegionCatalog {
  const RegionCatalog();

  /// Base URL for the v1.0 release assets. New regions append to the same
  /// release until we cut v1.1 etc.
  static const _releaseBase =
      'https://github.com/zackcaravan/innawoods/releases/download/v1.0';

  List<MapRegion> get all => const [
        // ─────────────────────────────────────────────────────────────
        // WESTERN BACKCOUNTRY — state-by-state, the primary audience.
        // High demand from hunters, riders, backcountry skiers.
        // ─────────────────────────────────────────────────────────────
        MapRegion(
          id: 'us-wa',
          name: 'Washington',
          pmtilesUrl: '$_releaseBase/wa.pmtiles',
          approxSizeBytes: 569 * 1024 * 1024,
          centerLng: -120.5, centerLat: 47.5,
          minLng: -124.85, minLat: 45.55,
          maxLng: -116.92, maxLat: 49.00,
        ),
        MapRegion(
          id: 'us-or',
          name: 'Oregon',
          pmtilesUrl: '$_releaseBase/or.pmtiles',
          approxSizeBytes: 720 * 1024 * 1024,
          centerLng: -120.5, centerLat: 44.0,
          minLng: -124.57, minLat: 41.99,
          maxLng: -116.46, maxLat: 46.30,
          built: false,
        ),
        MapRegion(
          id: 'us-id',
          name: 'Idaho',
          pmtilesUrl: '$_releaseBase/id.pmtiles',
          approxSizeBytes: 620 * 1024 * 1024,
          centerLng: -114.5, centerLat: 44.5,
          minLng: -117.24, minLat: 41.99,
          maxLng: -111.04, maxLat: 49.00,
          built: false,
        ),
        MapRegion(
          id: 'us-mt',
          name: 'Montana',
          pmtilesUrl: '$_releaseBase/mt.pmtiles',
          approxSizeBytes: 950 * 1024 * 1024,
          centerLng: -110.0, centerLat: 46.5,
          minLng: -116.05, minLat: 44.36,
          maxLng: -104.04, maxLat: 49.00,
          built: false,
        ),
        MapRegion(
          id: 'us-wy',
          name: 'Wyoming',
          pmtilesUrl: '$_releaseBase/wy.pmtiles',
          approxSizeBytes: 550 * 1024 * 1024,
          centerLng: -107.5, centerLat: 43.0,
          minLng: -111.06, minLat: 40.99,
          maxLng: -104.05, maxLat: 45.01,
          built: false,
        ),
        MapRegion(
          id: 'us-co',
          name: 'Colorado',
          pmtilesUrl: '$_releaseBase/co.pmtiles',
          approxSizeBytes: 780 * 1024 * 1024,
          centerLng: -105.5, centerLat: 39.0,
          minLng: -109.06, minLat: 36.99,
          maxLng: -102.04, maxLat: 41.00,
          built: false,
        ),
        MapRegion(
          id: 'us-ut',
          name: 'Utah',
          pmtilesUrl: '$_releaseBase/ut.pmtiles',
          approxSizeBytes: 650 * 1024 * 1024,
          centerLng: -111.5, centerLat: 39.5,
          minLng: -114.05, minLat: 36.99,
          maxLng: -109.04, maxLat: 42.00,
          built: false,
        ),
        MapRegion(
          id: 'us-nv',
          name: 'Nevada',
          pmtilesUrl: '$_releaseBase/nv.pmtiles',
          approxSizeBytes: 620 * 1024 * 1024,
          centerLng: -117.0, centerLat: 39.0,
          minLng: -120.01, minLat: 35.00,
          maxLng: -114.04, maxLat: 42.00,
          built: false,
        ),
        MapRegion(
          id: 'us-ca',
          name: 'California',
          pmtilesUrl: '$_releaseBase/ca.pmtiles',
          approxSizeBytes: 1450 * 1024 * 1024,
          centerLng: -119.5, centerLat: 37.0,
          minLng: -124.49, minLat: 32.53,
          maxLng: -114.13, maxLat: 42.01,
          built: false,
        ),
        MapRegion(
          id: 'us-az-nm',
          name: 'Arizona + New Mexico',
          pmtilesUrl: '$_releaseBase/az-nm.pmtiles',
          approxSizeBytes: 1350 * 1024 * 1024,
          centerLng: -109.0, centerLat: 34.0,
          minLng: -114.82, minLat: 31.33,
          maxLng: -103.00, maxLat: 37.00,
          built: false,
        ),
        MapRegion(
          id: 'us-ak',
          name: 'Alaska',
          pmtilesUrl: '$_releaseBase/ak.pmtiles',
          approxSizeBytes: 1900 * 1024 * 1024,
          centerLng: -150.0, centerLat: 64.0,
          // Bbox doesn't cross the antimeridian — the Aleutian Islands tail
          // past -180 will get clipped at extract time; that's acceptable
          // for v1. If users in the western Aleutians complain we'll split
          // Alaska into north/south or add a separate Aleutian region.
          minLng: -180.0, minLat: 51.21,
          maxLng: -129.97, maxLat: 71.50,
          // Capped lower so the extract fits under GitHub's 2 GB per-asset
          // limit. AK at zoom 14 would be ~3.5 GB; zoom 12 is enough
          // resolution for backcountry use (single trails visible).
          maxZoom: 12,
          built: false,
        ),

        // ─────────────────────────────────────────────────────────────
        // EASTERN MOUNTAINS — grouped because users routinely operate
        // across state lines (a hunter in NH crosses into VT or ME).
        // ─────────────────────────────────────────────────────────────
        MapRegion(
          id: 'us-ne-north',
          name: 'Northern New England',
          pmtilesUrl: '$_releaseBase/ne-north.pmtiles',
          approxSizeBytes: 480 * 1024 * 1024,
          centerLng: -71.5, centerLat: 44.5,
          minLng: -73.43, minLat: 42.70,
          maxLng: -66.95, maxLat: 47.46,
          built: false,
        ),
        MapRegion(
          id: 'us-ny-pa',
          name: 'New York + Pennsylvania',
          pmtilesUrl: '$_releaseBase/ny-pa.pmtiles',
          approxSizeBytes: 1200 * 1024 * 1024,
          centerLng: -77.5, centerLat: 42.5,
          minLng: -80.52, minLat: 39.72,
          maxLng: -71.86, maxLat: 45.02,
          built: false,
        ),
        MapRegion(
          id: 'us-appalachia-s',
          name: 'Southern Appalachia',
          pmtilesUrl: '$_releaseBase/appalachia-s.pmtiles',
          approxSizeBytes: 1500 * 1024 * 1024,
          centerLng: -82.0, centerLat: 37.0,
          minLng: -90.31, minLat: 33.84,
          maxLng: -75.24, maxLat: 40.64,
          built: false,
        ),
        MapRegion(
          id: 'us-midwest-upper',
          name: 'Upper Midwest',
          pmtilesUrl: '$_releaseBase/midwest-upper.pmtiles',
          approxSizeBytes: 1300 * 1024 * 1024,
          centerLng: -89.0, centerLat: 45.0,
          minLng: -97.24, minLat: 41.70,
          maxLng: -82.42, maxLat: 49.38,
          built: false,
        ),

        // ─────────────────────────────────────────────────────────────
        // REMAINING GROUPS — lower backcountry density per square mile
        // but still wanted by hunters / overlanders. Shipped after the
        // western tier proves demand for non-WA regions.
        // ─────────────────────────────────────────────────────────────
        MapRegion(
          id: 'us-plains',
          name: 'Plains',
          pmtilesUrl: '$_releaseBase/plains.pmtiles',
          approxSizeBytes: 1400 * 1024 * 1024,
          centerLng: -96.5, centerLat: 42.0,
          minLng: -104.06, minLat: 35.99,
          maxLng: -89.10, maxLat: 49.00,
          built: false,
        ),
        MapRegion(
          id: 'us-tx-ok-ar',
          name: 'Texas + Oklahoma + Arkansas',
          pmtilesUrl: '$_releaseBase/tx-ok-ar.pmtiles',
          approxSizeBytes: 1700 * 1024 * 1024,
          centerLng: -97.5, centerLat: 32.5,
          minLng: -106.65, minLat: 25.83,
          maxLng: -89.64, maxLat: 37.00,
          built: false,
        ),
        MapRegion(
          id: 'us-southeast',
          name: 'Southeast',
          pmtilesUrl: '$_releaseBase/southeast.pmtiles',
          approxSizeBytes: 1500 * 1024 * 1024,
          centerLng: -85.5, centerLat: 30.5,
          minLng: -94.04, minLat: 24.40,
          maxLng: -78.54, maxLat: 35.22,
          built: false,
        ),
      ];

  /// Subset that's actually downloadable today. UI uses this for the
  /// primary "Available regions" list; everything else lands in a
  /// "Coming soon" section.
  List<MapRegion> get available => all.where((r) => r.built).toList();

  /// Subset whose .pmtiles files haven't been built and uploaded yet.
  List<MapRegion> get comingSoon => all.where((r) => !r.built).toList();

  MapRegion? byId(String id) {
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }
}
