// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/models/track.dart';
import '../../../shared/services/track_recorder.dart';
import '../../party/providers/party_provider.dart';
import '../providers/tracks_provider.dart';
import '../../../core/errors/user_error.dart';

class TracksScreen extends ConsumerWidget {
  const TracksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(activeRecordingProvider).valueOrNull;
    final saved = ref.watch(savedTracksProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracks'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (live == null)
            _StartRecordingCard(
              onStart: () async {
                HapticFeedback.mediumImpact();
                try {
                  await ref.read(trackRecorderProvider).start();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(humanizeError(e))),
                    );
                  }
                }
              },
            )
          else
            _LiveRecordingCard(live: live),
          const SizedBox(height: 16),
          Text('Saved (${saved.length})',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          if (saved.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No saved tracks yet. Start a recording above.',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            ),
          for (final t in saved) _SavedTrackTile(track: t),
        ],
      ),
    );
  }
}

class _StartRecordingCard extends StatelessWidget {
  const _StartRecordingCard({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onStart,
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFD9A441),
                radius: 24,
                child: Icon(Icons.fiber_manual_record,
                    color: Colors.black, size: 22),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Start a track',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text(
                      'Record a breadcrumb of where you go. Saved on device, '
                      'export as GPX anytime.',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveRecordingCard extends ConsumerStatefulWidget {
  const _LiveRecordingCard({required this.live});
  final TrackInProgress live;

  @override
  ConsumerState<_LiveRecordingCard> createState() =>
      _LiveRecordingCardState();
}

class _LiveRecordingCardState extends ConsumerState<_LiveRecordingCard> {
  // 1-Hz tick so the duration label updates while recording.
  late final _ticker =
      Stream<DateTime>.periodic(const Duration(seconds: 1), (_) => DateTime.now());

  @override
  Widget build(BuildContext context) {
    final live = widget.live;
    return StreamBuilder<DateTime>(
      stream: _ticker,
      builder: (_, _) {
        return Material(
          color: Colors.redAccent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _PulseDot(active: !live.paused),
                    const SizedBox(width: 8),
                    Text(
                      live.paused ? 'Paused' : 'Recording',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                          label: 'Time',
                          value: _fmtDuration(live.duration)),
                    ),
                    Expanded(
                      child: _Stat(
                          label: 'Distance',
                          value: _fmtMiles(live.distanceMeters)),
                    ),
                    Expanded(
                      child: _Stat(
                          label: 'Points', value: '${live.points.length}'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          if (live.paused) {
                            ref.read(trackRecorderProvider).resume();
                          } else {
                            ref.read(trackRecorderProvider).pause();
                          }
                        },
                        icon: Icon(live.paused
                            ? Icons.play_arrow
                            : Icons.pause),
                        label: Text(live.paused ? 'Resume' : 'Pause'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.redAccent),
                        onPressed: () => _confirmStop(context),
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmStop(BuildContext context) async {
    final ctl = TextEditingController(text: _defaultName(widget.live.startedAt));
    final saved = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Save track'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Track name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(null),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(ctl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (saved == null) {
      await ref.read(trackRecorderProvider).discard();
    } else {
      await ref
          .read(trackRecorderProvider)
          .stop(name: saved.isEmpty ? null : saved);
      ref.invalidate(savedTracksProvider);
    }
  }

  String _defaultName(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Track ${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.active});
  final bool active;
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
            color: Colors.white54, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, _) {
        final a = 0.4 + 0.6 * _ctl.value;
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: a),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600)),
        ],
      );
}

class _SavedTrackTile extends ConsumerWidget {
  const _SavedTrackTile({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      child: ListTile(
        leading: const Icon(Icons.timeline, color: Colors.lightGreen),
        title: Text(track.name),
        subtitle: Text(
          '${_fmtMiles(track.distanceMeters)} · '
          '${_fmtDuration(track.duration)} · '
          '${_fmtElev(track.elevationGainM)} gain',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'gpx') {
              final gpx = ref
                  .read(gpxServiceProvider)
                  .routeToGpx(track.name, track.points.map((p) => p.latLng).toList());
              await Share.share(gpx, subject: '${track.name}.gpx');
            } else if (v == 'delete') {
              await ref.read(trackStoreProvider).delete(track.id);
              ref.invalidate(savedTracksProvider);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'gpx', child: Text('Export GPX')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

String _fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '${two(m)}:${two(s)}';
}

String _fmtMiles(double meters) {
  final mi = meters / 1609.344;
  final ft = meters * 3.28084;
  if (mi < 0.1) return '${ft.toStringAsFixed(0)} ft';
  return '${mi.toStringAsFixed(mi < 10 ? 2 : 1)} mi';
}

String _fmtElev(double meters) {
  if (meters < 1) return '0 ft';
  final ft = meters * 3.28084;
  return '${ft.toStringAsFixed(0)} ft';
}
