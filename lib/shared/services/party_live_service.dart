import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/encrypted_payload.dart';
import '../models/member_position.dart';
import 'crypto_session.dart';
import 'mesh/mesh_bridge.dart';
import 'mesh/mesh_envelope.dart';

/// Streams the live, decrypted positions of every member of a party.
///
/// Flow: derive the group key → seed from existing rows → subscribe to Supabase
/// Realtime on `location_updates` (filtered to this party) → decrypt each
/// incoming blob client-side → emit the merged roster. The server only ever
/// relays ciphertext; decryption happens here with the on-device group key.
///
/// Phase 8c: also subscribe to the mesh bridge's inbound stream and ingest
/// position envelopes the same way. The `user_id` baked into the encrypted
/// payload by [LocationPublisher] is what lets a mesh-only fix know which
/// member it belongs to (mesh frames don't carry Supabase user ids).
class PartyLiveService {
  PartyLiveService(this._client, this._crypto, this._session, this._bridge);

  final SupabaseClient _client;
  final CryptoService _crypto;
  final CryptoSession _session;
  final MeshBridge _bridge;

  Stream<List<MemberPosition>> watch(String partyId) {
    final controller = StreamController<List<MemberPosition>>();
    final positions = <String, MemberPosition>{};
    final meta = <String, ({String callsign, String color})>{};
    final selfId = _client.auth.currentUser?.id;
    final partyHash = MeshEnvelope.hashParty(partyId);
    SecretKey? groupKey;
    RealtimeChannel? channel;
    Timer? staleTicker;
    StreamSubscription<InboundMeshEvent>? meshSub;

    void emit() {
      if (controller.isClosed) return;
      final list = positions.values.toList()
        ..sort((a, b) => a.callsign.compareTo(b.callsign));
      controller.add(list);
    }

    /// Pull a single member's callsign + color from Supabase and merge
    /// into the local meta map. Called the first time we see a position
    /// from an unrecognised user_id — fixes the "??" callsign bug that
    /// happens when a member joins the party after we've initialised.
    Future<void> hydrateMember(String userId) async {
      if (meta.containsKey(userId)) return;
      try {
        final row = await _client
            .from('party_members')
            .select('callsign,color')
            .eq('party_id', partyId)
            .eq('user_id', userId)
            .maybeSingle();
        if (row != null) {
          meta[userId] = (
            callsign: (row['callsign'] as String?) ?? '??',
            color: (row['color'] as String?) ?? '#C19A6B',
          );
        }
      } catch (_) {/* network out — keep '??' until next refresh */}
    }

    Future<void> _absorb({
      required EncryptedPayload payload,
      required DateTime fallbackTs,
      String? rowUserId,
    }) async {
      final key = groupKey;
      if (key == null) return;
      try {
        final data = await _crypto.decryptJson(
            payload: payload, groupKey: key);
        // user_id can come from the row (Supabase) or from inside the
        // payload (mesh path). Trust the row's value when present.
        final uid = rowUserId ?? data['user_id'] as String?;
        if (uid == null) return;
        if (!meta.containsKey(uid)) await hydrateMember(uid);
        final m = meta[uid];
        final tsRaw = data['ts'] as String?;
        final ts = tsRaw != null
            ? (DateTime.tryParse(tsRaw)?.toUtc() ?? fallbackTs)
            : fallbackTs;
        // Drop strictly-older fixes — could happen when the same packet
        // arrives via both transports out of order.
        final existing = positions[uid];
        if (existing != null && existing.updatedAt.isAfter(ts)) return;
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
          accuracy: (data['accuracy'] as num?)?.toDouble(),
          altitude: (data['altitude'] as num?)?.toDouble(),
          updatedAt: ts,
          isSelf: uid == selfId,
        );
        emit();
      } catch (_) {
        // Undecryptable (no key / tampered / wrong party) — ignore rather
        // than crash. Common when scanning a noisy mesh channel.
      }
    }

    Future<void> ingestSupabaseRow(Map<String, dynamic> row) async {
      final uid = row['user_id'] as String?;
      final wire = row['encrypted_payload'] as String?;
      if (uid == null || wire == null) return;
      await _absorb(
        payload: EncryptedPayload.fromWire(wire),
        rowUserId: uid,
        fallbackTs: DateTime.now().toUtc(),
      );
    }

    Future<void> ingestMeshEvent(InboundMeshEvent ev) async {
      if (ev.type != MeshMsgType.position) return;
      if (ev.partyIdHash.length != partyHash.length) return;
      for (var i = 0; i < partyHash.length; i++) {
        if (ev.partyIdHash[i] != partyHash[i]) return;
      }
      await _absorb(
        payload: EncryptedPayload.fromBytes(ev.ciphertext),
        fallbackTs: DateTime.fromMillisecondsSinceEpoch(ev.timestampMs).toUtc(),
      );
    }

    Future<void> init() async {
      groupKey = await _session.groupKey(partyId);

      final members = await _client
          .from('party_members')
          .select('user_id,callsign,color')
          .eq('party_id', partyId);
      for (final m in (members as List)) {
        meta[m['user_id'] as String] = (
          callsign: m['callsign'] as String,
          color: m['color'] as String? ?? '#C19A6B',
        );
      }

      final rows = await _client
          .from('location_updates')
          .select()
          .eq('party_id', partyId);
      for (final r in (rows as List)) {
        await ingestSupabaseRow(Map<String, dynamic>.from(r as Map));
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
                ingestSupabaseRow(Map<String, dynamic>.from(payload.newRecord));
              }
            },
          )
          // Live party_members → late joiners get their callsign filled in
          // the moment they appear. Fixes the "??" bug for members who
          // joined after we started watching.
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'party_members',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'party_id',
              value: partyId,
            ),
            callback: (payload) {
              final row = payload.newRecord;
              final uid = row['user_id'] as String?;
              if (uid == null) return;
              meta[uid] = (
                callsign: (row['callsign'] as String?) ?? '??',
                color: (row['color'] as String?) ?? '#C19A6B',
              );
              // Rebuild any cached MemberPosition that was using '??'.
              final stale = positions[uid];
              if (stale != null && stale.callsign == '??') {
                positions[uid] = MemberPosition(
                  userId: stale.userId,
                  callsign: meta[uid]!.callsign,
                  color: meta[uid]!.color,
                  location: stale.location,
                  speed: stale.speed,
                  heading: stale.heading,
                  accuracy: stale.accuracy,
                  altitude: stale.altitude,
                  updatedAt: stale.updatedAt,
                  isSelf: stale.isSelf,
                );
              }
              emit();
            },
          )
          .subscribe();

      // Mesh inbound — runs in parallel with Supabase Realtime.
      meshSub = _bridge.inbound.listen(ingestMeshEvent);

      // Re-emit periodically so "last seen" / stale styling stays current.
      staleTicker = Timer.periodic(const Duration(seconds: 20), (_) => emit());
      emit();
    }

    controller.onListen = init;
    controller.onCancel = () async {
      staleTicker?.cancel();
      await meshSub?.cancel();
      final ch = channel;
      if (ch != null) await _client.removeChannel(ch);
      if (!controller.isClosed) await controller.close();
    };
    return controller.stream;
  }
}
