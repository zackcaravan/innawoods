// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/map_pin.dart';

/// Minimal GPX 1.1 read/write for pins (waypoints) and routes (tracks).
class GpxService {
  String pinsToGpx(List<MapPin> pins) {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="innawoods" '
          'xmlns="http://www.topografix.com/GPX/1/1">');
    for (final pin in pins) {
      b
        ..writeln('  <wpt lat="${pin.location.latitude}" '
            'lon="${pin.location.longitude}">')
        ..writeln('    <name>${_esc(pin.name)}</name>')
        ..writeln('    <type>${_esc(pin.type)}</type>');
      if (pin.note != null) b.writeln('    <desc>${_esc(pin.note!)}</desc>');
      b.writeln('  </wpt>');
    }
    b.writeln('</gpx>');
    return b.toString();
  }

  String routeToGpx(String name, List<LatLng> points) {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="innawoods" '
          'xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('  <trk>')
      ..writeln('    <name>${_esc(name)}</name>')
      ..writeln('    <trkseg>');
    for (final pt in points) {
      b.writeln('      <trkpt lat="${pt.latitude}" lon="${pt.longitude}"/>');
    }
    b
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return b.toString();
  }

  /// Pull every lat/lon pair from `trkpt`/`rtept`/`wpt` (order preserved).
  List<LatLng> parsePoints(String gpx) {
    final re = RegExp(
      r'<(?:trkpt|rtept|wpt)\b[^>]*?\blat="([-\d.]+)"[^>]*?\blon="([-\d.]+)"',
      caseSensitive: false,
    );
    return [
      for (final m in re.allMatches(gpx))
        LatLng(double.parse(m.group(1)!), double.parse(m.group(2)!)),
    ];
  }

  /// Write [content] to a temp `.gpx` file and open the OS share sheet.
  Future<void> shareGpx(String filename, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path)], subject: filename);
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
