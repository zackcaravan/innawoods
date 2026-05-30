import 'package:mgrs_dart/mgrs_dart.dart';

/// User-selectable coordinate display formats.
enum CoordFormat {
  latLonDecimal, // 47.65432, -122.30215
  latLonDms,     // N 47°39'15.6", W 122°18'07.7"
  mgrs,          // 10TER0123456789
  utm,           // 10T 550000mE 5275000mN
}

extension CoordFormatLabel on CoordFormat {
  String get label => switch (this) {
        CoordFormat.latLonDecimal => 'Lat/Lon (decimal)',
        CoordFormat.latLonDms => 'Lat/Lon (D°M\'S")',
        CoordFormat.mgrs => 'MGRS',
        CoordFormat.utm => 'UTM',
      };

  /// SharedPreferences-friendly stable id (don't change once shipped).
  String get id => switch (this) {
        CoordFormat.latLonDecimal => 'latlon_dec',
        CoordFormat.latLonDms => 'latlon_dms',
        CoordFormat.mgrs => 'mgrs',
        CoordFormat.utm => 'utm',
      };

  static CoordFormat fromId(String id) {
    for (final f in CoordFormat.values) {
      if (f.id == id) return f;
    }
    return CoordFormat.latLonDecimal;
  }
}

/// Format a (lat, lng) pair into the chosen display string. All operations
/// are pure + cheap — safe to call inside `build()`.
String formatCoord(double lat, double lng, CoordFormat fmt) {
  switch (fmt) {
    case CoordFormat.latLonDecimal:
      return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    case CoordFormat.latLonDms:
      return '${_dms(lat, true)}  ${_dms(lng, false)}';
    case CoordFormat.mgrs:
      try {
        return Mgrs.forward([lng, lat], 5);
      } catch (_) {
        return '(MGRS undefined at this lat)';
      }
    case CoordFormat.utm:
      try {
        final u = Mgrs.LLtoUTM(lat, lng);
        final letter = _utmLatBand(lat);
        final e = u.easting.toStringAsFixed(0);
        final n = u.northing.toStringAsFixed(0);
        return '${u.zoneNumber}$letter ${e}mE ${n}mN';
      } catch (_) {
        return '(UTM undefined at this lat)';
      }
  }
}

String _dms(double v, bool isLat) {
  final hemi = isLat ? (v >= 0 ? 'N' : 'S') : (v >= 0 ? 'E' : 'W');
  final a = v.abs();
  final deg = a.floor();
  final minF = (a - deg) * 60;
  final min = minF.floor();
  final sec = (minF - min) * 60;
  return "$hemi $deg°${min.toString().padLeft(2, '0')}'"
      "${sec.toStringAsFixed(1).padLeft(4, '0')}\"";
}

// Standard UTM latitude band letter (C..X excluding I, O). Used for display
// alongside the zone number.
String _utmLatBand(double lat) {
  if (lat < -80 || lat >= 84) return '?';
  const bands = 'CDEFGHJKLMNPQRSTUVWX';
  final i = ((lat + 80) ~/ 8).clamp(0, bands.length - 1);
  return bands[i];
}
