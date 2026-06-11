// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/models/map_region.dart';
import '../../../shared/services/map_tile_server.dart';
import '../../../shared/services/region_catalog.dart';
import '../../../shared/services/region_downloader.dart';
import '../../../shared/services/region_store.dart';

part 'maps_provider.g.dart';

@Riverpod(keepAlive: true)
RegionCatalog regionCatalog(Ref ref) => const RegionCatalog();

@Riverpod(keepAlive: true)
RegionStore regionStore(Ref ref) => RegionStore();

/// Which region the map currently reads from (null = none downloaded yet).
@riverpod
class ActiveRegion extends _$ActiveRegion {
  @override
  Future<String?> build() => ref.watch(regionStoreProvider).activeId();

  Future<void> setActive(String regionId) async {
    await ref.read(regionStoreProvider).setActive(regionId);
    state = AsyncData(regionId);
  }
}

/// Filesystem-truth list of downloaded region ids.
@riverpod
class DownloadedRegions extends _$DownloadedRegions {
  @override
  Future<List<String>> build() => ref.watch(regionStoreProvider).downloaded();
}

class RegionDownloadProgress {
  const RegionDownloadProgress({required this.downloaded, required this.total});
  final int downloaded;
  final int total;
  double get fraction =>
      total == 0 ? 0 : (downloaded / total).clamp(0, 1).toDouble();
}

/// In-flight downloads keyed by region id. Pauses/cancellation just drop the
/// stream; the downloader cleans up its `.part` file on error.
@Riverpod(keepAlive: true)
class RegionDownloadController extends _$RegionDownloadController {
  final _subs = <String, StreamSubscription>{};
  final _errors = <String, String>{};

  @override
  Map<String, RegionDownloadProgress> build() => const {};

  String? errorFor(String id) => _errors[id];

  Future<void> start(MapRegion region) async {
    if (_subs.containsKey(region.id)) return; // already running
    _errors.remove(region.id);
    final store = ref.read(regionStoreProvider);
    final dest = await store.pathFor(region.id);
    final dl = RegionDownloader();
    final next = Map.of(state);
    next[region.id] =
        const RegionDownloadProgress(downloaded: 0, total: 0);
    state = next;
    final sub = dl.download(url: region.pmtilesUrl, dest: dest).listen(
      (p) {
        final m = Map.of(state);
        m[region.id] =
            RegionDownloadProgress(downloaded: p.$1, total: p.$2);
        state = m;
      },
      onError: (e, _) {
        _errors[region.id] = e.toString();
        _subs.remove(region.id);
        dl.close();
        final m = Map.of(state)..remove(region.id);
        state = m;
      },
      onDone: () async {
        _subs.remove(region.id);
        dl.close();
        final m = Map.of(state)..remove(region.id);
        state = m;
        ref.invalidate(downloadedRegionsProvider);
        // Auto-activate the first-downloaded region for convenience.
        final active = await ref.read(activeRegionProvider.future);
        if (active == null) {
          await ref.read(activeRegionProvider.notifier).setActive(region.id);
        }
      },
      cancelOnError: true,
    );
    _subs[region.id] = sub;
  }

  Future<void> cancel(String regionId) async {
    await _subs[regionId]?.cancel();
    _subs.remove(regionId);
    final m = Map.of(state)..remove(regionId);
    state = m;
  }
}

/// Live progress of an in-flight terrain DEM prefetch, per region.
class DemPrefetchProgress {
  const DemPrefetchProgress({required this.done, required this.total});
  final int done;
  final int total;
  double get fraction =>
      total == 0 ? 0 : (done / total).clamp(0, 1).toDouble();
}

/// Walks the bbox of a region at zoom 6..10 and pulls every DEM tile through
/// [MapTileServer]'s normal proxy path — populating the on-disk cache so the
/// hillshade renders offline. Cancellable, idempotent (already-cached tiles
/// are skipped), survives back-grounding.
@Riverpod(keepAlive: true)
class DemPrefetchController extends _$DemPrefetchController {
  final _cancels = <String, bool>{};
  final _errors = <String, String>{};

  @override
  Map<String, DemPrefetchProgress> build() => const {};

  String? errorFor(String id) => _errors[id];

  Future<void> start(MapRegion region) async {
    if (state.containsKey(region.id)) return;
    _errors.remove(region.id);
    _cancels[region.id] = false;
    state = {...state, region.id: const DemPrefetchProgress(done: 0, total: 0)};
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(
        '${supportDir.path}${Platform.pathSeparator}dem_cache');
    // Reuse the server's prefetch logic so disk-cache layout matches what the
    // runtime tile server expects — single source of truth for cache paths.
    final server = MapTileServer('', demCacheDir: dir);
    final b = region.bbox;
    try {
      await server.prefetchDemForBbox(
        minLng: b[0],
        minLat: b[1],
        maxLng: b[2],
        maxLat: b[3],
        zMin: 6,
        zMax: 10,
        onProgress: (_, done, total) {
          state = {
            ...state,
            region.id: DemPrefetchProgress(done: done, total: total),
          };
        },
        cancel: () => _cancels[region.id] == true,
      );
    } catch (e) {
      _errors[region.id] = e.toString();
    } finally {
      _cancels.remove(region.id);
      final next = Map.of(state)..remove(region.id);
      state = next;
    }
  }

  void cancel(String regionId) {
    _cancels[regionId] = true;
  }
}
