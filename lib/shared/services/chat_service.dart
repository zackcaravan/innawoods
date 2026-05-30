import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/encrypted_payload.dart';
import '../models/chat_message.dart';
import 'crypto_session.dart';

/// Per-party encrypted text chat. Messages are sealed under the group key and
/// are ephemeral — `end_party` purges them server-side along with locations.
class ChatService {
  ChatService(this._client, this._crypto, this._session);

  final SupabaseClient _client;
  final CryptoService _crypto;
  final CryptoSession _session;

  Future<void> send({required String partyId, required String text}) async {
    final key = await _session.groupKey(partyId);
    if (key == null) throw StateError('No encryption key for this party');
    final payload = await _crypto.encryptJson(groupKey: key, data: {'text': text});
    await _client.from('messages').insert({
      'party_id': partyId,
      'sender_id': _client.auth.currentUser!.id,
      'encrypted_payload': payload.toWire(),
    });
  }

  Stream<List<ChatMessage>> watch(String partyId) {
    final controller = StreamController<List<ChatMessage>>();
    final messages = <String, ChatMessage>{};
    var meta = <String, String>{}; // userId -> callsign
    final selfId = _client.auth.currentUser?.id;
    SecretKey? key;
    RealtimeChannel? channel;

    void emit() {
      if (controller.isClosed) return;
      controller.add(messages.values.toList()
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt)));
    }

    Future<void> ingest(Map<String, dynamic> row) async {
      final k = key;
      if (k == null) return;
      final id = row['id'] as String?;
      final wire = row['encrypted_payload'] as String?;
      final sender = row['sender_id'] as String?;
      if (id == null || wire == null || sender == null) return;
      try {
        final data = await _crypto.decryptJson(
            payload: EncryptedPayload.fromWire(wire), groupKey: k);
        messages[id] = ChatMessage(
          id: id,
          senderId: sender,
          callsign: meta[sender] ?? '??',
          text: data['text'] as String? ?? '',
          sentAt:
              DateTime.tryParse(row['sent_at'] as String? ?? '')?.toUtc() ??
                  DateTime.now().toUtc(),
          mine: sender == selfId,
        );
        emit();
      } catch (_) {/* undecryptable — skip */}
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
        await ingest(Map<String, dynamic>.from(r as Map));
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
                ingest(Map<String, dynamic>.from(payload.newRecord));
              }
            },
          )
          .subscribe();
      emit();
    }

    controller.onListen = init;
    controller.onCancel = () async {
      final ch = channel;
      if (ch != null) await _client.removeChannel(ch);
      if (!controller.isClosed) await controller.close();
    };
    return controller.stream;
  }
}
