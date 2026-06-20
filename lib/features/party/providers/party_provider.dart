// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
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
import '../../../shared/services/photo_store.dart';
import '../../../shared/services/route_service.dart';
import '../../../shared/services/route_waypoint_service.dart';
import '../../../shared/services/routing_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../mesh/providers/mesh_provider.dart';
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
      ref.watch(meshBridgeProvider),
    );

@riverpod
PartyLiveService partyLiveService(Ref ref) => PartyLiveService(
      ref.watch(supabaseClientProvider),
      ref.watch(cryptoServiceProvider),
      ref.watch(cryptoSessionProvider),
      ref.watch(meshBridgeProvider),
      ref.watch(selfPositionProvider.stream),
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

@Riverpod(keepAlive: true)
PhotoStore photoStore(Ref ref) => PhotoStore();

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
      ref.watch(meshBridgeProvider),
    );

/// Live decrypted chat for a party (realtime).
@riverpod
Stream<List<ChatMessage>> partyMessages(Ref ref, String partyId) =>
    ref.watch(chatServiceProvider).watch(partyId);

/// Live continuous GPS stream for THIS device. Powers the local UI (camera
/// follow, heading-up auto-mode, instant self-dot updates) without waiting
/// on the Supabase round-trip. Survives screen reloads via keepAlive.
///
/// Uses `getPositionStream` with a 5 m distanceFilter — the OS will only
/// wake the listener when the user actually moves that far, which keeps
/// battery sane while still feeling responsive at a walking pace (5 m at
/// 4 mph ≈ a fresh fix every 2.8 s).
@Riverpod(keepAlive: true)
Stream<Position> selfPosition(Ref ref) async* {
  final publisher = ref.read(locationPublisherProvider);
  if (!await publisher.ensurePermission()) return;
  // Power profile derives from trip mode. Trip mode trades GPS responsiveness
  // for battery — lower fix accuracy (medium ≈ ~50 m vs high's ~5 m) lets
  // the chip use cell+wifi triangulation more aggressively, and a wider
  // distanceFilter throttles how often the stream wakes us up at all. At
  // hiking pace (4 mph) the user covers 20 m in ~11 s, so a fresh fix every
  // ~10 s is still plenty for the live-map dot to feel alive without burning
  // GPS through the day. Default profile is unchanged for backwards compat
  // with the responsiveness the original screen-on UX assumed.
  final settings = await ref.read(settingsControllerProvider.future);
  final accuracy = settings.tripMode
      ? LocationAccuracy.medium
      : LocationAccuracy.high;
  final filterM = settings.tripMode ? 20 : 5;

  // On Android, AndroidSettings.foregroundNotificationConfig spawns a
  // foreground service so the stream keeps emitting fixes when the screen
  // is off — without this, Android Doze kills location updates after a
  // few minutes and party members see each other go stale. iOS handles
  // background location via UIBackgroundModes + the system's significant
  // location service, no equivalent config needed in code.
  final LocationSettings locSettings;
  if (Platform.isAndroid) {
    locSettings = AndroidSettings(
      accuracy: accuracy,
      distanceFilter: filterM,
      // Use the foreground service so background fixes keep flowing
      // regardless of Doze / battery optimisations. The persistent
      // notification is the contract Android requires for that privilege.
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Sharing with your crew',
        notificationText:
            'Innawoods is broadcasting your encrypted position. '
            'Tap to open. Leave the party to stop.',
        notificationIcon:
            AndroidResource(name: 'launch_background', defType: 'drawable'),
        // setOngoing: true → user can't swipe-dismiss; matches "this is
        // genuinely about active sharing, not a background daemon."
        setOngoing: true,
        // Keep the service running across device sleep (Doze whitelisted).
        enableWakeLock: true,
      ),
    );
  } else if (Platform.isIOS) {
    locSettings = AppleSettings(
      accuracy: accuracy,
      distanceFilter: filterM,
      // Required so iOS keeps emitting fixes when the app is backgrounded.
      // Pairs with UIBackgroundModes=location in Info.plist (already set).
      allowBackgroundLocationUpdates: true,
      // showBackgroundLocationIndicator: true draws the blue pulsing bar
      // at the top of the screen — honest signal to the user that we're
      // actively reading their location while they're in another app.
      showBackgroundLocationIndicator: true,
      pauseLocationUpdatesAutomatically: false,
      activityType: ActivityType.fitness,
    );
  } else {
    locSettings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: filterM,
    );
  }
  yield* Geolocator.getPositionStream(locationSettings: locSettings);
}

/// Controls whether this device is broadcasting its own (encrypted) location
/// to a party. The map screen turns this on while it's open.
///
/// Previously this polled `getCurrentPosition` on a 30 s timer, which makes
/// the dot feel frozen between fixes even at a brisk walk (54 m gap per
/// tick). Now we subscribe to [selfPositionProvider] and throttle the
/// Supabase publish to no faster than the user's configured interval (still
/// 30 s default, up to 5 min) — so the local UI is smooth but server load /
/// battery cost match the old behaviour.
@riverpod
class LocationSharing extends _$LocationSharing {
  StreamSubscription<Position>? _sub;
  DateTime? _lastPublishAt;

  @override
  bool build() {
    ref.onDispose(() => _sub?.cancel());
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
    final interval =
        Duration(seconds: settings.effectiveLocationIntervalSeconds);

    Future<void> doPublish(Position pos) async {
      _lastPublishAt = DateTime.now();
      await publisher.publish(
          partyId: partyId, userId: uid, groupKey: key, position: pos);
    }

    await _sub?.cancel();
    // Seed with a fast one-shot so the dot lands somewhere within ~1 s,
    // even before the stream's distanceFilter has had a chance to fire.
    final first = await publisher.current();
    if (first != null) await doPublish(first);

    _sub = ref.read(selfPositionProvider.stream).listen((pos) async {
      // Server-side throttle: respect the user's battery setting. The local
      // UI gets every fix (separate listener); only Supabase writes are gated.
      final last = _lastPublishAt;
      if (last != null && DateTime.now().difference(last) < interval) return;
      await doPublish(pos);
    });
    state = true;
    return true;
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    state = false;
  }

  /// Public read-through to the publisher's check. Used by the settings
  /// screen to show whether background sharing is already armed.
  Future<bool> hasBackgroundPermission() =>
      ref.read(locationPublisherProvider).hasBackgroundPermission();

  /// Try to upgrade the user from whileInUse → always so position keeps
  /// flowing while the phone is in their pocket. MUST be called only after
  /// the prominent disclosure screen has been shown and accepted (Google
  /// requires it before the OS prompt). Returns the resulting state so the
  /// caller can update UI / show a toast / deep-link to settings.
  Future<BackgroundUpgradeResult> requestBackgroundUpgrade() =>
      ref.read(locationPublisherProvider).requestBackgroundUpgrade();

  /// Opens the OS's app-settings page so the user can manually flip the
  /// background-location permission to "Allow all the time." Needed on
  /// Android 11+ since Google removed the runtime dialog for it.
  Future<bool> openAppSettings() =>
      ref.read(locationPublisherProvider).openAppSettings();
}
