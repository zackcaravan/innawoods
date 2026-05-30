import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/models/chat_message.dart';
import '../../../shared/models/map_pin.dart';
import '../../../shared/models/map_route.dart';
import '../../../shared/models/route_waypoint.dart';
import '../../../shared/models/member_position.dart';
import '../../../shared/models/party.dart';
import '../../../shared/models/party_member.dart';
import '../../../shared/services/crypto_session.dart';
import '../../../shared/services/geocoder_service.dart';
import '../../../shared/services/gpx_service.dart';
import '../../../shared/services/location_publisher.dart';
import '../../../shared/services/party_live_service.dart';
import '../../../shared/services/party_secret_store.dart';
import '../../../shared/services/chat_service.dart';
import '../../../shared/services/party_service.dart';
import '../../../shared/services/pin_service.dart';
import '../../../shared/services/route_service.dart';
import '../../../shared/services/route_waypoint_service.dart';
import '../../../shared/services/routing_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../settings/providers/settings_provider.dart';

part 'party_provider.g.dart';

@riverpod
PartySecretStore partySecretStore(Ref ref) => PartySecretStore();

@riverpod
CryptoSession cryptoSession(Ref ref) => CryptoSession(
      ref.watch(cryptoServiceProvider),
      ref.watch(partySecretStoreProvider),
    );

@riverpod
PartyService partyService(Ref ref) => PartyService(
      ref.watch(supabaseClientProvider),
      ref.watch(cryptoServiceProvider),
      ref.watch(partySecretStoreProvider),
      ref.watch(cryptoSessionProvider),
    );

/// Parties the current user belongs to (newest first).
@riverpod
Future<List<Party>> myParties(Ref ref) =>
    ref.watch(partyServiceProvider).myParties();

/// Live-ish roster for a party. Refresh-on-demand for now; Phase 3 wires
/// realtime so the roster and dots update without a manual refresh.
@riverpod
Future<List<PartyMember>> partyMembers(Ref ref, String partyId) =>
    ref.watch(partyServiceProvider).members(partyId);

@riverpod
Future<Party?> partyById(Ref ref, String partyId) =>
    ref.watch(partyServiceProvider).party(partyId);

@riverpod
LocationPublisher locationPublisher(Ref ref) => LocationPublisher(
      ref.watch(supabaseClientProvider),
      ref.watch(cryptoServiceProvider),
    );

@riverpod
PartyLiveService partyLiveService(Ref ref) => PartyLiveService(
      ref.watch(supabaseClientProvider),
      ref.watch(cryptoServiceProvider),
      ref.watch(cryptoSessionProvider),
    );

/// Live decrypted member positions for a party (realtime).
@riverpod
Stream<List<MemberPosition>> partyLive(Ref ref, String partyId) =>
    ref.watch(partyLiveServiceProvider).watch(partyId);

@riverpod
GpxService gpxService(Ref ref) => GpxService();

@riverpod
GeocoderService geocoderService(Ref ref) => GeocoderService();

@riverpod
RoutingService routingService(Ref ref) => RoutingService();

@riverpod
PinService pinService(Ref ref) => PinService(
      ref.watch(supabaseClientProvider),
      ref.watch(cryptoServiceProvider),
      ref.watch(cryptoSessionProvider),
    );

/// Live decrypted pins for a party (realtime).
@riverpod
Stream<List<MapPin>> partyPins(Ref ref, String partyId) =>
    ref.watch(pinServiceProvider).watch(partyId);

@riverpod
RouteService routeService(Ref ref) => RouteService(
      ref.watch(supabaseClientProvider),
      ref.watch(cryptoServiceProvider),
      ref.watch(cryptoSessionProvider),
    );

/// Live decrypted shared routes for a party (realtime).
@riverpod
Stream<List<MapRoute>> partyRoutes(Ref ref, String partyId) =>
    ref.watch(routeServiceProvider).watch(partyId);

@riverpod
RouteWaypointService routeWaypointService(Ref ref) => RouteWaypointService(
      ref.watch(supabaseClientProvider),
      ref.watch(cryptoServiceProvider),
      ref.watch(cryptoSessionProvider),
    );

/// Live decrypted waypoints (across all routes) for a party.
@riverpod
Stream<List<RouteWaypoint>> partyRouteWaypoints(Ref ref, String partyId) =>
    ref.watch(routeWaypointServiceProvider).watch(partyId);

@riverpod
ChatService chatService(Ref ref) => ChatService(
      ref.watch(supabaseClientProvider),
      ref.watch(cryptoServiceProvider),
      ref.watch(cryptoSessionProvider),
    );

/// Live decrypted chat for a party (realtime).
@riverpod
Stream<List<ChatMessage>> partyMessages(Ref ref, String partyId) =>
    ref.watch(chatServiceProvider).watch(partyId);

/// Controls whether this device is broadcasting its own (encrypted) location to
/// a party. The map screen turns this on while it's open. Publishes on the
/// user-configured interval (default 30 s, up to 5 min) to save battery.
@riverpod
class LocationSharing extends _$LocationSharing {
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    return false;
  }

  /// Returns false if permission/services unavailable or no key for the party.
  Future<bool> start(String partyId) async {
    final publisher = ref.read(locationPublisherProvider);
    if (!await publisher.ensurePermission()) return false;
    final key = await ref.read(cryptoSessionProvider).groupKey(partyId);
    if (key == null) return false;
    final uid = ref.read(supabaseClientProvider).auth.currentUser!.id;
    final settings = await ref.read(settingsControllerProvider.future);

    Future<void> tick() async {
      final pos = await publisher.current();
      if (pos != null) {
        await publisher.publish(
            partyId: partyId, userId: uid, groupKey: key, position: pos);
      }
    }

    _timer?.cancel();
    await tick(); // publish immediately, then on the interval
    _timer = Timer.periodic(
      Duration(seconds: settings.effectiveLocationIntervalSeconds),
      (_) => tick(),
    );
    state = true;
    return true;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    state = false;
  }
}
