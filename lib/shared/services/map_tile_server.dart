import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// A tiny localhost HTTP server that makes the MapLibre map work fully offline:
///  - serves the bundled map assets (map.html, maplibre-gl.js, pmtiles.js, style)
///    straight from the Flutter asset bundle, and
///  - range-serves the downloaded region `.pmtiles` file from device storage
///    (pmtiles.js issues HTTP Range requests to read vector tiles).
///
/// The WebView loads `http://127.0.0.1:<port>/map.html`; everything it needs is
/// same-origin and local, so the map renders with no internet.
class MapTileServer {
  MapTileServer(this.pmtilesPath);

  /// On-disk path to the active region's `.pmtiles` (may not exist yet).
  final String pmtilesPath;

  HttpServer? _server;
  int get port => _server!.port;

  // Reused connection + small in-memory cache so terrain DEM tiles don't open a
  // fresh socket each time or refetch on every pan. Bounded LRU (~256 tiles).
  final http.Client _http = http.Client();
  final LinkedHashMap<String, List<int>> _demCache = LinkedHashMap();
  static const _demCacheMax = 256;

  Future<int> start() async {
    _server = await shelf_io.serve(
      _handler,
      InternetAddress.loopbackIPv4,
      0, // ephemeral port
    );
    return _server!.port;
  }

  Future<void> stop() async {
    _http.close();
    await _server?.close(force: true);
  }

  Future<Response> _handler(Request req) async {
    final path = req.url.path;
    if (path == 'wa.pmtiles' || path.endsWith('.pmtiles')) {
      return _servePmtiles(req);
    }
    if (path.startsWith('dem/')) {
      return _proxyDem(path);
    }
    // `rootBundle.load` keys against the decoded AssetManifest paths (literal
    // spaces, not `%20`). shelf already decodes `Request.url.path`, so pass it
    // straight through — re-encoding would miss assets bundled with spaces.
    final asset = path.isEmpty ? 'map.html' : path;
    try {
      final data = await rootBundle.load('assets/map/$asset');
      return Response.ok(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        headers: {
          'content-type': _contentType(asset),
          'access-control-allow-origin': '*',
        },
      );
    } catch (_) {
      return Response.notFound('not found: $asset');
    }
  }

  /// Serves the region pmtiles with HTTP Range support (required by pmtiles.js).
  Future<Response> _servePmtiles(Request req) async {
    final file = File(pmtilesPath);
    if (!file.existsSync()) {
      return Response.notFound('no map downloaded');
    }
    final length = await file.length();
    final range = req.headers['range'];
    if (range != null && range.startsWith('bytes=')) {
      final spec = range.substring(6).split('-');
      final start = int.parse(spec[0]);
      final end = (spec.length > 1 && spec[1].isNotEmpty)
          ? int.parse(spec[1])
          : length - 1;
      final raf = await file.open();
      await raf.setPosition(start);
      final bytes = await raf.read(end - start + 1);
      await raf.close();
      return Response(
        206,
        body: bytes,
        headers: {
          'content-type': 'application/octet-stream',
          'content-range': 'bytes $start-$end/$length',
          'content-length': '${bytes.length}',
          'accept-ranges': 'bytes',
          'access-control-allow-origin': '*',
        },
      );
    }
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': 'application/octet-stream',
        'accept-ranges': 'bytes',
        'content-length': '$length',
        'access-control-allow-origin': '*',
      },
    );
  }

  /// Proxy terrain DEM tiles (AWS Terrarium) so the WebView fetches them
  /// same-origin (no CORS). Phase D will swap this for a bundled offline DEM.
  Future<Response> _proxyDem(String path) async {
    // path = dem/{z}/{x}/{y}.png
    final coords = path.substring(4);
    const demHeaders = {
      'content-type': 'image/png',
      'access-control-allow-origin': '*',
      'cache-control': 'max-age=86400',
    };
    final cached = _demCache.remove(coords);
    if (cached != null) {
      _demCache[coords] = cached; // touch (move to MRU)
      return Response.ok(cached, headers: demHeaders);
    }
    final url =
        'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/$coords';
    try {
      // Timeout so a slow/unreachable AWS can't hang a request forever and back
      // up the basemap requests behind it.
      final resp =
          await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        _demCache[coords] = bytes;
        if (_demCache.length > _demCacheMax) {
          _demCache.remove(_demCache.keys.first); // evict LRU
        }
        return Response.ok(bytes, headers: demHeaders);
      }
      return Response.notFound('dem $coords');
    } catch (_) {
      return Response.notFound('dem fetch failed');
    }
  }

  String _contentType(String p) {
    if (p.endsWith('.html')) return 'text/html; charset=utf-8';
    if (p.endsWith('.js')) return 'application/javascript';
    if (p.endsWith('.css')) return 'text/css';
    if (p.endsWith('.json')) return 'application/json';
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.pbf')) return 'application/x-protobuf';
    return 'application/octet-stream';
  }
}
