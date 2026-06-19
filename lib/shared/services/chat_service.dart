// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/encrypted_payload.dart';
import '../models/chat_message.dart';
import 'crypto_session.dart';
import 'mesh/mesh_bridge.dart';
import 'mesh/mesh_envelope.dart';

/// Per-party encrypted text chat. Messages are sealed under the group key and
/// are ephemeral — `end_party` purges them server-side along with locations.
///
/// Phase 8c: every send also broadcasts via the mesh bridge when a LoRa radio
/// is paired, and every watch subscribes to both Supabase Realtime AND the
/// mesh bridge's inbound stream. A `uuid` field baked into the encrypted
/// payload de-duplicates messages that arrive over both transports — only
/// the first one to land surfaces in the UI.
class ChatService {
  ChatService(this._client, this._crypto, this._session, this._bridge);

  final SupabaseClient _client;
  final CryptoService _crypto;
  final CryptoSession _session;
  final MeshBridge _bridge;

  static const _uuid = Uuid();

  /// Local-echo stream so own messages appear in the chat the instant they're
  /// sent, without waiting for the Supabase round-trip. Critical for offline
  /// use where the round-trip never completes. Dedupe on msgUuid stops the
  /// echo from doubling when Supabase eventually catches up online.
  final StreamController<_LocalChatEcho> _localEchoes =
      StreamController<_LocalChatEcho>.broadcast();

  Future<void> send({required String partyId, required String text}) =>
      _send(partyId: partyId, text: text, kind: ChatKind.text);

  /// Broadcast a Man-down mayday to the party. Reuses the encrypted-chat
  /// fanout (Supabase + mesh) so receivers get it over whatever transport
  /// is alive, with the same dedup-by-uuid guarantees. [location] is
  /// embedded inside the ciphertext so receivers can route to the sender
  /// without waiting for the next location publish to catch up.
  Future<void> sendMayday({
    required String partyId,
    required LatLng location,
    String? note,
  }) => _send(
        partyId: partyId,
        text: note ?? 'Man down',
        kind: ChatKind.mayday,
        extras: {
          'mayday_lat': location.latitude,
          'mayday_lng': location.longitude,
        },
      );

  Future<void> _send({
    required String partyId,
    required String text,
    required ChatKind kind,
    Map<String, Object?>? extras,
  }) async {
    final key = await _session.groupKey(partyId);
    if (key == null) throw StateError('No encryption key for this party');
    final userId = _client.auth.currentUser!.id;
    // Bake the sender id INSIDE the ciphertext so mesh receivers (which
    // don't get a Supabase sender_id column) can still attribute the
    // message to the right callsign. The msgUuid de-dupes across
    // transports when both deliver the same message.
    final msgUuid = _uuid.v4();
    final sentAt = DateTime.now().toUtc();
    final payload = await _crypto.encryptJson(groupKey: key, data: {
      'text': text,
      'uuid': msgUuid,
      'user_id': userId,
      if (kind != ChatKind.text) 'kind': kind.id,
      if (extras != null) ...extras,
    });
    final wire = payload.toWire();
    // Local echo first — the user sees their own message immediately even
    // when both transports fail (e.g. radio busy + cell out).
    _localEchoes.add(_LocalChatEcho(
      uuid: msgUuid,
      text: text,
      userId: userId,
      sentAt: sentAt,
      kind: kind,
      maydayLat: (extras?['mayday_lat'] as num?)?.toDouble(),
      maydayLng: (extras?['mayday_lng'] as num?)?.toDouble(),
    ));
    // Both transports run in parallel, each isolated so an offline
    // Supabase can't sink the mesh delivery and vice versa.
    final supabaseFuture = () async {
      try {
        await _client.from('messages').insert({
          'party_id': partyId,
          'sender_id': userId,
          'encrypted_payload': wire,
        });
      } catch (_) {/* offline — mesh is the fallback */}
    }();
    final meshFuture = () async {
      try {
        await _bridge.broadcast(
          partyId: partyId,
          type: MeshMsgType.chat,
          ciphertext: payload.toBytes(),
        );
      } catch (_) {/* radio busy / not paired — silent */}
    }();
    await Future.wait([supabaseFuture, meshFuture]);
  }

  Stream<List<ChatMessage>> watch(String partyId) {
    final controller = StreamController<List<ChatMessage>>();
    // Keyed by msgUuid extracted from decrypted payload — the same key
    // for both Supabase- and mesh-delivered copies of any message.
    final messages = <String, ChatMessage>{};
    var meta = <String, String>{}; // userId -> callsign
    final selfId = _client.auth.currentUser?.id;
    final partyHash = MeshEnvelope.hashParty(partyId);
    SecretKey? key;
    RealtimeChannel? channel;
    StreamSubscription<InboundMeshEvent>? meshSub;
    StreamSubscription<_LocalChatEcho>? echoSub;

    void emit() {
      if (controller.isClosed) return;
      controller.add(messages.values.toList()
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt)));
    }

    Future<void> _absorb({
      required EncryptedPayload payload,
      required String? senderId,
      required DateTime sentAt,
      String? fallbackId,
    }) async {
      final k = key;
      if (k == null) return;
      try {
        final data = await _crypto.decryptJson(payload: payload, groupKey: k);
        final uuid = data['uuid'] as String? ?? fallbackId;
        if (uuid == null) return; // no dedupe key — skip
        if (messages.containsKey(uuid)) return; // already have it
        // Trust the row's sender_id when present (Supabase path); fall
        // back to the user_id baked into the encrypted payload for
        // mesh-only messages where the row column doesn't exist.
        final sender = senderId ?? data['user_id'] as String?;
        final kind = ChatKind.fromId(data['kind'] as String?);
        MaydayPayload? mayday;
        if (kind == ChatKind.mayday) {
          final lat = (data['mayday_lat'] as num?)?.toDouble();
          final lng = (data['mayday_lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            mayday = MaydayPayload(location: LatLng(lat, lng));
          }
        }
        messages[uuid] = ChatMessage(
          id: uuid,
          senderId: sender ?? '',
          callsign: meta[sender ?? ''] ?? '??',
          text: data['text'] as String? ?? '',
          sentAt: sentAt,
          mine: sender == selfId,
          kind: kind,
          mayday: mayday,
        );
        emit();
      } catch (_) {
        // undecryptable — wrong key, garbled, or message-from-the-future
      }
    }

    Future<void> ingestSupabaseRow(Map<String, dynamic> row) async {
      final id = row['id'] as String?;
      final wire = row['encrypted_payload'] as String?;
      final sender = row['sender_id'] as String?;
      if (wire == null) return;
      final sentAt =
          DateTime.tryParse(row['sent_at'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc();
      await _absorb(
        payload: EncryptedPayload.fromWire(wire),
        senderId: sender,
        sentAt: sentAt,
        fallbackId: id,
      );
    }

    Future<void> ingestMeshEvent(InboundMeshEvent ev) async {
      if (ev.type != MeshMsgType.chat) return;
      // Wrong party? The 8-byte hash check is cheap and avoids wasted
      // decryption attempts on packets from other innawoods crews on the
      // same mesh channel.
      if (ev.partyIdHash.length != partyHash.length) return;
      for (var i = 0; i < partyHash.length; i++) {
        if (ev.partyIdHash[i] != partyHash[i]) return;
      }
      await _absorb(
        payload: EncryptedPayload.fromBytes(ev.ciphertext),
        senderId: null, // mesh layer doesn't preserve user_id; the
                       // displayed callsign falls back to '??'
        sentAt: DateTime.fromMillisecondsSinceEpoch(ev.timestampMs).toUtc(),
      );
    }

    Future<void> init() async {
      key = await _session.groupKey(partyId);
      final members = await _client
          .from('party_members')
          .select('user_id,callsign')
          .eq('party_id', partyId);
      meta = {
        for (final m in (members as List))
          (m['user_id'] as String): (m['callsign'] as String? ?? '??'),
      };
      final rows = await _client
          .from('messages')
          .select()
          .eq('party_id', partyId)
          .order('sent_at');
      for (final r in (rows as List)) {
        await ingestSupabaseRow(Map<String, dynamic>.from(r as Map));
      }
      channel = _client.channel('party-chat-$partyId');
      channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'party_id',
                value: partyId),
            callback: (payload) {
              if (payload.newRecord.isNotEmpty) {
                ingestSupabaseRow(Map<String, dynamic>.from(payload.newRecord));
              }
            },
          )
          .subscribe();
      // Mesh inbound — parallel to Supabase Realtime. Decoupled lifetime:
      // both can fail independently and the other keeps working.
      meshSub = _bridge.inbound.listen(ingestMeshEvent);
      // Local-echo subscription — own messages from send() land here
      // before any network round-trip completes.
      echoSub = _localEchoes.stream.listen((ev) {
        if (messages.containsKey(ev.uuid)) return;
        MaydayPayload? mayday;
        if (ev.kind == ChatKind.mayday &&
            ev.maydayLat != null && ev.maydayLng != null) {
          mayday = MaydayPayload(
              location: LatLng(ev.maydayLat!, ev.maydayLng!));
        }
        messages[ev.uuid] = ChatMessage(
          id: ev.uuid,
          senderId: ev.userId,
          callsign: meta[ev.userId] ?? '??',
          text: ev.text,
          sentAt: ev.sentAt,
          mine: ev.userId == selfId,
          kind: ev.kind,
          mayday: mayday,
        );
        emit();
      });
      emit();
    }

    controller.onListen = init;
    controller.onCancel = () async {
      await meshSub?.cancel();
      await echoSub?.cancel();
      final ch = channel;
      if (ch != null) await _client.removeChannel(ch);
      if (!controller.isClosed) await controller.close();
    };
    return controller.stream;
  }
}

/// One own-message event piped from [ChatService.send] to every active
/// [ChatService.watch] subscriber so the sender's UI updates instantly
/// regardless of whether Supabase or the mesh ever ack the broadcast.
class _LocalChatEcho {
  const _LocalChatEcho({
    required this.uuid,
    required this.text,
    required this.userId,
    required this.sentAt,
    this.kind = ChatKind.text,
    this.maydayLat,
    this.maydayLng,
  });
  final String uuid;
  final String text;
  final String userId;
  final DateTime sentAt;
  final ChatKind kind;
  final double? maydayLat;
  final double? maydayLng;
}
