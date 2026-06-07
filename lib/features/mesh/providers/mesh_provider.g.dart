// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mesh_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$meshRadioServiceHash() => r'6403f356f57caf33d3c119a18e07cca6ddd146c3';

/// Singleton mesh-radio service. KeepAlive so the BLE connection survives
/// when the Settings screen unmounts and we navigate back to the map.
///
/// Copied from [meshRadioService].
@ProviderFor(meshRadioService)
final meshRadioServiceProvider = Provider<MeshRadioService>.internal(
  meshRadioService,
  name: r'meshRadioServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$meshRadioServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MeshRadioServiceRef = ProviderRef<MeshRadioService>;
String _$connectedRadioHash() => r'bc1da86e062f00afdf88560592471c352166f98d';

/// Live connected-radio snapshot. Settings reads this to render firmware,
/// battery, etc.; null when no radio is paired.
///
/// Copied from [connectedRadio].
@ProviderFor(connectedRadio)
final connectedRadioProvider = StreamProvider<ConnectedRadio?>.internal(
  connectedRadio,
  name: r'connectedRadioProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$connectedRadioHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ConnectedRadioRef = StreamProviderRef<ConnectedRadio?>;
String _$meshConnectionStateHash() =>
    r'1841d75b7238ecf72df05c6108bbeac7b3346230';

/// Connection lifecycle — disconnected → scanning → connecting → syncing
/// → ready. Drives the status chip on the map.
///
/// Copied from [meshConnectionState].
@ProviderFor(meshConnectionState)
final meshConnectionStateProvider =
    StreamProvider<MeshConnectionState>.internal(
      meshConnectionState,
      name: r'meshConnectionStateProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$meshConnectionStateHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MeshConnectionStateRef = StreamProviderRef<MeshConnectionState>;
String _$meshBridgeHash() => r'6367f5dd0954873cbf13f7dcfadf3368e6a36381';

/// Singleton bridge — wraps the radio service to encode/decode innawoods
/// envelopes onto Meshtastic MeshPackets. Disposed when the provider is
/// torn down, which only happens at app shutdown.
///
/// Copied from [meshBridge].
@ProviderFor(meshBridge)
final meshBridgeProvider = Provider<MeshBridge>.internal(
  meshBridge,
  name: r'meshBridgeProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$meshBridgeHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MeshBridgeRef = ProviderRef<MeshBridge>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
