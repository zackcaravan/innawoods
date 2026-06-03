import '../models/map_region.dart';

/// The hardcoded list of regions the user can download. The id becomes the
/// on-disk filename, so keep ids stable + lowercase-with-dashes.
///
/// PMTiles are hosted as GitHub release assets on this project's repo. To add
/// a new region:
///   1. Build with `pmtiles extract` against a Protomaps daily dump.
///   2. Upload to the latest release:
///      `gh release upload vX.Y /path/to/us-XX.pmtiles --clobber`
///   3. Add an entry here with `pmtilesUrl` pointing at that asset.
class RegionCatalog {
  const RegionCatalog();

  /// Base URL for the v1.0 release assets. New regions append to the same
  /// release until we cut v1.1 etc.
  static const _releaseBase =
      'https://github.com/zackcaravan/innawoods/releases/download/v1.0';

  List<MapRegion> get all => const [
        MapRegion(
          id: 'us-wa',
          name: 'Washington',
          pmtilesUrl: '$_releaseBase/wa.pmtiles',
          approxSizeBytes: 570 * 1024 * 1024, // ~570 MB
          centerLng: -120.5, centerLat: 47.5,
          minLng: -124.85, minLat: 45.55,
          maxLng: -116.92, maxLat: 49.00,
        ),
        // The entries below are PLACEHOLDERS — build + upload each region's
        // .pmtiles to the release before relying on these.
        MapRegion(
          id: 'us-or',
          name: 'Oregon',
          pmtilesUrl: '$_releaseBase/or.pmtiles',
          approxSizeBytes: 480 * 1024 * 1024,
          centerLng: -120.5, centerLat: 44.0,
          minLng: -124.57, minLat: 41.99,
          maxLng: -116.46, maxLat: 46.30,
        ),
        MapRegion(
          id: 'us-id',
          name: 'Idaho',
          pmtilesUrl: '$_releaseBase/id.pmtiles',
          approxSizeBytes: 380 * 1024 * 1024,
          centerLng: -114.5, centerLat: 44.5,
          minLng: -117.24, minLat: 41.99,
          maxLng: -111.04, maxLat: 49.00,
        ),
        MapRegion(
          id: 'us-mt',
          name: 'Montana',
          pmtilesUrl: '$_releaseBase/mt.pmtiles',
          approxSizeBytes: 520 * 1024 * 1024,
          centerLng: -110.0, centerLat: 46.5,
          minLng: -116.05, minLat: 44.36,
          maxLng: -104.04, maxLat: 49.00,
        ),
        MapRegion(
          id: 'us-co',
          name: 'Colorado',
          pmtilesUrl: '$_releaseBase/co.pmtiles',
          approxSizeBytes: 460 * 1024 * 1024,
          centerLng: -105.5, centerLat: 39.0,
          minLng: -109.06, minLat: 36.99,
          maxLng: -102.04, maxLat: 41.00,
        ),
      ];

  MapRegion? byId(String id) {
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }
}
