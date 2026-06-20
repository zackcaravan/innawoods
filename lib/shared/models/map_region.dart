// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

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
    // Bounding box for DEM prefetch + accurate "fit bounds" camera framing.
    // Falls back to a 4°×3° envelope around the center when omitted.
    this.minLng,
    this.minLat,
    this.maxLng,
    this.maxLat,
    // Whether the .pmtiles asset for this region has actually been built
    // and uploaded to the release. False = catalog placeholder; the maps
    // screen shows it greyed out with a "Coming soon" badge instead of
    // letting the user tap into a 404. Lets us ship the full state list
    // ahead of the extracts so users see the roadmap.
    this.built = true,
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

  /// Optional explicit bounding box for the region. When any is null we
  /// derive a 4°×3° envelope around the center via [bbox].
  final double? minLng;
  final double? minLat;
  final double? maxLng;
  final double? maxLat;

  /// Whether the asset at [pmtilesUrl] actually exists yet. New regions land
  /// in the catalog with `built: false` so the UI lists them as "coming
  /// soon"; the extract pipeline flips this to true once the file is
  /// uploaded to the release. See `tools/build-regions/` for the workflow.
  final bool built;

  /// Resolved [minLng, minLat, maxLng, maxLat] — uses provided fields when set,
  /// otherwise a 4°×3° box centered on [centerLng]/[centerLat].
  List<double> get bbox {
    if (minLng != null &&
        minLat != null &&
        maxLng != null &&
        maxLat != null) {
      return [minLng!, minLat!, maxLng!, maxLat!];
    }
    return [
      centerLng - 2.0,
      centerLat - 1.5,
      centerLng + 2.0,
      centerLat + 1.5,
    ];
  }

  String get sizeLabel {
    final mb = approxSizeBytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }
}
