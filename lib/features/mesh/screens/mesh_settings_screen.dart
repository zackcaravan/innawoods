import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/services/mesh/mesh_radio.dart';
import '../providers/mesh_provider.dart';

/// LoRa radio section — paired-device card if we have one, otherwise a
/// "scan for radios" picker. Phase 8a foundation; the proper "step you
/// through pairing" wizard lands in Phase 8b.
class MeshSettingsScreen extends ConsumerStatefulWidget {
  const MeshSettingsScreen({super.key});

  @override
  ConsumerState<MeshSettingsScreen> createState() => _MeshSettingsScreenState();
}

class _MeshSettingsScreenState extends ConsumerState<MeshSettingsScreen> {
  StreamSubscription<List<DiscoveredRadio>>? _scanSub;
  List<DiscoveredRadio> _found = [];
  bool _scanning = false;
  String? _scanError;

  @override
  void dispose() {
    _scanSub?.cancel();
    ref.read(meshRadioServiceProvider).stopScan();
    super.dispose();
  }

  /// Walk the BLE permission gauntlet — on Android 12+ this asks for
  /// BLUETOOTH_SCAN + BLUETOOTH_CONNECT separately from location. Falls
  /// back gracefully on iOS where the OS handles consent inline.
  Future<bool> _ensurePermissions() async {
    final perms = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    final ok = perms.values.every((s) =>
        s == PermissionStatus.granted || s == PermissionStatus.limited);
    if (!ok) {
      setState(() => _scanError =
          'Bluetooth + location permission are required to find nearby radios.');
    }
    return ok;
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _scanError = null;
      _found = const [];
    });
    if (!await _ensurePermissions()) {
      setState(() => _scanning = false);
      return;
    }
    final svc = ref.read(meshRadioServiceProvider);
    await _scanSub?.cancel();
    _scanSub = svc.scan().listen(
      (devices) {
        if (!mounted) return;
        setState(() => _found = devices);
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _scanning = false);
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _scanError = '$e';
          _scanning = false;
        });
      },
    );
  }

  Future<void> _connectTo(DiscoveredRadio d) async {
    await _scanSub?.cancel();
    setState(() => _scanning = false);
    await ref.read(meshRadioServiceProvider).connect(d.id);
  }

  Future<void> _forgetRadio() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget this radio?'),
        content: const Text(
            'Disconnects and clears the paired radio. You can re-pair by '
            'scanning again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Forget')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(meshRadioServiceProvider).forget();
  }

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(meshConnectionStateProvider).valueOrNull ??
        MeshConnectionState.disconnected;
    final radio = ref.watch(connectedRadioProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('LoRa radio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(
            connState: connState,
            radio: radio,
          ),
          const SizedBox(height: 8),
          if (radio == null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'innawoods works with any device flashed with the Meshtastic '
                'firmware — LilyGO T-Beam / T-Echo, Heltec, RAK, and so on. '
                'Power on your radio (it should already be running '
                'Meshtastic), then scan to pair.',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => context.push('/settings/lora/setup'),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Set up step-by-step'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _scanning ? null : _startScan,
              icon: _scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.bluetooth_searching),
              label: Text(_scanning
                  ? 'Scanning…'
                  : (_found.isEmpty ? 'Or scan now' : 'Scan again')),
            ),
            if (_scanError != null) ...[
              const SizedBox(height: 8),
              Text(_scanError!,
                  style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 16),
            if (_found.isEmpty && !_scanning)
              const Text(
                'No radios found yet. Make sure the device is powered on, '
                'in range, and broadcasting via Bluetooth.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              )
            else
              for (final d in _found) _DiscoveredTile(d: d, onTap: _connectTo),
          ] else ...[
            _RadioCard(radio: radio),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _forgetRadio,
              icon: const Icon(Icons.link_off),
              label: const Text('Forget radio'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.connState, required this.radio});
  final MeshConnectionState connState;
  final ConnectedRadio? radio;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (connState) {
      MeshConnectionState.ready => (
          Icons.signal_cellular_alt,
          Colors.lightGreenAccent,
          'Mesh ready'
        ),
      MeshConnectionState.syncing => (
          Icons.sync,
          Colors.amberAccent,
          'Syncing config from radio…'
        ),
      MeshConnectionState.connecting => (
          Icons.bluetooth_connected,
          Colors.amberAccent,
          'Connecting…'
        ),
      MeshConnectionState.scanning => (
          Icons.bluetooth_searching,
          Colors.lightBlueAccent,
          'Scanning…'
        ),
      MeshConnectionState.disconnected => (
          Icons.bluetooth_disabled,
          Colors.white54,
          'No radio paired'
        ),
    };
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            radio != null && connState == MeshConnectionState.ready
                ? 'Connected to ${radio!.name}'
                : label,
            style: TextStyle(color: color, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _DiscoveredTile extends StatelessWidget {
  const _DiscoveredTile({required this.d, required this.onTap});
  final DiscoveredRadio d;
  final void Function(DiscoveredRadio) onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: const Icon(Icons.radio),
          title: Text(d.name),
          subtitle: Text('${d.id} · ${d.rssi} dBm'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onTap(d),
        ),
      );
}

class _RadioCard extends StatelessWidget {
  const _RadioCard({required this.radio});
  final ConnectedRadio radio;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String? value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13)),
              ),
              Expanded(
                child: Text(value ?? '—',
                    style: const TextStyle(fontSize: 14)),
              ),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.radio, color: Colors.lightGreenAccent),
                const SizedBox(width: 8),
                Text(radio.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const Divider(height: 24),
            row('Hardware', radio.hwModel),
            row('Firmware', radio.firmwareVersion),
            row('Region', radio.region),
            row(
                'Battery',
                radio.batteryLevel == null
                    ? null
                    : '${radio.batteryLevel}%'
                        '${radio.voltage == null ? '' : ' · ${radio.voltage!.toStringAsFixed(2)} V'}'),
            row('Node #', radio.myNodeNum?.toString()),
            row('Mesh nodes', radio.nodeCount.toString()),
            row('BLE id', radio.id),
          ],
        ),
      ),
    );
  }
}
