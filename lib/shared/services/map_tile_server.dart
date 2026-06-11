// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// A tiny localhost HTTP server that makes the MapLibre map work fully offline:
///  - serves the bundled map assets (map.html, maplibre-gl.js, pmtiles.js, style)
///    straight from the Flutter asset bundle,
///  - range-serves the downloaded region `.pmtiles` file from device storage
///    (pmtiles.js issues HTTP Range requests to read vector tiles), and
///  - serves terrain DEM tiles with a two-tier (memory + disk) cache, so the
///    hillshade keeps working when you go offline after warming the cache.
///
/// The WebView loads `http://127.0.0.1:<port>/map.html`; everything it needs is
/// same-origin and local, so the map renders with no internet.
class MapTileServer {
  MapTileServer(this.pmtilesPath, {this.demCacheDir});

  /// On-disk path to the active region's `.pmtiles` (may not exist yet).
  final String pmtilesPath;

  /// Directory where DEM tiles are persisted across launches. When null, only
  /// the in-memory LRU is consulted (useful in tests).
  final Directory? demCacheDir;

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

  /// Serve a terrain DEM tile. Checks the memory LRU, then the on-disk cache,
  /// then falls back to the AWS Terrarium dataset. Successful network fetches
  /// are written through to disk so subsequent offline sessions still render
  /// shaded relief. The WebView fetches via this localhost endpoint regardless
  /// (it can't talk to AWS directly with CORS).
  Future<Response> _proxyDem(String path) async {
    // path = dem/{z}/{x}/{y}.png
    final coords = path.substring(4);
    const demHeaders = {
      'content-type': 'image/png',
      'access-control-allow-origin': '*',
      'cache-control': 'max-age=86400',
    };
    // Tier 1: in-memory LRU.
    final cached = _demCache.remove(coords);
    if (cached != null) {
      _demCache[coords] = cached;
      return Response.ok(cached, headers: demHeaders);
    }
    // Tier 2: on-disk cache. Path components are flattened to one filename
    // (`z_x_y.png`) so we don't have to mkdir every parent for every tile.
    final diskFile = _demCacheFile(coords);
    if (diskFile != null && diskFile.existsSync()) {
      try {
        final bytes = await diskFile.readAsBytes();
        _admitToMemory(coords, bytes);
        return Response.ok(bytes, headers: demHeaders);
      } catch (_) {
        // Corrupt cache entry — fall through to network.
      }
    }
    // Tier 3: AWS Terrarium S3.
    final url =
        'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/$coords';
    try {
      final resp =
          await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        _admitToMemory(coords, bytes);
        if (diskFile != null) {
          // Fire-and-forget — never block the request on disk.
          unawaited(_writeDemTile(diskFile, bytes));
        }
        return Response.ok(bytes, headers: demHeaders);
      }
      return Response.notFound('dem $coords');
    } catch (_) {
      return Response.notFound('dem fetch failed');
    }
  }

  /// Returns the on-disk file for a DEM tile, or null if caching is disabled.
  /// Flattens `{z}/{x}/{y}.png` → `{z}_{x}_{y}.png` to avoid per-tile mkdirs.
  File? _demCacheFile(String coords) {
    final dir = demCacheDir;
    if (dir == null) return null;
    // coords e.g. "9/82/183.png"
    final flat = coords.replaceAll('/', '_');
    return File('${dir.path}${Platform.pathSeparator}$flat');
  }

  Future<void> _writeDemTile(File f, List<int> bytes) async {
    try {
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes, flush: false);
    } catch (_) {
      // Best-effort — disk full / permission issues are non-fatal.
    }
  }

  void _admitToMemory(String coords, List<int> bytes) {
    _demCache[coords] = bytes;
    if (_demCache.length > _demCacheMax) {
      _demCache.remove(_demCache.keys.first);
    }
  }

  /// Walk every DEM tile inside `bounds` at zoom levels [`zMin`..`zMax`] and
  /// pull each one through the server's normal proxy path — populating both
  /// caches. Used by the "Download terrain for offline" action on the Maps
  /// screen. Reports progress via [onProgress] (0..1) so the UI can render a
  /// bar; respects [cancel] so the user can abort. Skips tiles already on
  /// disk so re-running is cheap.
  Future<int> prefetchDemForBbox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int zMin = 6,
    int zMax = 10,
    void Function(double progress, int done, int total)? onProgress,
    bool Function()? cancel,
  }) async {
    // Web-Mercator tile range per zoom.
    final tiles = <List<int>>[]; // [z, x, y]
    for (int z = zMin; z <= zMax; z++) {
      final n = 1 << z; // 2^z
      int x0 = ((minLng + 180) / 360 * n).floor();
      int x1 = ((maxLng + 180) / 360 * n).floor();
      // Latitude → tile-y uses the Mercator projection.
      int y0 = _lat2tileY(maxLat, z);
      int y1 = _lat2tileY(minLat, z);
      x0 = x0.clamp(0, n - 1);
      x1 = x1.clamp(0, n - 1);
      y0 = y0.clamp(0, n - 1);
      y1 = y1.clamp(0, n - 1);
      for (int x = x0; x <= x1; x++) {
        for (int y = y0; y <= y1; y++) {
          tiles.add([z, x, y]);
        }
      }
    }
    int done = 0;
    int fetched = 0;
    for (final t in tiles) {
      if (cancel != null && cancel()) break;
      final coords = '${t[0]}/${t[1]}/${t[2]}.png';
      // Skip if already on disk (cheap stat).
      final f = _demCacheFile(coords);
      if (f != null && f.existsSync()) {
        done++;
        onProgress?.call(done / tiles.length, done, tiles.length);
        continue;
      }
      try {
        final url =
            'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/$coords';
        final resp = await _http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200 && f != null) {
          await _writeDemTile(f, resp.bodyBytes);
          fetched++;
        }
      } catch (_) {
        // Skip — one failed tile shouldn't abort the whole region.
      }
      done++;
      onProgress?.call(done / tiles.length, done, tiles.length);
    }
    return fetched;
  }

  static int _lat2tileY(double lat, int z) {
    final n = 1 << z;
    final latRad = lat * math.pi / 180;
    return ((1 -
                math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
            2 *
            n)
        .floor();
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
