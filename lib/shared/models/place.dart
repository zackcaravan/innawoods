// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:latlong2/latlong.dart';

/// A geocoder search result.
class Place {
  const Place({required this.name, required this.subtitle, required this.location});

  final String name;
  final String subtitle;
  final LatLng location;
}
