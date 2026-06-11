// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Snaps a drawn leg to the trail/road network via BRouter (open-source,
/// trail-aware, no API key). Used by the "snap to trail" drawing mode.
class RoutingService {
  /// Geometry that follows the network from [from] to [to]. On any failure
  /// (off-network, offline, timeout) it falls back to a straight segment so
  /// drawing never breaks.
  Future<List<LatLng>> snap(
    LatLng from,
    LatLng to, {
    String profile = 'trekking',
  }) async {
    final uri = Uri.parse('https://brouter.de/brouter').replace(
      queryParameters: {
        'lonlats':
            '${from.longitude},${from.latitude}|${to.longitude},${to.latitude}',
        'profile': profile,
        'alternativeidx': '0',
        'format': 'geojson',
      },
    );
    try {
      final resp = await http.get(uri, headers: {'User-Agent': 'innawoods/0.1'});
      if (resp.statusCode != 200) return [from, to];
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final feats = json['features'] as List?;
      final coords =
          ((feats?.first as Map?)?['geometry'] as Map?)?['coordinates'] as List?;
      if (coords == null || coords.length < 2) return [from, to];
      return [
        for (final c in coords)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
    } catch (_) {
      return [from, to];
    }
  }
}
