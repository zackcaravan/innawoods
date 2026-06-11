// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'generated/meshtastic/mesh.pb.dart' as pb;
import 'generated/meshtastic/portnums.pb.dart' as portnums;
import 'mesh_envelope.dart';
import 'mesh_radio.dart';

/// innawoods's private Meshtastic app port. The Meshtastic firmware
/// reserves the PRIVATE_APP range (PortNum >= 256) for third-party apps;
/// we pick 257 ("PRIVATE_APP + 1") as the canonical innawoods slot.
const int innawoodsPortNum = 257;

/// One inbound mesh-fed party event after envelope decode.
class InboundMeshEvent {
  const InboundMeshEvent({
    required this.partyIdHash,
    required this.type,
    required this.msgUuid,
    required this.timestampMs,
    required this.ciphertext,
    required this.fromNodeNum,
  });
  final Uint8List partyIdHash;
  final MeshMsgType type;
  final Uint8List msgUuid;
  final int timestampMs;
  final Uint8List ciphertext;
  final int fromNodeNum;
}

/// Bridges innawoods's party traffic onto the mesh. Sits between
/// [MeshRadioService] (raw FromRadio / ToRadio packets) and the existing
/// chat / position providers (which consume Supabase Realtime today).
///
/// Phase 8b ships the encode/decode layer + inbound stream. Wiring those
/// inbound events into [partyLiveProvider] and [partyMessagesProvider] as
/// a second source of truth lands in 8c — that step needs hardware-loop
/// testing first so it's easier to land as a small, focused diff.
class MeshBridge {
  MeshBridge(this._radio) {
    _packetSub = _radio.packets.listen(_onFromRadio);
  }

  final MeshRadioService _radio;
  StreamSubscription<pb.FromRadio>? _packetSub;
  final _inboundCtrl = StreamController<InboundMeshEvent>.broadcast();
  final _uuid = const Uuid();

  /// Inbound stream — every well-formed innawoods envelope decoded off
  /// the mesh. Consumers filter by `partyIdHash` to their party.
  Stream<InboundMeshEvent> get inbound => _inboundCtrl.stream;

  void dispose() {
    _packetSub?.cancel();
    _inboundCtrl.close();
  }

  void _onFromRadio(pb.FromRadio fr) {
    if (!fr.hasPacket()) return;
    final mp = fr.packet;
    if (!mp.hasDecoded()) return; // encrypted at radio layer — wrong channel
    final data = mp.decoded;
    if (data.portnum.value != innawoodsPortNum) return;
    final env = MeshEnvelope.tryDecode(Uint8List.fromList(data.payload));
    if (env == null) {
      if (kDebugMode) {
        debugPrint('[mesh-bridge] dropped malformed envelope from ${mp.from}');
      }
      return;
    }
    _inboundCtrl.add(InboundMeshEvent(
      partyIdHash: env.partyIdHash,
      type: env.type,
      msgUuid: env.msgUuidBytes,
      timestampMs: env.timestampMs,
      ciphertext: env.ciphertext,
      fromNodeNum: mp.from,
    ));
  }

  /// Send an innawoods chat or position blob over the mesh as a broadcast.
  /// Caller supplies the already-encrypted ciphertext (we don't decrypt or
  /// re-encrypt). Returns the 16-byte message UUID so the caller can
  /// dedupe its own echoes when the same message also arrives over
  /// Supabase Realtime.
  Future<Uint8List?> broadcast({
    required String partyId,
    required MeshMsgType type,
    required Uint8List ciphertext,
  }) async {
    if (_radio.currentState != MeshConnectionState.ready) return null;
    final uuid = Uint8List(16);
    _uuid.v4buffer(uuid);
    final env = MeshEnvelope(
      type: type,
      partyIdHash: MeshEnvelope.hashParty(partyId),
      msgUuidBytes: uuid,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      ciphertext: ciphertext,
    );
    final Uint8List wire;
    try {
      wire = env.encode();
    } on ArgumentError catch (e) {
      if (kDebugMode) debugPrint('[mesh-bridge] $e');
      return null;
    }
    final data = pb.Data()
      ..portnum = portnums.PortNum.valueOf(innawoodsPortNum) ??
          portnums.PortNum.PRIVATE_APP
      ..payload = wire;
    final mp = pb.MeshPacket()
      ..to = 0xFFFFFFFF // broadcast
      ..wantAck = false
      ..decoded = data;
    final out = pb.ToRadio()..packet = mp;
    try {
      await _radio.sendToRadio(out);
    } catch (e) {
      if (kDebugMode) debugPrint('[mesh-bridge] sendToRadio failed: $e');
      return null;
    }
    return uuid;
  }
}
