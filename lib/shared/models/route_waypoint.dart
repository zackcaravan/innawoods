import 'package:latlong2/latlong.dart';

/// A waypoint placed along an existing shared route. Encrypted client-side
/// just like the parent route — the server only stores ciphertext.
///
/// Visual: a small marker drawn at `location` along its parent route line.
/// Use cases: "rest stop", "water source", "tricky bit", "viewpoint".
class RouteWaypoint {
  const RouteWaypoint({
    required this.id,
    required this.routeId,
    required this.userId,
    required this.name,
    required this.icon,
    required this.location,
    required this.createdAt,
    required this.mine,
    this.note,
  });

  final String id;
  final String routeId;
  final String userId;
  final String name;

  /// One of [RouteWaypointIcon.values] — the marker emoji shown on the map.
  final RouteWaypointIcon icon;

  final LatLng location;
  final String? note;
  final DateTime createdAt;
  final bool mine;
}

/// The fixed icon set offered when placing a waypoint. Stable string ids so
/// later renames don't break the encrypted payloads.
enum RouteWaypointIcon {
  flag('flag', '🚩'),
  water('water', '💧'),
  camp('camp', '🏕'),
  hazard('hazard', '⚠️'),
  view('view', '👁'),
  food('food', '🍴'),
  fuel('fuel', '⛽'),
  rest('rest', '🪑');

  const RouteWaypointIcon(this.id, this.emoji);
  final String id;
  final String emoji;

  static RouteWaypointIcon fromId(String id) {
    for (final v in RouteWaypointIcon.values) {
      if (v.id == id) return v;
    }
    return RouteWaypointIcon.flag;
  }
}
