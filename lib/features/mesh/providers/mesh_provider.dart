import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/services/mesh/mesh_bridge.dart';
import '../../../shared/services/mesh/mesh_radio.dart';

part 'mesh_provider.g.dart';

/// Singleton mesh-radio service. KeepAlive so the BLE connection survives
/// when the Settings screen unmounts and we navigate back to the map.
@Riverpod(keepAlive: true)
MeshRadioService meshRadioService(Ref ref) {
  final svc = MeshRadioService();
  ref.onDispose(() {
    svc.disconnect();
  });
  return svc;
}

/// Live connected-radio snapshot. Settings reads this to render firmware,
/// battery, etc.; null when no radio is paired.
@Riverpod(keepAlive: true)
Stream<ConnectedRadio?> connectedRadio(Ref ref) =>
    ref.watch(meshRadioServiceProvider).radio;

/// Connection lifecycle — disconnected → scanning → connecting → syncing
/// → ready. Drives the status chip on the map.
@Riverpod(keepAlive: true)
Stream<MeshConnectionState> meshConnectionState(Ref ref) =>
    ref.watch(meshRadioServiceProvider).connectionState;

/// Singleton bridge — wraps the radio service to encode/decode innawoods
/// envelopes onto Meshtastic MeshPackets. Disposed when the provider is
/// torn down, which only happens at app shutdown.
@Riverpod(keepAlive: true)
MeshBridge meshBridge(Ref ref) {
  final svc = ref.watch(meshRadioServiceProvider);
  final bridge = MeshBridge(svc);
  ref.onDispose(bridge.dispose);
  return bridge;
}
