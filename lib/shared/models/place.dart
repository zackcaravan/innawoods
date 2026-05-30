import 'package:latlong2/latlong.dart';

/// A geocoder search result.
class Place {
  const Place({required this.name, required this.subtitle, required this.location});

  final String name;
  final String subtitle;
  final LatLng location;
}
