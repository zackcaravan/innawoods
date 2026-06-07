/// Meshtastic-firmware BLE radio service.
///
/// Talks to ANY device flashed with Meshtastic — LilyGO T-Beam / T-Echo /
/// T-Deck, Heltec, RAK Wireless, and so on — by speaking the standard
/// Meshtastic GATT protocol. Vendor-agnostic by construction; we never
/// special-case a board.
///
/// Three GATT characteristics matter:
///   • FromRadio (notify + read)   — radio → app: MyNodeInfo, NodeInfo,
///                                   Position, MeshPacket, ConfigComplete.
///   • ToRadio   (write)           — app → radio: ToRadio messages, used
///                                   for ConfigOnly request, sending text /
///                                   position packets.
///   • FromNum   (notify)          — radio increments a counter whenever
///                                   there's new FromRadio data; we just
///                                   drain FromRadio on every bump.
///
/// This file is the transport layer. Higher-level routing — bridging chat
/// and positions onto the mesh, dedupe by message UUID, etc. — lives in
/// the mesh_bridge service that ships in Phase 8b.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'generated/meshtastic/mesh.pb.dart' as pb;

/// Meshtastic's published BLE service & characteristic UUIDs. These are
/// stable across firmware versions; the four-character short form is
/// expanded to the full 128-bit UUID Android expects.
class MeshUuids {
  static final Guid service = Guid('6ba1b218-15a8-461f-9fa8-5dcae273eafd');
  static final Guid fromRadio =
      Guid('2c55e69e-4993-11ed-b878-0242ac120002');
  static final Guid toRadio =
      Guid('f75c76d2-129e-4dad-a1dd-7866124401e7');
  static final Guid fromNum =
      Guid('ed9da18c-a800-4f66-a670-aa7547e34453');
}

/// Lightweight summary of a Meshtastic radio surfaced in the scan list.
@immutable
class DiscoveredRadio {
  const DiscoveredRadio({
    required this.id,
    required this.name,
    required this.rssi,
  });
  final String id;        // BLE remote id (MAC on Android, UUID on iOS)
  final String name;
  final int rssi;
}

/// Snapshot of the currently-paired radio — what Settings shows when you
/// land on the LoRa screen.
@immutable
class ConnectedRadio {
  const ConnectedRadio({
    required this.id,
    required this.name,
    this.myNodeNum,
    this.firmwareVersion,
    this.hwModel,
    this.region,
    this.batteryLevel,
    this.voltage,
    this.nodeCount = 0,
  });
  final String id;
  final String name;
  final int? myNodeNum;
  final String? firmwareVersion;
  final String? hwModel;
  final String? region;
  final int? batteryLevel; // 0-100
  final double? voltage;
  final int nodeCount;     // how many peers in the mesh database

  ConnectedRadio copyWith({
    int? myNodeNum,
    String? firmwareVersion,
    String? hwModel,
    String? region,
    int? batteryLevel,
    double? voltage,
    int? nodeCount,
  }) =>
      ConnectedRadio(
        id: id,
        name: name,
        myNodeNum: myNodeNum ?? this.myNodeNum,
        firmwareVersion: firmwareVersion ?? this.firmwareVersion,
        hwModel: hwModel ?? this.hwModel,
        region: region ?? this.region,
        batteryLevel: batteryLevel ?? this.batteryLevel,
        voltage: voltage ?? this.voltage,
        nodeCount: nodeCount ?? this.nodeCount,
      );
}

/// High-level connection lifecycle for the mesh UI to render.
enum MeshConnectionState { disconnected, scanning, connecting, syncing, ready }

/// Singleton-ish service: one paired radio at a time. Survives across
/// screens via Riverpod keepAlive.
class MeshRadioService {
  MeshRadioService();

  final _connectionStateCtrl =
      StreamController<MeshConnectionState>.broadcast();
  final _radioCtrl = StreamController<ConnectedRadio?>.broadcast();
  final _packetsCtrl = StreamController<pb.FromRadio>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();

  Stream<MeshConnectionState> get connectionState =>
      _connectionStateCtrl.stream;
  Stream<ConnectedRadio?> get radio => _radioCtrl.stream;
  Stream<pb.FromRadio> get packets => _packetsCtrl.stream;
  Stream<String> get logs => _logCtrl.stream;

  MeshConnectionState _state = MeshConnectionState.disconnected;
  ConnectedRadio? _radio;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _fromRadio;
  BluetoothCharacteristic? _toRadio;
  BluetoothCharacteristic? _fromNum;
  StreamSubscription<List<int>>? _fromRadioSub;
  StreamSubscription<List<int>>? _fromNumSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  /// Distinct node nums we've seen in NodeInfo packets — counts every peer
  /// the radio knows about (plus the radio itself). Surfaced as the
  /// 'Mesh nodes' row + the on-map status chip.
  final Set<int> _knownNodes = {};

  ConnectedRadio? get currentRadio => _radio;
  MeshConnectionState get currentState => _state;

  void _log(String msg) {
    if (kDebugMode) debugPrint('[mesh] $msg');
    _logCtrl.add(msg);
  }

  void _setState(MeshConnectionState s) {
    _state = s;
    _connectionStateCtrl.add(s);
  }

  void _setRadio(ConnectedRadio? r) {
    _radio = r;
    _radioCtrl.add(r);
  }

  /// Stream of nearby Meshtastic radios. We filter on the canonical service
  /// UUID — Bluetooth peripherals broadcast their primary service in the
  /// advertisement, so only Meshtastic-flashed boards surface. Caller is
  /// responsible for calling [stopScan] when leaving the scan UI.
  Stream<List<DiscoveredRadio>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) async* {
    if (!await _ensureBluetoothOn()) {
      yield const [];
      return;
    }
    await FlutterBluePlus.stopScan();
    _log('starting scan (${timeout.inSeconds}s)');
    final pending = <String, DiscoveredRadio>{};
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        // Match either the service-uuid advertisement (most common) or any
        // device whose name starts with "Meshtastic_" as a fallback in case
        // the radio is advertising in a non-service mode.
        final guids = r.advertisementData.serviceUuids;
        final matchesService = guids.any((g) =>
            g.toString().toLowerCase() == MeshUuids.service.toString().toLowerCase());
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        final matchesName = name.toLowerCase().startsWith('meshtastic');
        if (matchesService || matchesName) {
          pending[r.device.remoteId.str] = DiscoveredRadio(
            id: r.device.remoteId.str,
            name: name.isNotEmpty ? name : 'Meshtastic radio',
            rssi: r.rssi,
          );
        }
      }
    });
    unawaited(FlutterBluePlus.startScan(
      withServices: [MeshUuids.service],
      timeout: timeout,
      // androidUsesFineLocation: false would imply we cannot fall back to
      // location-permission scanning on Android 11 and below; we DO have
      // ACCESS_FINE_LOCATION already, so leave it default.
    ));
    final deadline = DateTime.now().add(timeout + const Duration(seconds: 1));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 500));
      yield pending.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    }
    await sub.cancel();
    await FlutterBluePlus.stopScan();
    yield pending.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  /// Make sure the host BT adapter is on; return false if the user keeps
  /// it off. (UI calls this and surfaces a "Turn on Bluetooth" prompt.)
  Future<bool> _ensureBluetoothOn() async {
    if (await FlutterBluePlus.isSupported == false) {
      _log('BLE not supported on this device');
      return false;
    }
    final adapter = await FlutterBluePlus.adapterState.first;
    if (adapter == BluetoothAdapterState.on) return true;
    _log('adapter state $adapter — waiting for ON');
    // Wait up to ~4 s for the user to toggle BT on, then bail.
    final ready = await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first
        .timeout(const Duration(seconds: 4), onTimeout: () => BluetoothAdapterState.off);
    return ready == BluetoothAdapterState.on;
  }

  /// Connect to a discovered radio, subscribe to FromRadio notifications,
  /// and request a config dump. The radio responds with a stream of
  /// FromRadio packets ending in a ConfigComplete; we surface them on
  /// [packets] and synthesize a [ConnectedRadio] snapshot for the UI.
  Future<void> connect(String remoteId) async {
    await disconnect(); // tear down any prior session cleanly
    _setState(MeshConnectionState.connecting);
    final device = BluetoothDevice(remoteId: DeviceIdentifier(remoteId));
    _device = device;
    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
      _log('connected to $remoteId');
    } catch (e) {
      _log('connect failed: $e');
      _setState(MeshConnectionState.disconnected);
      return;
    }
    _connSub = device.connectionState.listen((s) {
      _log('conn state → $s');
      if (s == BluetoothConnectionState.disconnected) {
        _setRadio(null);
        _setState(MeshConnectionState.disconnected);
      }
    });
    // Negotiate a larger ATT MTU. The default 23-byte MTU gives only 20
    // bytes per characteristic read — most Meshtastic FromRadio packets are
    // larger than that, so protobuf decode would silently fail and the UI
    // would stay stuck on 'Syncing config'. The radio's firmware will cap
    // us at whatever its own ceiling is (typically 247 or 512).
    try {
      final mtu = await device.requestMtu(512);
      _log('negotiated MTU = $mtu');
    } catch (e) {
      _log('requestMtu failed (ignoring): $e');
    }
    // Discover GATT services + locate our three characteristics. Some
    // platforms hand us cached service lists missing characteristics on
    // first connect — discoverServices forces a fresh DB read.
    final services = await device.discoverServices();
    BluetoothService? svc;
    for (final s in services) {
      if (s.uuid == MeshUuids.service) {
        svc = s;
        break;
      }
    }
    if (svc == null) {
      _log('no Meshtastic service on remote — likely wrong firmware');
      await device.disconnect();
      _setState(MeshConnectionState.disconnected);
      return;
    }
    for (final c in svc.characteristics) {
      if (c.uuid == MeshUuids.fromRadio) _fromRadio = c;
      else if (c.uuid == MeshUuids.toRadio) _toRadio = c;
      else if (c.uuid == MeshUuids.fromNum) _fromNum = c;
    }
    if (_fromRadio == null || _toRadio == null) {
      _log('characteristics missing');
      await device.disconnect();
      _setState(MeshConnectionState.disconnected);
      return;
    }
    _setRadio(ConnectedRadio(
      id: remoteId,
      name: device.platformName.isNotEmpty
          ? device.platformName
          : 'Meshtastic radio',
    ));
    _setState(MeshConnectionState.syncing);
    // Subscribe to FromNum so the radio tells us when new FromRadio bytes
    // are queued; we then drain FromRadio.read() until empty.
    if (_fromNum != null) {
      await _fromNum!.setNotifyValue(true);
      _fromNumSub = _fromNum!.onValueReceived.listen((_) => _drainFromRadio());
    }
    // Some firmware versions also push notifications on FromRadio directly.
    await _fromRadio!.setNotifyValue(true);
    _fromRadioSub = _fromRadio!.onValueReceived.listen(_handleBytes);
    // Kick off a config-dump request: the radio will reply with a sequence
    // of FromRadio packets describing its node DB + channel config.
    await _requestConfig();
  }

  Future<void> disconnect() async {
    await _fromRadioSub?.cancel();
    await _fromNumSub?.cancel();
    await _connSub?.cancel();
    _fromRadioSub = null;
    _fromNumSub = null;
    _connSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _fromRadio = null;
    _toRadio = null;
    _fromNum = null;
    _knownNodes.clear();
    _setRadio(null);
    _setState(MeshConnectionState.disconnected);
  }

  /// Drain whatever FromRadio bytes the radio has queued. Each .read()
  /// call gives us at most one protobuf-framed packet; an empty payload
  /// means "no more".
  Future<void> _drainFromRadio() async {
    final c = _fromRadio;
    if (c == null) return;
    for (var i = 0; i < 32; i++) {
      final bytes = await c.read();
      if (bytes.isEmpty) return;
      _handleBytes(bytes);
    }
  }

  void _handleBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    try {
      final fr = pb.FromRadio.fromBuffer(bytes);
      _packetsCtrl.add(fr);
      _absorbForUi(fr);
    } catch (e) {
      _log('decode error: $e (${bytes.length} bytes)');
    }
  }

  /// Pull bits out of incoming FromRadio packets that the Settings UI
  /// wants to surface (firmware version, battery, region, node count).
  void _absorbForUi(pb.FromRadio fr) {
    final cur = _radio;
    if (cur == null) return;
    if (fr.hasMyInfo()) {
      _setRadio(cur.copyWith(myNodeNum: fr.myInfo.myNodeNum));
    } else if (fr.hasNodeInfo()) {
      final ni = fr.nodeInfo;
      _knownNodes.add(ni.num);
      // The radio's own node is identified by num == myNodeNum — pull
      // battery + voltage off its device-metrics for the Settings card.
      var next = cur.copyWith(nodeCount: _knownNodes.length);
      if (cur.myNodeNum != null && ni.num == cur.myNodeNum) {
        next = next.copyWith(
          batteryLevel:
              ni.hasDeviceMetrics() ? ni.deviceMetrics.batteryLevel : null,
          voltage:
              ni.hasDeviceMetrics() ? ni.deviceMetrics.voltage : null,
        );
      }
      // If this NodeInfo also carries a user record with a long name,
      // surface the hw model heuristic as a fallback when Metadata wasn't
      // sent (older firmware path).
      if (cur.hwModel == null && ni.hasUser() && ni.user.hwModel.value != 0) {
        next = next.copyWith(hwModel: ni.user.hwModel.name);
      }
      _setRadio(next);
    } else if (fr.hasConfigCompleteId()) {
      _setState(MeshConnectionState.ready);
    } else if (fr.hasMetadata()) {
      final m = fr.metadata;
      _setRadio(cur.copyWith(
        firmwareVersion: m.firmwareVersion,
        hwModel: m.hwModel.name,
      ));
    } else if (fr.hasConfig()) {
      // Region lives inside LoRaConfig — only present when the firmware
      // pushes a LoRa config block in the dump.
      final cfg = fr.config;
      if (cfg.hasLora()) {
        _setRadio(cur.copyWith(region: cfg.lora.region.name));
      }
    }
  }

  /// Ask the radio to dump its config + drain the FromRadio queue without
  /// waiting on FromNum notifications. The Meshtastic-Android reference
  /// client polls FromRadio in a tight loop after wantConfigId because
  /// some firmware revisions don't reliably notify on FromNum until after
  /// the queue is empty, which is the bug we'd hit otherwise.
  Future<void> _requestConfig() async {
    final c = _toRadio;
    if (c == null) return;
    final req = pb.ToRadio()
      ..wantConfigId = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
    await c.write(req.writeToBuffer(), withoutResponse: false);
    _log('sent wantConfigId=${req.wantConfigId}');
    // Poll-drain — keep reading until we hit a string of empties or land
    // on ready. The radio queue can hold dozens of packets for a typical
    // node DB; cap at 200 reads so a stuck radio can't lock us up.
    var consecutiveEmpties = 0;
    for (var i = 0; i < 200; i++) {
      if (_state == MeshConnectionState.ready) break;
      final bytes = await _fromRadio?.read();
      if (bytes == null || bytes.isEmpty) {
        consecutiveEmpties++;
        if (consecutiveEmpties >= 3) break;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        continue;
      }
      consecutiveEmpties = 0;
      _handleBytes(bytes);
    }
    _log('config drain done (state=$_state)');
  }

  /// Write a raw ToRadio protobuf to the radio. Phase 8b will wrap this
  /// for sending text packets, position packets, channel updates, etc.
  Future<void> sendToRadio(pb.ToRadio msg) async {
    final c = _toRadio;
    if (c == null) throw StateError('not connected');
    await c.write(msg.writeToBuffer(), withoutResponse: false);
  }

  /// Helper: byte view of MAC-style remoteId, for matching against
  /// last-paired stored in shared_preferences (Phase 8b).
  static Uint8List remoteIdBytes(String id) =>
      Uint8List.fromList(id.codeUnits);
}
