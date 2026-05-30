import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/encrypted_payload.dart';
import '../models/route_waypoint.dart';
import 'crypto_session.dart';

/// Create / stream / delete encrypted waypoints attached to shared routes.
/// Same zero-knowledge pattern as routes: payload `{name, icon, lat, lng, note?}`
/// is sealed under the party's group key before the row hits the server.
class RouteWaypointService {
  RouteWaypointService(this._client, this._crypto, this._session);

  final SupabaseClient _client;
  final CryptoService _crypto;
  final CryptoSession _session;

  Future<void> create({
    required String partyId,
    required String routeId,
    required String name,
    required RouteWaypointIcon icon,
    required LatLng location,
    String? note,
  }) async {
    final key = await _session.groupKey(partyId);
    if (key == null) throw StateError('No encryption key for this party');
    final payload = await _crypto.encryptJson(groupKey: key, data: {
      'name': name,
      'icon': icon.id,
      'lat': location.latitude,
      'lng': location.longitude,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    await _client.from('route_waypoints').insert({
      'party_id': partyId,
      'route_id': routeId,
      'user_id': _client.auth.currentUser!.id,
      'encrypted_payload': payload.toWire(),
    });
  }

  Future<void> delete(String waypointId) =>
      _client.from('route_waypoints').delete().eq('id', waypointId);

  /// Stream all waypoints for any route in the given party (so a single
  /// subscription drives every route's waypoint markers).
  Stream<List<RouteWaypoint>> watch(String partyId) {
    final controller = StreamController<List<RouteWaypoint>>();
    final byId = <String, RouteWaypoint>{};
    final selfId = _client.auth.currentUser?.id;
    SecretKey? key;
    RealtimeChannel? channel;

    void emit() {
      if (controller.isClosed) return;
      controller.add(byId.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
    }

    Future<void> ingest(Map<String, dynamic> row) async {
      final k = key;
      if (k == null) return;
      final id = row['id'] as String?;
      final wire = row['encrypted_payload'] as String?;
      final routeId = row['route_id'] as String?;
      if (id == null || wire == null || routeId == null) return;
      try {
        final data = await _crypto.decryptJson(
            payload: EncryptedPayload.fromWire(wire), groupKey: k);
        byId[id] = RouteWaypoint(
          id: id,
          routeId: routeId,
          userId: row['user_id'] as String? ?? '',
          name: data['name'] as String? ?? 'Waypoint',
          icon: RouteWaypointIcon.fromId(data['icon'] as String? ?? 'flag'),
          location: LatLng(
            (data['lat'] as num).toDouble(),
            (data['lng'] as num).toDouble(),
          ),
          note: data['note'] as String?,
          createdAt:
              DateTime.tryParse(row['created_at'] as String? ?? '')?.toUtc() ??
                  DateTime.now().toUtc(),
          mine: (row['user_id'] as String?) == selfId,
        );
        emit();
      } catch (_) {/* undecryptable */}
    }

    Future<void> init() async {
      key = await _session.groupKey(partyId);
      final rows = await _client
          .from('route_waypoints')
          .select()
          .eq('party_id', partyId);
      for (final r in (rows as List)) {
        await ingest(Map<String, dynamic>.from(r as Map));
      }
      channel = _client.channel('party-route-waypoints-$partyId');
      channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'route_waypoints',
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
            table: 'route_waypoints',
            callback: (payload) {
              final id = payload.oldRecord['id'] as String?;
              if (id != null && byId.remove(id) != null) emit();
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
