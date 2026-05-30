/// A downloadable map region. The .pmtiles file holds the vector basemap for
/// that area; the app reads it from internal storage when the region is active.
class MapRegion {
  const MapRegion({
    required this.id,
    required this.name,
    required this.pmtilesUrl,
    required this.approxSizeBytes,
    required this.centerLng,
    required this.centerLat,
    this.minZoom = 0,
    this.maxZoom = 15,
  });

  /// Short stable id used as the on-disk filename (`<id>.pmtiles`).
  final String id;

  /// Human-readable name shown in the UI.
  final String name;

  /// HTTPS URL the app downloads the .pmtiles from.
  final String pmtilesUrl;

  /// Approximate size for UI display (bytes).
  final int approxSizeBytes;

  /// Suggested camera center when this region becomes active.
  final double centerLng;
  final double centerLat;

  /// Tile zoom range available in the bundle.
  final int minZoom;
  final int maxZoom;

  String get sizeLabel {
    final mb = approxSizeBytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }
}
