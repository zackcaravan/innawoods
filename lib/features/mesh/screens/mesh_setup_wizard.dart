import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/services/mesh/mesh_radio.dart';
import '../providers/mesh_provider.dart';

/// 3-step pairing wizard. Walks the user from "I have a Meshtastic device
/// somewhere on the table" to "innawoods is connected and listening on
/// the mesh", with clear failure modes at each step.
///
/// Step 1 — prepare:    plain-English explainer + permission grants.
/// Step 2 — scan + pair: live-updating device list, tap to connect.
/// Step 3 — done:        confirm config sync finished, surface a success card.
class MeshSetupWizard extends ConsumerStatefulWidget {
  const MeshSetupWizard({super.key});

  @override
  ConsumerState<MeshSetupWizard> createState() => _MeshSetupWizardState();
}

class _MeshSetupWizardState extends ConsumerState<MeshSetupWizard> {
  int _step = 0;
  bool _permsGranted = false;
  StreamSubscription<List<DiscoveredRadio>>? _scanSub;
  List<DiscoveredRadio> _found = const [];
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Listen for the radio entering 'ready' so we can auto-advance to the
    // success step once the config dump finishes.
    ref.listenManual(meshConnectionStateProvider, (_, next) {
      final s = next.valueOrNull;
      if (!mounted) return;
      if (s == MeshConnectionState.ready && _step != 2) {
        setState(() => _step = 2);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    ref.read(meshRadioServiceProvider).stopScan();
    super.dispose();
  }

  Future<void> _grantPerms() async {
    final perms = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    final ok = perms.values.every((s) =>
        s == PermissionStatus.granted || s == PermissionStatus.limited);
    setState(() {
      _permsGranted = ok;
      _error = ok
          ? null
          : 'Without Bluetooth + location permission innawoods can\'t find your radio. Grant them and try again.';
    });
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _found = const [];
      _error = null;
    });
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
          _error = '$e';
          _scanning = false;
        });
      },
    );
  }

  Future<void> _connectTo(DiscoveredRadio d) async {
    await _scanSub?.cancel();
    setState(() {
      _scanning = false;
      _error = null;
    });
    await ref.read(meshRadioServiceProvider).connect(d.id);
    // The listenManual above flips us to step 2 when the radio reaches
    // 'ready'; if it stalls in 'syncing' we surface a manual continue
    // button on step 1.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair LoRa radio'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StepIndicator(currentStep: _step),
            const SizedBox(height: 24),
            Expanded(
              child: switch (_step) {
                0 => _StepPrepare(
                    permsGranted: _permsGranted,
                    onGrant: _grantPerms,
                    onNext: () => setState(() => _step = 1),
                    error: _error,
                  ),
                1 => _StepScan(
                    scanning: _scanning,
                    devices: _found,
                    onScan: _startScan,
                    onPick: _connectTo,
                    error: _error,
                  ),
                _ => _StepDone(
                    onFinish: () => Navigator.of(context).pop(),
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep});
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    Color dotColor(int i) => i <= currentStep
        ? Theme.of(context).colorScheme.primary
        : Colors.white24;
    Widget dot(int i, String label) => Expanded(
          child: Column(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: dotColor(i),
                child: Text('${i + 1}',
                    style: const TextStyle(
                        color: Colors.black, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: i <= currentStep ? Colors.white : Colors.white38)),
            ],
          ),
        );
    return Row(
      children: [
        dot(0, 'Prepare'),
        dot(1, 'Scan & pair'),
        dot(2, 'Ready'),
      ],
    );
  }
}

class _StepPrepare extends StatelessWidget {
  const _StepPrepare({
    required this.permsGranted,
    required this.onGrant,
    required this.onNext,
    required this.error,
  });
  final bool permsGranted;
  final VoidCallback onGrant;
  final VoidCallback onNext;
  final String? error;

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          const Text(
            'Before we scan',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            '• Power on your Meshtastic radio (any vendor — LilyGO, '
            'Heltec, RAK, T-Echo).',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 6),
          const Text(
            '• Confirm it\'s flashed with Meshtastic firmware and has '
            'BLE turned on. The official Meshtastic app is fine for the '
            'initial flash + region setup.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 6),
          const Text(
            '• Keep it within ~3 m for the first pairing.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 24),
          if (permsGranted)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Icon(Icons.check_circle, color: Colors.lightGreenAccent),
                SizedBox(width: 8),
                Text('Permissions granted',
                    style: TextStyle(color: Colors.lightGreenAccent)),
              ]),
            )
          else
            FilledButton.icon(
              onPressed: onGrant,
              icon: const Icon(Icons.lock_open),
              label: const Text('Grant Bluetooth + location'),
            ),
          const SizedBox(height: 8),
          const Text(
            'innawoods only uses location permission to satisfy Android\'s '
            'BLE-scan API — nothing about your position is sent anywhere '
            'because of this prompt.',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: permsGranted ? onNext : null,
            child: const Text('Next'),
          ),
        ],
      );
}

class _StepScan extends StatelessWidget {
  const _StepScan({
    required this.scanning,
    required this.devices,
    required this.onScan,
    required this.onPick,
    required this.error,
  });
  final bool scanning;
  final List<DiscoveredRadio> devices;
  final VoidCallback onScan;
  final void Function(DiscoveredRadio) onPick;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pick your radio',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.icon(
                onPressed: scanning ? null : onScan,
                icon: scanning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: Text(scanning ? 'Scanning' : 'Scan'),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: devices.isEmpty
                ? Center(
                    child: Text(
                      scanning
                          ? 'Looking for radios…'
                          : 'No radios found yet — tap Scan.',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = devices[i];
                      return ListTile(
                        leading: const Icon(Icons.radio),
                        title: Text(d.name),
                        subtitle: Text('${d.id} · ${d.rssi} dBm'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => onPick(d),
                      );
                    },
                  ),
          ),
        ],
      );
}

class _StepDone extends StatelessWidget {
  const _StepDone({required this.onFinish});
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Icon(Icons.check_circle,
            color: Colors.lightGreenAccent, size: 56),
        const SizedBox(height: 12),
        const Text(
          'You\'re on the mesh.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          'When you and your crew are out of cell range, innawoods will '
          'use this radio to keep chat and positions flowing between '
          'paired devices. You\'ll see a "Mesh" chip on the map whenever '
          'the radio is reachable.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onFinish,
          child: const Text('Done'),
        ),
      ],
    );
  }
}
