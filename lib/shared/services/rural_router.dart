// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// Result of a rural routing query.
class RuralRoute {
  const RuralRoute({
    required this.found,
    required this.coords,
    required this.distanceMeters,
    this.reason,
  });

  /// True when a path through the loaded road graph was discovered. False
  /// for the honest "we don't have tiles for that" cases; callers should
  /// surface [reason] instead of rendering a misleading straight line.
  final bool found;

  /// Polyline from the start projection to the end projection. Empty when
  /// [found] is false.
  final List<LatLng> coords;

  /// Sum of great-circle lengths along the polyline. 0 when [found] is false.
  final double distanceMeters;

  /// Human-readable reason when [found] is false ("No road data loaded",
  /// "Endpoint too far from any loaded road", etc.).
  final String? reason;

  factory RuralRoute.notFound(String reason) =>
      RuralRoute(found: false, coords: const [], distanceMeters: 0,
          reason: reason);

  factory RuralRoute.fromJson(Map<String, dynamic> j) {
    final found = j['found'] == true;
    if (!found) {
      return RuralRoute.notFound((j['reason'] as String?) ?? 'No path.');
    }
    final raw = (j['coords'] as List?) ?? const [];
    return RuralRoute(
      found: true,
      coords: [
        for (final c in raw)
          if (c is List && c.length >= 2)
            LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ],
      distanceMeters: ((j['distM'] as num?) ?? 0).toDouble(),
    );
  }
}

/// Classification of a single turn extracted from a routed polyline.
enum ManeuverType {
  depart,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uturn,
  arrive;

  /// What the banner should read aloud (or display).
  String get instruction {
    switch (this) {
      case ManeuverType.depart:      return 'Head out';
      case ManeuverType.slightLeft:  return 'Bear left';
      case ManeuverType.left:        return 'Turn left';
      case ManeuverType.sharpLeft:   return 'Sharp left';
      case ManeuverType.slightRight: return 'Bear right';
      case ManeuverType.right:       return 'Turn right';
      case ManeuverType.sharpRight:  return 'Sharp right';
      case ManeuverType.uturn:       return 'Make a U-turn';
      case ManeuverType.arrive:      return 'Arrive';
    }
  }

  static ManeuverType fromId(String id) {
    switch (id) {
      case 'depart':       return ManeuverType.depart;
      case 'slight_left':  return ManeuverType.slightLeft;
      case 'left':         return ManeuverType.left;
      case 'sharp_left':   return ManeuverType.sharpLeft;
      case 'slight_right': return ManeuverType.slightRight;
      case 'right':        return ManeuverType.right;
      case 'sharp_right':  return ManeuverType.sharpRight;
      case 'uturn':        return ManeuverType.uturn;
      case 'arrive':       return ManeuverType.arrive;
      default:             return ManeuverType.depart;
    }
  }
}

/// One turn point along the route.
class Maneuver {
  const Maneuver({
    required this.type,
    required this.location,
    required this.distFromStartM,
    required this.distFromPrevM,
  });

  final ManeuverType type;
  final LatLng location;
  final double distFromStartM;
  final double distFromPrevM;

  static List<Maneuver> listFromJsonString(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final list = jsonDecode(json) as List;
      return [
        for (final e in list)
          if (e is Map<String, dynamic>)
            Maneuver(
              type: ManeuverType.fromId(e['type'] as String? ?? 'depart'),
              location: LatLng(
                (e['lat'] as num).toDouble(),
                (e['lng'] as num).toDouble(),
              ),
              distFromStartM: ((e['distFromStartM'] as num?) ?? 0).toDouble(),
              distFromPrevM: ((e['distFromPrevM'] as num?) ?? 0).toDouble(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// Dart-side wrapper for the JS routing primitives in map.html.
///
/// All real work happens in the WebView (we already have the road graph +
/// Dijkstra there); this class is just the type-safe bridge that callers
/// use without thinking about JSON shapes.
class RuralRouter {
  RuralRouter({required this.evalJs});

  /// Pluggable JS-eval, supplied by the map screen since the controller
  /// belongs to it. Returns the JSON result string, or null when the
  /// WebView is unavailable.
  final Future<String?> Function(String source) evalJs;

  /// Compute a rural-preferring route from [from] to [to]. Returns
  /// `RuralRoute.notFound(...)` when the graph is empty / endpoints are
  /// too far / no path exists — don't synthesise a route on top of that.
  Future<RuralRoute> route({
    required LatLng from,
    required LatLng to,
  }) async {
    final raw = await evalJs(
      'routeBetween(${from.longitude},${from.latitude},'
      '${to.longitude},${to.latitude})',
    );
    if (raw == null) return RuralRoute.notFound('No map available.');
    try {
      return RuralRoute.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return RuralRoute.notFound('Invalid route data.');
    }
  }

  /// Classify a routed polyline into a list of [Maneuver]s suitable for
  /// turn-by-turn display.
  Future<List<Maneuver>> maneuversFor(List<LatLng> coords) async {
    if (coords.length < 2) return const [];
    final js = jsonEncode([
      for (final c in coords) [c.longitude, c.latitude]
    ]);
    final raw = await evalJs('maneuversFor(${jsonEncode(js)})');
    return Maneuver.listFromJsonString(raw);
  }
}
