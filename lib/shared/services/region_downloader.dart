import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Streamed PMTiles download with progress + atomic rename on success.
/// Writes to `<dest>.part` so a partial/aborted download is never mistaken for
/// a usable region.
class RegionDownloader {
  RegionDownloader();

  final http.Client _client = http.Client();

  /// Downloads [url] to [dest], emitting (downloaded, total) progress events.
  /// Throws if the response is non-200 or the connection drops.
  Stream<(int downloaded, int total)> download({
    required String url,
    required String dest,
  }) async* {
    final part = File('$dest.part');
    if (part.existsSync()) part.deleteSync();
    final sink = part.openWrite();
    final req = http.Request('GET', Uri.parse(url));
    final resp = await _client.send(req);
    if (resp.statusCode != 200) {
      await sink.close();
      part.deleteSync();
      throw HttpException('HTTP ${resp.statusCode} from $url');
    }
    final total = resp.contentLength ?? 0;
    int got = 0;
    try {
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        got += chunk.length;
        yield (got, total);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.close();
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }
    // Success — atomically rename into place.
    final final_ = File(dest);
    if (final_.existsSync()) final_.deleteSync();
    part.renameSync(dest);
  }

  void close() => _client.close();
}
