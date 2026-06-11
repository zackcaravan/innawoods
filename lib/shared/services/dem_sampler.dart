// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';

/// Samples elevation at lat/lng points from the in-app DEM tile server
/// (`/dem/{z}/{x}/{y}.png`, terrarium-encoded). Decoded tiles cached in
/// memory — a few hundred KB even for long routes.
///
/// Build with the *base URL* of the in-app server (the port changes per app
/// launch, so this is reconstructed each time the map opens).
class DemSampler {
  DemSampler({required this.baseUrl, this.zoom = 10});

  /// `http://127.0.0.1:<port>` (no trailing slash, no `/dem`).
  final String baseUrl;

  /// The DEM source's max zoom — Terrarium tiles top out at 15; the in-app
  /// proxy caps at 10. Lower zoom = wider sample area per tile = fewer fetches.
  final int zoom;

  final http.Client _http = http.Client();
  final LinkedHashMap<String, img.Image> _cache = LinkedHashMap();
  static const _cacheMax = 64;

  /// Returns elevation (in meters) at the given lat/lng, or `null` if the
  /// tile couldn't be fetched/decoded.
  Future<double?> elevationAt(double lat, double lng) async {
    final n = math.pow(2, zoom).toDouble();
    // Web-Mercator tile coords.
    final xTileF = (lng + 180) / 360 * n;
    final yTileF = (1 -
            math.log(math.tan(lat * math.pi / 180) +
                    1 / math.cos(lat * math.pi / 180)) /
                math.pi) /
        2 *
        n;
    final xTile = xTileF.floor();
    final yTile = yTileF.floor();
    final key = '$zoom/$xTile/$yTile';

    var tile = _cache.remove(key);
    if (tile != null) {
      _cache[key] = tile; // touch (MRU)
    } else {
      try {
        final resp = await _http
            .get(Uri.parse('$baseUrl/dem/$zoom/$xTile/$yTile.png'))
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) return null;
        tile = img.decodePng(resp.bodyBytes);
        if (tile == null) return null;
        _cache[key] = tile;
        if (_cache.length > _cacheMax) _cache.remove(_cache.keys.first);
      } catch (_) {
        return null;
      }
    }

    // Convert lat/lng to pixel within the 256×256 tile.
    final px = (((xTileF - xTile) * tile.width)).floor().clamp(0, tile.width - 1);
    final py = (((yTileF - yTile) * tile.height)).floor().clamp(0, tile.height - 1);
    final p = tile.getPixel(px, py);
    final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
    // Terrarium decode: elevation = (R*256 + G + B/256) - 32768
    return (r * 256.0 + g + b / 256.0) - 32768;
  }

  /// Sample elevations evenly along a polyline. Returns one value per sample
  /// (null where the DEM lookup failed). `n` >= 2.
  Future<List<double?>> sampleAlong(List<LatLng> points, {int n = 80}) async {
    if (points.length < 2) return const [];
    // Pre-compute cumulative distances so we can interpolate at each sample.
    const d = Distance();
    final cum = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cum.add(cum.last + d.as(LengthUnit.Meter, points[i - 1], points[i]));
    }
    final total = cum.last;
    if (total == 0) return const [];

    final out = <double?>[];
    for (var i = 0; i < n; i++) {
      final t = i / (n - 1);
      final targetM = t * total;
      // Find segment whose cumulative distance brackets targetM.
      var seg = 1;
      while (seg < cum.length && cum[seg] < targetM) {
        seg++;
      }
      if (seg >= cum.length) seg = cum.length - 1;
      final segStartM = cum[seg - 1];
      final segLenM = cum[seg] - segStartM;
      final localT = segLenM == 0 ? 0.0 : (targetM - segStartM) / segLenM;
      final p0 = points[seg - 1];
      final p1 = points[seg];
      final lat = p0.latitude + (p1.latitude - p0.latitude) * localT;
      final lng = p0.longitude + (p1.longitude - p0.longitude) * localT;
      out.add(await elevationAt(lat, lng));
    }
    return out;
  }

  void close() => _http.close();
}

/// Derived stats from a list of along-route elevation samples.
class ElevationStats {
  const ElevationStats({
    required this.minM,
    required this.maxM,
    required this.ascentM,
    required this.descentM,
  });

  final double minM;
  final double maxM;
  final double ascentM;
  final double descentM;

  factory ElevationStats.from(List<double?> samples) {
    double min_ = double.infinity;
    double max_ = -double.infinity;
    double ascent = 0;
    double descent = 0;
    double? prev;
    for (final v in samples) {
      if (v == null) continue;
      if (v < min_) min_ = v;
      if (v > max_) max_ = v;
      if (prev != null) {
        final dz = v - prev;
        if (dz > 0) ascent += dz;
        if (dz < 0) descent += -dz;
      }
      prev = v;
    }
    if (min_ == double.infinity) min_ = 0;
    if (max_ == -double.infinity) max_ = 0;
    return ElevationStats(
        minM: min_, maxM: max_, ascentM: ascent, descentM: descent);
  }
}
