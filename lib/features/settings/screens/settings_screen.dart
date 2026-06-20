// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../../shared/services/coord_format.dart';
import '../../../shared/services/location_publisher.dart';
import '../../../shared/services/settings_store.dart';
import '../providers/settings_provider.dart';
import '../../../core/errors/user_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/screens/background_disclosure_screen.dart';
import '../../party/providers/party_provider.dart';

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
        const Divider(height: 24),
        Text('Radio', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.radio_outlined),
          title: const Text('LoRa radio'),
          subtitle: const Text(
              'Pair a Meshtastic-firmware device for off-grid mesh chat '
              'and position sharing.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/lora'),
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
          value: settings.autoHeadingUp,
          onChanged: (v) =>
              controller.save(settings.copyWith(autoHeadingUp: v)),
          title: const Text('Auto heading-up over 4 mph'),
          subtitle: const Text(
              'Map flips to heading-up while you\'re moving briskly, then '
              'returns to north when you stop. Compass tap also resets to '
              'north anytime.'),
          secondary: const Icon(Icons.directions_walk),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.tripMode,
          onChanged: (v) =>
              controller.save(settings.copyWith(tripMode: v)),
          title: const Text('Trip mode (battery saver)'),
          subtitle: const Text(
              'Position updates every 90 s, lower-accuracy GPS, 3D tilt + '
              'relief shading off. Use for multi-hour trips where battery '
              'matters more than a smooth 5 m dot.'),
          secondary: const Icon(Icons.eco_outlined),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.searchLimitToRegion,
          onChanged: (v) =>
              controller.save(settings.copyWith(searchLimitToRegion: v)),
          title: const Text('Limit search to downloaded region'),
          subtitle: const Text(
              'Drop any place-search result outside your active region. '
              'Off → distant matches still rank in (camera-biased).'),
          secondary: const Icon(Icons.crop_free),
        ),
        // Off-road style lives in the map's Layers drawer instead of here —
        // it's a "moment's notice" visual toggle and Settings is for things
        // you set once and forget. See party_map3d_screen `_showLayersSheet`.
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
        const _BackgroundLocationTile(),
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

/// Tile that exposes the "Share with screen off" state and triggers the
/// disclosure → OS prompt flow when the user wants to enable it. Lives
/// here (Settings) rather than onboarding so we don't pile up permission
/// prompts on first install.
class _BackgroundLocationTile extends ConsumerStatefulWidget {
  const _BackgroundLocationTile();

  @override
  ConsumerState<_BackgroundLocationTile> createState() =>
      _BackgroundLocationTileState();
}

class _BackgroundLocationTileState
    extends ConsumerState<_BackgroundLocationTile>
    with WidgetsBindingObserver {
  bool? _hasAlways;
  bool _busy = false;

  /// True while we're waiting for the user to come back from the system
  /// settings page. Drives the "Waiting for you to grant…" banner and
  /// the lifecycle re-check on resume.
  bool _awaitingSettingsReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user comes back from system settings (or any other app),
    // re-check the permission state. If they granted Always in settings,
    // the tile flips to "ON" without them having to tap Enable again.
    if (state == AppLifecycleState.resumed && _awaitingSettingsReturn) {
      _awaitingSettingsReturn = false;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final has = await ref
        .read(locationSharingProvider.notifier)
        .hasBackgroundPermission();
    if (mounted) setState(() => _hasAlways = has);
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    // 1. Prominent disclosure first — Google's requirement before any OS
    //    prompt / settings deep-link. User can dismiss; we honour that
    //    without retrying.
    final accepted = await BackgroundDisclosureScreen.show(context);
    if (!mounted) return;
    if (!accepted) {
      setState(() => _busy = false);
      return;
    }
    // 2. POST_NOTIFICATIONS (Android 13+). Without this, the foreground
    //    service's persistent notification is silently dropped, leaving
    //    the user with no signal that we're actually sharing — defeating
    //    the disclosure promise. Ask before the location dance so the OS
    //    prompt doesn't sandwich them. No-op on iOS / Android < 13 where
    //    the package returns granted without showing anything.
    final notifStatus = await ph.Permission.notification.request();
    if (!mounted) return;
    if (!notifStatus.isGranted) {
      // Don't block on this — background sharing technically works
      // without notifications visible, it's just that the user won't
      // know it's running. Surface a snackbar and continue.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Notifications blocked. You won't see the persistent "
              'banner that tells you sharing is active.'),
        ),
      );
    }
    // 3. Attempt the upgrade. On Android 10 and earlier this can show a
    //    runtime dialog with "Allow all the time"; on Android 11+ Google
    //    removed that dialog and we need to deep-link to app settings.
    //    The publisher returns an enum that tells us which case we're in.
    final result = await ref
        .read(locationSharingProvider.notifier)
        .requestBackgroundUpgrade();
    if (!mounted) return;
    switch (result) {
      case BackgroundUpgradeResult.granted:
        setState(() {
          _busy = false;
          _hasAlways = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF2e7d32),
            content: Text('Background sharing is ON.'),
          ),
        );
        return;
      case BackgroundUpgradeResult.foregroundDenied:
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Location permission denied. Innawoods needs at least '
                "'While using app' to function — tap Enable again to retry."),
          ),
        );
        return;
      case BackgroundUpgradeResult.needsSettings:
        // Android 11+: open the app's system settings so the user can
        // pick "Allow all the time" themselves. Set _awaitingSettingsReturn
        // so the lifecycle observer above re-checks on resume.
        setState(() {
          _busy = false;
          _awaitingSettingsReturn = true;
        });
        await ref
            .read(locationSharingProvider.notifier)
            .openAppSettings();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 8),
            content: Text(
                "Opened system settings. Tap 'Permissions' → 'Location' "
                "→ 'Allow all the time', then come back."),
          ),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final has = _hasAlways;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Background sharing', style: t.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Whether your party can see you with the screen off. Without this, '
          'your dot freezes on their map the moment your phone sleeps.',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 12),
        if (has == null)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Checking permission…'),
          )
        else if (has)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: const Text('Background sharing is ON'),
            subtitle: const Text(
                'Your position keeps flowing to your party while the '
                'screen is off. Disable via OS settings if you change '
                'your mind.'),
          )
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_off_outlined,
                color: Colors.orange),
            title: const Text('Background sharing is OFF'),
            subtitle: const Text(
                'Your dot freezes for the rest of your party once your '
                'screen sleeps. Tap Enable to fix.'),
            trailing: FilledButton(
              onPressed: _busy ? null : _enable,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.amber,
                foregroundColor: Colors.black,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('Enable'),
            ),
          ),
      ],
    );
  }
}
