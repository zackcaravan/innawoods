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
