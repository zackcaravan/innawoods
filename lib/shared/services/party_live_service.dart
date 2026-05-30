import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/encrypted_payload.dart';
import '../models/member_position.dart';
import 'crypto_session.dart';

/// Streams the live, decrypted positions of every member of a party.
///
/// Flow: derive the group key → seed from existing rows → subscribe to Supabase
/// Realtime on `location_updates` (filtered to this party) → decrypt each
/// incoming blob client-side → emit the merged roster. The server only ever
/// relays ciphertext; decryption happens here with the on-device group key.
class PartyLiveService {
  PartyLiveService(this._client, this._crypto, this._session);

  final SupabaseClient _client;
  final CryptoService _crypto;
  final CryptoSession _session;

  Stream<List<MemberPosition>> watch(String partyId) {
    final controller = StreamController<List<MemberPosition>>();
    final positions = <String, MemberPosition>{};
    var meta = <String, ({String callsign, String color})>{};
    final selfId = _client.auth.currentUser?.id;
    SecretKey? groupKey;
    RealtimeChannel? channel;
    Timer? staleTicker;

    void emit() {
      if (controller.isClosed) return;
      final list = positions.values.toList()
        ..sort((a, b) => a.callsign.compareTo(b.callsign));
      controller.add(list);
    }

    Future<void> ingest(Map<String, dynamic> row) async {
      final key = groupKey;
      if (key == null) return;
      final uid = row['user_id'] as String?;
      final wire = row['encrypted_payload'] as String?;
      if (uid == null || wire == null) return;
      try {
        final data = await _crypto.decryptJson(
          payload: EncryptedPayload.fromWire(wire),
          groupKey: key,
        );
        final m = meta[uid];
        positions[uid] = MemberPosition(
          userId: uid,
          callsign: m?.callsign ?? '??',
          color: m?.color ?? '#C19A6B',
          location: LatLng(
            (data['lat'] as num).toDouble(),
            (data['lng'] as num).toDouble(),
          ),
          speed: (data['speed'] as num?)?.toDouble(),
          heading: (data['heading'] as num?)?.toDouble(),
          updatedAt: DateTime.parse(data['ts'] as String).toUtc(),
          isSelf: uid == selfId,
        );
        emit();
      } catch (_) {
        // Undecryptable (no key / tampered) — ignore rather than crash.
      }
    }

    Future<void> init() async {
      groupKey = await _session.groupKey(partyId);

      final members = await _client
          .from('party_members')
          .select('user_id,callsign,color')
          .eq('party_id', partyId);
      meta = {
        for (final m in (members as List))
          (m['user_id'] as String): (
            callsign: m['callsign'] as String,
            color: m['color'] as String? ?? '#C19A6B',
          ),
      };

      final rows = await _client
          .from('location_updates')
          .select()
          .eq('party_id', partyId);
      for (final r in (rows as List)) {
        await ingest(Map<String, dynamic>.from(r as Map));
      }

      channel = _client.channel('party-loc-$partyId');
      channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'location_updates',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'party_id',
              value: partyId,
            ),
            callback: (payload) {
              if (payload.newRecord.isNotEmpty) {
                ingest(Map<String, dynamic>.from(payload.newRecord));
              }
            },
          )
          .subscribe();

      // Re-emit periodically so "last seen" / stale styling stays current.
      staleTicker = Timer.periodic(const Duration(seconds: 20), (_) => emit());
      emit();
    }

    controller.onListen = init;
    controller.onCancel = () async {
      staleTicker?.cancel();
      final ch = channel;
      if (ch != null) await _client.removeChannel(ch);
      if (!controller.isClosed) await controller.close();
    };
    return controller.stream;
  }
}
