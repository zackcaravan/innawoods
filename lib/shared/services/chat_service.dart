import 'dart:async';

import 'package:cryptography/cryptography.dart';
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

  Future<void> send({required String partyId, required String text}) async {
    final key = await _session.groupKey(partyId);
    if (key == null) throw StateError('No encryption key for this party');
    // Stable per-message id baked into the ciphertext so receivers can
    // dedupe regardless of which transport delivered first.
    final msgUuid = _uuid.v4();
    final payload = await _crypto.encryptJson(
        groupKey: key, data: {'text': text, 'uuid': msgUuid});
    final wire = payload.toWire();
    // Fan out: Supabase is the primary transport for any device with
    // internet; the mesh bridge is the redundant transport for devices
    // out of cell range. Both go in parallel; either alone is enough to
    // get the message delivered.
    final supabaseFuture = _client.from('messages').insert({
      'party_id': partyId,
      'sender_id': _client.auth.currentUser!.id,
      'encrypted_payload': wire,
    });
    // Don't fail the whole send if mesh broadcast errors — Supabase is
    // good enough on its own when paired. Wrap as Future<void> to satisfy
    // Future.wait's homogeneous-typed requirement.
    final Future<void> meshFuture = _bridge
        .broadcast(
          partyId: partyId,
          type: MeshMsgType.chat,
          ciphertext: payload.toBytes(),
        )
        .then<void>((_) {})
        .catchError((Object _) {});
    await Future.wait<void>([supabaseFuture.then<void>((_) {}), meshFuture]);
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
        messages[uuid] = ChatMessage(
          id: uuid,
          senderId: senderId ?? '',
          callsign: meta[senderId ?? ''] ?? '??',
          text: data['text'] as String? ?? '',
          sentAt: sentAt,
          mine: senderId == selfId,
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
      emit();
    }

    controller.onListen = init;
    controller.onCancel = () async {
      await meshSub?.cancel();
      final ch = channel;
      if (ch != null) await _client.removeChannel(ch);
      if (!controller.isClosed) await controller.close();
    };
    return controller.stream;
  }
}
