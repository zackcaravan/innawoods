// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/place.dart';

/// Forward geocoding via Photon (open-source, OSM-based, no API key).
///
/// Privacy note: the query text goes to the Photon server, like tile requests.
/// Self-hostable later for a fully private search.
class GeocoderService {
  Future<List<Place>> search(String query, {LatLng? near}) async {
    if (query.trim().length < 2) return [];
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': query,
      'limit': '8',
      if (near != null) 'lat': '${near.latitude}',
      if (near != null) 'lon': '${near.longitude}',
    });
    final resp = await http.get(uri, headers: {'User-Agent': 'innawoods/0.1'});
    if (resp.statusCode != 200) return [];
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final feats = (json['features'] as List?) ?? const [];
    return feats
        .map((f) => _toPlace(f as Map<String, dynamic>))
        .whereType<Place>()
        .toList();
  }

  Place? _toPlace(Map<String, dynamic> f) {
    final coords = (f['geometry'] as Map<String, dynamic>?)?['coordinates'];
    if (coords is! List || coords.length < 2) return null;
    final p = (f['properties'] as Map<String, dynamic>?) ?? const {};
    final name = (p['name'] ?? p['street'] ?? 'Unnamed').toString();
    final subtitle = [p['city'], p['county'], p['state'], p['country']]
        .where((e) => e != null && e.toString().isNotEmpty)
        .map((e) => e.toString())
        .toSet()
        .join(', ');
    return Place(
      name: name,
      subtitle: subtitle,
      location: LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
    );
  }
}
