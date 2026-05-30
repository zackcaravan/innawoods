import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/encrypted_payload.dart';
import '../models/map_route.dart';
import 'crypto_session.dart';

/// Create / stream / delete encrypted shared routes (same zero-knowledge
/// pattern as pins; the whole route — name + every point — is sealed).
class RouteService {
  RouteService(this._client, this._crypto, this._session);

  final SupabaseClient _client;
  final CryptoService _crypto;
  final CryptoSession _session;

  Future<void> create({
    required String partyId,
    required String name,
    required List<LatLng> points,
    String? color,
  }) async {
    final key = await _session.groupKey(partyId);
    if (key == null) throw StateError('No encryption key for this party');
    final payload = await _crypto.encryptJson(groupKey: key, data: {
      'name': name,
      'points': [
        for (final p in points) [p.latitude, p.longitude],
      ],
      // ignore: use_null_aware_elements
      if (color != null) 'color': color,
    });
    await _client.from('routes').insert({
      'party_id': partyId,
      'user_id': _client.auth.currentUser!.id,
      'encrypted_payload': payload.toWire(),
    });
  }

  /// Re-encrypt the route with updated mutable fields (name/color/points).
  /// The DB row is a single encrypted blob, so any change rewrites the whole
  /// payload. Points default to existing if not provided.
  Future<void> update({
    required String partyId,
    required MapRoute route,
    String? name,
    String? color,
    List<LatLng>? points,
  }) async {
    final key = await _session.groupKey(partyId);
    if (key == null) throw StateError('No encryption key for this party');
    final pts = points ?? route.points;
    final payload = await _crypto.encryptJson(groupKey: key, data: {
      'name': name ?? route.name,
      'points': [
        for (final p in pts) [p.latitude, p.longitude],
      ],
      if ((color ?? route.color) != null) 'color': color ?? route.color,
    });
    await _client
        .from('routes')
        .update({'encrypted_payload': payload.toWire()})
        .eq('id', route.id);
  }

  Future<void> delete(String routeId) =>
      _client.from('routes').delete().eq('id', routeId);

  Stream<List<MapRoute>> watch(String partyId) {
    final controller = StreamController<List<MapRoute>>();
    final routes = <String, MapRoute>{};
    final selfId = _client.auth.currentUser?.id;
    SecretKey? key;
    RealtimeChannel? channel;

    void emit() {
      if (controller.isClosed) return;
      controller.add(routes.values.toList()
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
        final pts = (data['points'] as List)
            .map((e) => LatLng(
                  (e[0] as num).toDouble(),
                  (e[1] as num).toDouble(),
                ))
            .toList();
        routes[id] = MapRoute(
          id: id,
          userId: row['user_id'] as String? ?? '',
          name: data['name'] as String? ?? 'Route',
          points: pts,
          createdAt:
              DateTime.tryParse(row['created_at'] as String? ?? '')?.toUtc() ??
                  DateTime.now().toUtc(),
          mine: (row['user_id'] as String?) == selfId,
          color: data['color'] as String?,
        );
        emit();
      } catch (_) {/* undecryptable — skip */}
    }

    Future<void> init() async {
      key = await _session.groupKey(partyId);
      final rows =
          await _client.from('routes').select().eq('party_id', partyId);
      for (final r in (rows as List)) {
        await ingest(Map<String, dynamic>.from(r as Map));
      }
      channel = _client.channel('party-routes-$partyId');
      channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'routes',
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
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'routes',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'party_id',
                value: partyId),
            callback: (payload) {
              if (payload.newRecord.isNotEmpty) {
                // Re-decrypt + replace the cached entry so name/color edits
                // ripple to the map without a back-and-re-enter.
                ingest(Map<String, dynamic>.from(payload.newRecord));
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'routes',
            callback: (payload) {
              final id = payload.oldRecord['id'] as String?;
              if (id != null && routes.remove(id) != null) emit();
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
