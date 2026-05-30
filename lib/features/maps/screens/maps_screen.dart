import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/map_region.dart';
import '../providers/maps_provider.dart';

/// Region download manager — pick what to download, see what's installed,
/// pick which one the map currently reads from.
class MapsScreen extends ConsumerWidget {
  const MapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(regionCatalogProvider);
    final downloaded =
        ref.watch(downloadedRegionsProvider).valueOrNull ?? const [];
    final active = ref.watch(activeRegionProvider).valueOrNull;
    final inFlight = ref.watch(regionDownloadControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maps'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.amber.withValues(alpha: 0.12),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: const Text(
              'Region URLs are placeholders — host your own .pmtiles (S3, R2, '
              'GitHub release) and edit lib/shared/services/region_catalog.dart '
              'to point at them. Your Washington download already on device '
              'works either way.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: catalog.all.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = catalog.all[i];
                return _RegionTile(
                  region: r,
                  isDownloaded: downloaded.contains(r.id),
                  isActive: active == r.id,
                  progress: inFlight[r.id],
                  error: ref
                      .read(regionDownloadControllerProvider.notifier)
                      .errorFor(r.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionTile extends ConsumerWidget {
  const _RegionTile({
    required this.region,
    required this.isDownloaded,
    required this.isActive,
    required this.progress,
    required this.error,
  });

  final MapRegion region;
  final bool isDownloaded;
  final bool isActive;
  final RegionDownloadProgress? progress;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(regionDownloadControllerProvider.notifier);
    final subtitle = progress != null
        ? _progressLabel(progress!)
        : (isDownloaded
            ? (isActive ? 'Active · ${region.sizeLabel}' : region.sizeLabel)
            : '${region.sizeLabel} · not downloaded');

    Widget? trailing;
    if (progress != null) {
      trailing = IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel',
        onPressed: () => ctrl.cancel(region.id),
      );
    } else if (isDownloaded) {
      trailing = PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'activate') {
            await ref
                .read(activeRegionProvider.notifier)
                .setActive(region.id);
          } else if (v == 'delete') {
            await ref.read(regionStoreProvider).delete(region.id);
            ref.invalidate(downloadedRegionsProvider);
            ref.invalidate(activeRegionProvider);
          }
        },
        itemBuilder: (_) => [
          if (!isActive)
            const PopupMenuItem(value: 'activate', child: Text('Set active')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );
    } else {
      trailing = IconButton(
        icon: const Icon(Icons.download),
        tooltip: 'Download',
        onPressed: () => ctrl.start(region),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      title: Text(region.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle),
          if (progress != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress!.fraction),
          ],
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(error!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
        ],
      ),
      leading: Icon(
        isActive
            ? Icons.public
            : (isDownloaded ? Icons.map_outlined : Icons.cloud_outlined),
        color: isActive ? Colors.lightGreen : null,
      ),
      trailing: trailing,
    );
  }

  String _progressLabel(RegionDownloadProgress p) {
    final mbDone = (p.downloaded / (1024 * 1024)).toStringAsFixed(0);
    if (p.total <= 0) return 'Downloading… ${mbDone}MB';
    final mbTot = (p.total / (1024 * 1024)).toStringAsFixed(0);
    final pct = (p.fraction * 100).toStringAsFixed(0);
    return 'Downloading $mbDone / $mbTot MB ($pct%)';
  }
}
