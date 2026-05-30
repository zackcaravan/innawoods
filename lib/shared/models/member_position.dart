import 'package:latlong2/latlong.dart';

/// A party member's decrypted live position, ready to draw on the map.
class MemberPosition {
  const MemberPosition({
    required this.userId,
    required this.callsign,
    required this.color,
    required this.location,
    required this.updatedAt,
    required this.isSelf,
    this.speed,
    this.heading,
  });

  final String userId;
  final String callsign;
  final String color; // hex
  final LatLng location;
  final double? speed; // m/s
  final double? heading; // degrees
  final DateTime updatedAt; // UTC
  final bool isSelf;

  Duration get age => DateTime.now().toUtc().difference(updatedAt);

  /// No ping in a while → dot goes grey, "last seen X ago".
  bool get isStale => age > const Duration(minutes: 2);
}
