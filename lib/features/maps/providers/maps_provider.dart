import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/models/map_region.dart';
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
