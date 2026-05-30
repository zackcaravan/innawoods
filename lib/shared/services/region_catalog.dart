import '../models/map_region.dart';

/// The hardcoded list of regions the user can download. The id becomes the
/// on-disk filename, so keep ids stable + lowercase-with-dashes.
///
/// IMPORTANT: there is no public, stable per-state .pmtiles CDN. Build each
/// region's .pmtiles from a Protomaps daily extract (via the `pmtiles extract`
/// CLI + a bounding-box GeoJSON) and host it yourself — a GitHub release asset,
/// an S3/R2 bucket, etc. — then put that URL here. The `pmtilesUrl` values
/// below are PLACEHOLDERS that will 404 until you point them at real files.
class RegionCatalog {
  const RegionCatalog();

  List<MapRegion> get all => const [
        MapRegion(
          id: 'us-wa',
          name: 'Washington',
          pmtilesUrl:
              'https://build.protomaps.com/extracts/us-wa.pmtiles',
          approxSizeBytes: 570 * 1024 * 1024, // ~570 MB
          centerLng: -120.5, centerLat: 47.5,
        ),
        MapRegion(
          id: 'us-or',
          name: 'Oregon',
          pmtilesUrl:
              'https://build.protomaps.com/extracts/us-or.pmtiles',
          approxSizeBytes: 480 * 1024 * 1024,
          centerLng: -120.5, centerLat: 44.0,
        ),
        MapRegion(
          id: 'us-id',
          name: 'Idaho',
          pmtilesUrl:
              'https://build.protomaps.com/extracts/us-id.pmtiles',
          approxSizeBytes: 380 * 1024 * 1024,
          centerLng: -114.5, centerLat: 44.5,
        ),
        MapRegion(
          id: 'us-mt',
          name: 'Montana',
          pmtilesUrl:
              'https://build.protomaps.com/extracts/us-mt.pmtiles',
          approxSizeBytes: 520 * 1024 * 1024,
          centerLng: -110.0, centerLat: 46.5,
        ),
        MapRegion(
          id: 'us-co',
          name: 'Colorado',
          pmtilesUrl:
              'https://build.protomaps.com/extracts/us-co.pmtiles',
          approxSizeBytes: 460 * 1024 * 1024,
          centerLng: -105.5, centerLat: 39.0,
        ),
      ];

  MapRegion? byId(String id) {
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }
}
