// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:latlong2/latlong.dart';

/// A single recorded breadcrumb point — position + optional altitude + time.
class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lng,
    required this.t,
    this.alt,
  });

  final double lat;
  final double lng;
  final double? alt; // meters
  final DateTime t;

  LatLng get latLng => LatLng(lat, lng);

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        if (alt != null) 'alt': alt,
        't': t.toIso8601String(),
      };

  factory TrackPoint.fromJson(Map<String, dynamic> j) => TrackPoint(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        alt: (j['alt'] as num?)?.toDouble(),
        t: DateTime.parse(j['t'] as String),
      );
}

/// A finalized recorded track — your private breadcrumb of a trip.
/// Tracks are stored locally on the device; they don't sync to the crew.
/// (Sharing is opt-in via the share/export-GPX actions.)
class Track {
  const Track({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.endedAt,
    required this.points,
  });

  final String id;
  final String name;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<TrackPoint> points;

  Duration get duration => endedAt.difference(startedAt);

  /// Total along-track distance in meters (great-circle between consecutive
  /// points; cheap enough for typical track sizes).
  double get distanceMeters {
    if (points.length < 2) return 0;
    const d = Distance();
    double total = 0;
    for (var i = 1; i < points.length; i++) {
      total += d.as(LengthUnit.Meter, points[i - 1].latLng, points[i].latLng);
    }
    return total;
  }

  /// Sum of upward altitude differences between consecutive points (meters).
  /// Naive — no smoothing — but a useful order-of-magnitude reading.
  double get elevationGainM {
    double gain = 0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1].alt;
      final b = points[i].alt;
      if (a == null || b == null) continue;
      final dz = b - a;
      if (dz > 0) gain += dz;
    }
    return gain;
  }

  /// Maximum recorded altitude (meters), or null if no altitudes were sampled.
  double? get maxAltM {
    double? mx;
    for (final p in points) {
      if (p.alt == null) continue;
      if (mx == null || p.alt! > mx) mx = p.alt;
    }
    return mx;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'points': [for (final p in points) p.toJson()],
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        name: j['name'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        endedAt: DateTime.parse(j['endedAt'] as String),
        points: [
          for (final p in (j['points'] as List))
            TrackPoint.fromJson(Map<String, dynamic>.from(p as Map))
        ],
      );
}
