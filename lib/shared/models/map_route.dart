// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:latlong2/latlong.dart';

/// A decrypted shared route. name + points + color come from the encrypted
/// payload — the server only ever sees ciphertext.
class MapRoute {
  const MapRoute({
    required this.id,
    required this.userId,
    required this.name,
    required this.points,
    required this.createdAt,
    required this.mine,
    this.color,
  });

  final String id;
  final String userId;
  final String name;
  final List<LatLng> points;
  final DateTime createdAt;
  final bool mine;

  /// User-picked line color, hex like `#ff5722`. Null = use the app default.
  /// Stored in the encrypted payload, so the server can't see who used which.
  final String? color;

  MapRoute copyWith({String? name, String? color}) => MapRoute(
        id: id,
        userId: userId,
        name: name ?? this.name,
        points: points,
        createdAt: createdAt,
        mine: mine,
        color: color ?? this.color,
      );
}

/// Suggested route colors. First entry is the app's default amber.
const kRouteColors = <String>[
  '#D9A441', // amber (default)
  '#ff5722', // deep orange
  '#ffeb3b', // yellow
  '#8bc34a', // lime
  '#26c6da', // cyan
  '#4fc3f7', // sky
  '#7e57c2', // violet
  '#ec407a', // pink
  '#ef5350', // red
  '#ffffff', // white (high contrast)
];
