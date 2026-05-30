import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/encrypted_payload.dart';
import '../models/map_pin.dart';
import 'crypto_session.dart';

/// Drop / stream / delete encrypted pins. Same zero-knowledge pattern as
/// locations: the payload (name/coords/note) is sealed under the group key;
/// only `pin_type` is plaintext.
class PinService {
  PinService(this._client, this._crypto, this._session);

  final SupabaseClient _client;
  final CryptoService _crypto;
  final CryptoSession _session;

  Future<void> drop({
    required String partyId,
    required String type,
    required String name,
    required LatLng location,
    String? note,
  }) async {
    final key = await _session.groupKey(partyId);
    if (key == null) throw StateError('No encryption key for this party');
    final payload = await _crypto.encryptJson(groupKey: key, data: {
      'name': name,
      'lat': location.latitude,
      'lng': location.longitude,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    await _client.from('pins').insert({
      'party_id': partyId,
      'user_id': _client.auth.currentUser!.id,
      'pin_type': type,
      'encrypted_payload': payload.toWire(),
    });
  }

  Future<void> delete(String pinId) =>
      _client.from('pins').delete().eq('id', pinId);

  Stream<List<MapPin>> watch(String partyId) {
    final controller = StreamController<List<MapPin>>();
    final pins = <String, MapPin>{};
    final selfId = _client.auth.currentUser?.id;
    SecretKey? key;
    RealtimeChannel? channel;

    void emit() {
      if (controller.isClosed) return;
      controller.add(pins.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    }

    Future<void> ingest(Map<String, dynamic> row) async {
      final k = key;
      if (k == null) return;
      final id = row['id'] as String?;
      final wire = row['encrypted_payload'] as String?;
      if (id == null || wire == null) return;
      try {
        final data = await _crypto.decryptJson(
            payload: EncryptedPayload.fromWire(wire), groupKey: k);
        pins[id] = MapPin(
          id: id,
          userId: row['user_id'] as String? ?? '',
          type: row['pin_type'] as String? ?? 'custom',
          name: data['name'] as String? ?? 'Pin',
          location: LatLng((data['lat'] as num).toDouble(),
              (data['lng'] as num).toDouble()),
          note: data['note'] as String?,
          createdAt: DateTime.tryParse(row['created_at'] as String? ?? '')
                  ?.toUtc() ??
              DateTime.now().toUtc(),
          mine: (row['user_id'] as String?) == selfId,
        );
        emit();
      } catch (_) {/* undecryptable — skip */}
    }

    Future<void> init() async {
      key = await _session.groupKey(partyId);
      final rows =
          await _client.from('pins').select().eq('party_id', partyId);
      for (final r in (rows as List)) {
        await ingest(Map<String, dynamic>.from(r as Map));
      }
      channel = _client.channel('party-pins-$partyId');
      channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'pins',
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
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'pins',
            callback: (payload) {
              final id = payload.oldRecord['id'] as String?;
              if (id != null && pins.remove(id) != null) emit();
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
