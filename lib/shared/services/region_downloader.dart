// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Resumable streamed PMTiles download with progress + atomic rename.
///
/// Writes to `<dest>.part` so a partial/aborted download is preserved across
/// retries — GitHub's release-asset CDN routinely drops connections part-way
/// through a 500MB+ asset over mobile (5G handoff, NAT churn, idle timeouts).
/// Each retry issues a `Range: bytes=<got>-` request to pick up from where the
/// previous attempt died. On a clean `200` from the server we restart from
/// zero; on `416` we treat the existing `.part` as complete.
class RegionDownloader {
  RegionDownloader({
    int maxRetries = 5,
    Duration initialBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(seconds: 30),
  })  : _maxRetries = maxRetries,
        _initialBackoff = initialBackoff,
        _maxBackoff = maxBackoff;

  final http.Client _client = http.Client();
  final int _maxRetries;
  final Duration _initialBackoff;
  final Duration _maxBackoff;

  /// Downloads [url] to [dest], emitting (downloaded, total) progress events.
  /// Retries on dropped connections with HTTP Range resumption. Throws only
  /// after [maxRetries] consecutive failures or on a non-recoverable HTTP
  /// status (anything other than 200/206/416).
  Stream<(int downloaded, int total)> download({
    required String url,
    required String dest,
  }) async* {
    final part = File('$dest.part');
    int attempt = 0;
    Duration backoff = _initialBackoff;
    int totalSize = 0;

    while (true) {
      attempt += 1;
      final int got = part.existsSync() ? part.lengthSync() : 0;

      final req = http.Request('GET', Uri.parse(url));
      if (got > 0) {
        req.headers['Range'] = 'bytes=$got-';
      }

      final http.StreamedResponse resp;
      try {
        resp = await _client.send(req);
      } catch (e) {
        if (attempt > _maxRetries) rethrow;
        await Future.delayed(backoff);
        backoff = _bump(backoff);
        continue;
      }

      // 416 Range Not Satisfiable: existing .part is already past the end of
      // the remote file — treat it as complete and finalise.
      if (resp.statusCode == 416 && got > 0) {
        await resp.stream.drain<void>();
        _finalize(part, dest);
        if (totalSize > 0) yield (got, totalSize);
        return;
      }

      if (resp.statusCode != 200 && resp.statusCode != 206) {
        await resp.stream.drain<void>();
        throw HttpException('HTTP ${resp.statusCode} from $url');
      }

      // 200 means the server ignored our Range header (or this was a fresh
      // first attempt). Start over from byte zero.
      final IOSink sink;
      int written;
      if (resp.statusCode == 200) {
        if (part.existsSync()) part.deleteSync();
        sink = part.openWrite();
        written = 0;
        totalSize = resp.contentLength ?? 0;
      } else {
        // 206 Partial Content — append to the existing .part. Prefer the
        // Content-Range total over Content-Length (Content-Length is the
        // *remainder*, not the whole file).
        sink = part.openWrite(mode: FileMode.append);
        written = got;
        final cr = resp.headers['content-range'];
        if (cr != null) {
          final slash = cr.lastIndexOf('/');
          if (slash >= 0) {
            final tot = int.tryParse(cr.substring(slash + 1).trim());
            if (tot != null) totalSize = tot;
          }
        }
        if (totalSize == 0) {
          totalSize = written + (resp.contentLength ?? 0);
        }
      }

      try {
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          written += chunk.length;
          yield (written, totalSize);
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        await sink.close();
        // Connection drop mid-body. KEEP .part for the next attempt's Range
        // request to resume from.
        if (attempt > _maxRetries) rethrow;
        await Future.delayed(backoff);
        backoff = _bump(backoff);
        continue;
      }

      // Sanity-check the byte count before declaring victory. A clean stream
      // close without hitting Content-Length means the CDN hung up silently;
      // treat it as a partial and retry.
      if (totalSize > 0 && written < totalSize) {
        if (attempt > _maxRetries) {
          throw HttpException(
            'Short download from $url: $written of $totalSize bytes',
          );
        }
        await Future.delayed(backoff);
        backoff = _bump(backoff);
        continue;
      }

      _finalize(part, dest);
      return;
    }
  }

  Duration _bump(Duration current) {
    final next = current * 2;
    return next > _maxBackoff ? _maxBackoff : next;
  }

  void _finalize(File part, String dest) {
    final out = File(dest);
    if (out.existsSync()) out.deleteSync();
    part.renameSync(dest);
  }

  void close() => _client.close();
}
