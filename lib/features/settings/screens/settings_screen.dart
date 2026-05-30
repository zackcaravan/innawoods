import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/coord_format.dart';
import '../../../shared/services/settings_store.dart';
import '../providers/settings_provider.dart';
import '../../../core/errors/user_error.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(humanizeError(e))),
        data: (s) => _Body(settings: s),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Battery', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Location update interval: ${_label(settings.locationIntervalSeconds)}'),
        Slider(
          value: settings.locationIntervalSeconds.toDouble(),
          min: 30,
          max: 300,
          divisions: 9, // 30s steps
          label: _label(settings.locationIntervalSeconds),
          onChanged: (v) => controller
              .save(settings.copyWith(locationIntervalSeconds: v.round())),
        ),
        const Text(
          'Less frequent = longer battery life. Takes effect next time you open a party map.',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const Divider(height: 32),
        Text('Map', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.map_outlined),
          title: const Text('Downloaded regions'),
          subtitle: const Text('Add, switch, or remove offline map regions.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/maps'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.timeline_outlined),
          title: const Text('Tracks'),
          subtitle:
              const Text('Record + browse your private breadcrumb tracks.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/tracks'),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.explore_outlined),
          title: const Text('Coordinate format'),
          subtitle: Text(settings.coordFormat.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final picked = await showModalBottomSheet<CoordFormat>(
              context: context,
              builder: (_) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Coordinate format',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    for (final f in CoordFormat.values)
                      RadioListTile<CoordFormat>(
                        value: f,
                        groupValue: settings.coordFormat,
                        onChanged: (v) => Navigator.of(context).pop(v),
                        title: Text(f.label),
                        subtitle: Text(_sampleFor(f),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
            if (picked != null) {
              await controller.save(settings.copyWith(coordFormat: picked));
            }
          },
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.nightMode,
          onChanged: (v) =>
              controller.save(settings.copyWith(nightMode: v)),
          title: const Text('Night mode (red filter)'),
          subtitle: const Text(
              'Tints the whole app red so a quick glance doesn\'t blow your '
              'dark-adapted vision.'),
          secondary: const Icon(Icons.brightness_2_outlined),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.headingUp,
          onChanged: (v) =>
              controller.save(settings.copyWith(headingUp: v)),
          title: const Text('Heading-up map'),
          subtitle: const Text(
              'Rotate the map so your travel direction is always up. '
              'Compass single-tap still snaps back to north.'),
          secondary: const Icon(Icons.navigation_outlined),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.tripMode,
          onChanged: (v) =>
              controller.save(settings.copyWith(tripMode: v)),
          title: const Text('Trip mode (battery saver)'),
          subtitle: const Text(
              'Forces location updates to every 90 s, regardless of the '
              'battery slider. Shows a TRIP badge on the map while on.'),
          secondary: const Icon(Icons.eco_outlined),
        ),
        const SizedBox(height: 8),
        Text('3D terrain height: ${_exagLabel(settings.terrainExaggeration)}'),
        Slider(
          value: settings.terrainExaggeration,
          min: 0.5,
          max: 2.5,
          divisions: 20, // 0.1 steps
          label: _exagLabel(settings.terrainExaggeration),
          onChanged: (v) => controller.save(
              settings.copyWith(terrainExaggeration: double.parse(v.toStringAsFixed(1)))),
        ),
        const Text(
          'How dramatic mountains look in 3D mode. 1.0 is true-to-life; '
          'higher exaggerates relief. Takes effect next time you tilt into 3D.',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const Divider(height: 32),
        Text('Safety', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.deadManEnabled,
          onChanged: (v) =>
              controller.save(settings.copyWith(deadManEnabled: v)),
          title: const Text('Dead-man’s switch'),
          subtitle: const Text(
              'Alert me when a crew member hasn’t pinged in a while.'),
        ),
        if (settings.deadManEnabled) ...[
          Text('Alert after ${settings.deadManMinutes} min of silence'),
          Slider(
            value: settings.deadManMinutes.toDouble(),
            min: 5,
            max: 60,
            divisions: 11,
            label: '${settings.deadManMinutes} min',
            onChanged: (v) =>
                controller.save(settings.copyWith(deadManMinutes: v.round())),
          ),
        ],
      ],
    );
  }

  /// Sample readout (Mt Rainier coords) to give context to each format choice.
  String _sampleFor(CoordFormat f) => formatCoord(46.8523, -121.7603, f);

  String _exagLabel(double e) {
    if (e <= 0.75) return 'Subtle (${e.toStringAsFixed(1)}×)';
    if (e <= 1.25) return 'Realistic (${e.toStringAsFixed(1)}×)';
    if (e <= 1.75) return 'Bold (${e.toStringAsFixed(1)}×)';
    return 'Dramatic (${e.toStringAsFixed(1)}×)';
  }

  String _label(int seconds) =>
      seconds < 60 ? '${seconds}s' : '${(seconds / 60).toStringAsFixed(seconds % 60 == 0 ? 0 : 1)} min';
}
