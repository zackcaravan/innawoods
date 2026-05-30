import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// A decrypted pin ready to draw. `type` is the only plaintext field on the
/// server; name/coords/note all come from the encrypted payload.
class MapPin {
  const MapPin({
    required this.id,
    required this.userId,
    required this.type,
    required this.name,
    required this.location,
    required this.createdAt,
    required this.mine,
    this.note,
  });

  final String id;
  final String userId;
  final String type;
  final String name;
  final LatLng location;
  final String? note;
  final DateTime createdAt;
  final bool mine;
}

/// The fixed pin types (kept in the clear server-side for icon rendering).
enum PinType {
  waypoint('waypoint', Icons.place, 'Waypoint'),
  meet('meet', Icons.handshake, 'Meet here'),
  hazard('hazard', Icons.warning, 'Hazard'),
  camp('camp', Icons.cabin, 'Camp'),
  poi('poi', Icons.star, 'POI'),
  custom('custom', Icons.push_pin, 'Custom');

  const PinType(this.id, this.icon, this.label);
  final String id;
  final IconData icon;
  final String label;

  static PinType fromId(String id) =>
      PinType.values.firstWhere((t) => t.id == id, orElse: () => PinType.custom);
}
