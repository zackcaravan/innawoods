// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/map_pin.dart';
import '../../../shared/models/map_route.dart';
import '../../../shared/models/member_position.dart';
import '../../../shared/models/party.dart';
import '../../../shared/models/place.dart';
import '../../../shared/models/route_waypoint.dart';
import '../../../shared/services/dead_man_monitor.dart';
import '../../../shared/services/map_tile_server.dart';
import '../../../shared/services/settings_store.dart';
import '../../../shared/models/track.dart';
import '../../../shared/services/coord_format.dart';
import '../../../shared/services/dem_sampler.dart';
import '../../../shared/services/track_recorder.dart';
import '../../auth/providers/auth_provider.dart';
import '../../maps/providers/maps_provider.dart';
import '../../party/providers/party_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../mesh/providers/mesh_provider.dart';
import '../../party/widgets/invite_qr_dialog.dart';
import '../../tracks/providers/tracks_provider.dart';
import '../../../core/errors/user_error.dart';
import '../../../shared/services/mesh/mesh_radio.dart';

/// The party map — MapLibre 3D vector engine + the full encrypted party layer
/// and all interactions. This replaces the old flutter_map party screen.
class PartyMap3dScreen extends ConsumerStatefulWidget {
  const PartyMap3dScreen({super.key, required this.partyId});
  final String partyId;

  @override
  ConsumerState<PartyMap3dScreen> createState() => _PartyMap3dScreenState();
}

class _PartyMap3dScreenState extends ConsumerState<PartyMap3dScreen> {
  // Built ONCE — recreating this Set on every rebuild resets the WebView's
  // gesture handling and freezes the map after any button press.
  static final Set<Factory<OneSequenceGestureRecognizer>> _mapGestures = {
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  MapTileServer? _server;
  String? _url;
  bool _noRegion = false; // user hasn't downloaded any region yet
  InAppWebViewController? _ctrl;
  // Notifiers/services captured while `ref` is live so dispose AND
  // long-lived listener callbacks (which race with disposal) don't have to
  // touch `ref` — that's what was throwing "Cannot use ref after disposed".
  LocationSharing? _locShare;
  DeadManMonitor? _deadMan;
  AppSettings? _currentSettings; // mirrored from settingsControllerProvider
  bool _ready = false;
  bool _is3d = false; // default 2D (low GL memory); 3D is opt-in
  bool _placingPin = false; // pin FAB → next map tap places the pin
  String? _placingWaypointForRouteId; // != null → next map tap drops a waypoint
  bool _measuring = false; // distance/area measurement mode
  final List<LatLng> _measurePoints = [];

  /// Tells the JS click handler to short-circuit hit-tests and just report
  /// the tap coordinate via `mapTap`. Without this, tapping a route or pin
  /// while in placement mode would re-open its detail drawer instead of
  /// dropping the new pin/waypoint.
  void _pushPlacementMode() {
    final mode = _placingPin
        ? 'pin'
        : (_placingWaypointForRouteId != null
            ? 'waypoint'
            : (_measuring ? 'measure' : 'none'));
    _eval('setPlacementMode(${jsonEncode(mode)})');
  }

  /// Total along-line distance through the current measurement points (meters).
  double get _measureDistanceM {
    if (_measurePoints.length < 2) return 0;
    const d = Distance();
    double total = 0;
    for (var i = 1; i < _measurePoints.length; i++) {
      total += d.as(
          LengthUnit.Meter, _measurePoints[i - 1], _measurePoints[i]);
    }
    return total;
  }

  void _startMeasure() {
    HapticFeedback.selectionClick();
    setState(() {
      _measuring = true;
      _measurePoints.clear();
    });
    _pushPlacementMode();
    _push('setMeasure', _measureGeo());
  }

  void _stopMeasure() {
    setState(() {
      _measuring = false;
      _measurePoints.clear();
    });
    _pushPlacementMode();
    _push('setMeasure', _measureGeo());
  }

  void _addMeasurePoint(LatLng p) {
    HapticFeedback.lightImpact();
    setState(() => _measurePoints.add(p));
    _push('setMeasure', _measureGeo());
  }

  void _undoMeasurePoint() {
    if (_measurePoints.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(_measurePoints.removeLast);
    _push('setMeasure', _measureGeo());
  }

  Map<String, dynamic> _measureGeo() => {
        'type': 'FeatureCollection',
        'features': [
          // Vertex points so the user can see each tap.
          for (final p in _measurePoints)
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [p.longitude, p.latitude],
              },
              'properties': {'kind': 'vertex'},
            },
          if (_measurePoints.length >= 2)
            {
              'type': 'Feature',
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  for (final p in _measurePoints) [p.longitude, p.latitude]
                ],
              },
              'properties': {'kind': 'line'},
            },
        ],
      };
  // Live map camera state — driven by JS `move` events. Lives in a
  // ValueNotifier so the compass FAB + scale bar update without rebuilding
  // the whole screen (which would tank the WebView during easeTo animations).
  final ValueNotifier<_Camera> _camera = ValueNotifier<_Camera>(const _Camera());
  bool _offline = false; // no network → show banner
  StreamSubscription? _netSub;
  // Imagery basemap selection (null = vector). One of:
  //   'sat-esri' (Esri World Imagery) · 'sat-usgs' (USGS aerial) · 'opentopo'.
  String? _imagery;
  // Hybrid view — keep roads+labels over satellite, hide basemap fills.
  bool _hybrid = false;
  // Overlay visibility, persisted in SharedPreferences. Map's JS layer ids.
  final Map<String, bool> _overlays = {
    'usgs-topo': false,
    'overlay-trails': false,
    'blm-sma': false,
    'wildfires': false,
  };

  // Drawing
  bool _drawing = false;
  bool _snap = false;
  bool _snapping = false;
  final List<LatLng> _draft = [];
  final List<List<LatLng>> _segments = [];

  // Freehand draw — when on, the user finger-drags a path over the map
  // instead of tapping points. The overlay disambiguates 1- vs 2-finger
  // touches itself: 1 finger draws, 2 fingers route through to MapLibre as
  // a pan + pinch-zoom + rotate via the panBy / zoomBy / rotateBy JS
  // bridges. Once all fingers lift, the next single-finger touch resumes
  // drawing — you don't have to re-toggle anything.
  bool _freehand = false;
  bool _freehandActive = false;
  final List<Offset> _freehandPts = [];

  /// Live pointer book — local positions keyed by Flutter's pointer id.
  /// Drives the 1-vs-2-finger decision inside the overlay's Listener.
  final Map<int, Offset> _activePtrs = {};

  /// True once the current touch sequence escalated to two fingers. Stays
  /// true until ALL fingers lift, so dropping back to one finger mid-pan
  /// doesn't accidentally start a new freehand stroke under the user.
  bool _gestureIsPan = false;

  /// Snapshot of the two-finger geometry at the start of (and updated
  /// each frame of) a pan/pinch/rotate. We diff against the new geometry
  /// to derive incremental pan / zoom / rotation deltas to send to JS.
  Offset? _twoFingerMid;
  double? _twoFingerDist;
  double? _twoFingerAngle;

  bool _autoCentered = false;
  bool _unread = false;
  int _lastSeenMsgCount = -1;

  /// Follow-mode: when on, every position update slides the camera to the
  /// user's location at the current zoom. Manual map gestures flip it off;
  /// the Recenter FAB flips it back on. See `userPan` JS handler.
  bool _following = true;

  /// Auto-heading-up sticky state — tracks whether the last sustained-speed
  /// decision asked the map to be in heading-up mode, so we don't write the
  /// setting on every fix.
  bool _autoHeadUpActive = false;

  @override
  void initState() {
    super.initState();
    _boot();
    _watchConnectivity();
  }

  Future<void> _watchConnectivity() async {
    final conn = Connectivity();
    final first = await conn.checkConnectivity();
    if (!mounted) return;
    setState(() => _offline = _isOffline(first));
    _netSub = conn.onConnectivityChanged.listen((r) {
      if (!mounted) return;
      setState(() => _offline = _isOffline(r));
    });
  }

  static bool _isOffline(List<ConnectivityResult> r) =>
      r.isEmpty || r.every((x) => x == ConnectivityResult.none);

  static String _overlayKey(String id) => 'innawoods.overlay.$id';
  static const _kImagery = 'innawoods.imagery';
  static const _kHybrid = 'innawoods.hybrid';

  Future<void> _loadOverlayPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final id in _overlays.keys.toList()) {
      _overlays[id] = prefs.getBool(_overlayKey(id)) ?? false;
    }
    _imagery = prefs.getString(_kImagery);
    // Default hybrid ON for new users — satellite without labels reads as a
    // "broken" map (no roads, no town names, no POIs); the previous default
    // of false routinely caught test users out. Explicit user choice still
    // wins on subsequent launches.
    _hybrid = prefs.getBool(_kHybrid) ?? true;
  }

  Future<void> _setOverlay(String id, bool visible) async {
    setState(() => _overlays[id] = visible);
    await _eval('setOverlay(${jsonEncode(id)}, $visible)');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_overlayKey(id), visible);
  }

  Future<void> _setImagery(String? id) async {
    final wasNull = _imagery == null;
    setState(() => _imagery = id);
    await _eval('setImagery(${id == null ? 'null' : jsonEncode(id)})');
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kImagery);
    } else {
      await prefs.setString(_kImagery, id);
      // Going from "no imagery" to "some imagery" auto-enables hybrid so the
      // satellite isn't a barren imagery dump (no labels, no road names).
      // We don't touch hybrid on imagery-to-imagery switches because the
      // user has already made their preference clear by that point.
      if (wasNull && !_hybrid) {
        await _setHybrid(true);
      }
    }
  }

  Future<void> _setHybrid(bool on) async {
    setState(() => _hybrid = on);
    await _eval('setHybrid($on)');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHybrid, on);
  }

  void _pushOverlays() {
    for (final entry in _overlays.entries) {
      if (entry.value) {
        _eval('setOverlay(${jsonEncode(entry.key)}, true)');
      }
    }
    if (_imagery != null) {
      _eval('setImagery(${jsonEncode(_imagery)})');
    }
    if (_hybrid) _eval('setHybrid(true)');
    if (_currentSettings?.offRoadStyle == true) {
      _eval('setOffRoadStyle(true)');
    }
    if (_currentSettings?.tripMode == true) {
      // Trip mode persists across screen restarts — re-apply the GPU-cost
      // suppression on every map open so the user doesn't have to toggle
      // trip-mode off-and-on to get the hillshade hidden again.
      _eval('setHillshade(false)');
    }
    _pushActivityFilter();
  }

  /// Push the user's trail-style filter (all / hike / orv) to the map. The JS
  /// side toggles layer visibility on the split `roads_hike` / `roads_orv`
  /// layers — major roads, bridges, tunnels stay visible regardless.
  void _pushActivityFilter() {
    if (!_ready) return;
    final a = _currentSettings?.mapActivity ?? MapActivity.all;
    _eval('setActivityFilter(${jsonEncode(a.id)})');
  }

  Future<void> _boot() async {
    await _loadOverlayPrefs();
    if (!mounted) return;
    final activeId = await ref.read(regionStoreProvider).activeId();
    if (!mounted) return;
    if (activeId == null) {
      setState(() => _noRegion = true);
      return;
    }
    final pmtilesPath = await ref.read(regionStoreProvider).pathFor(activeId);
    if (!mounted) return;
    // DEM cache lives under the app's private support dir so it survives
    // re-launches and isn't user-visible. Lets the hillshade keep rendering
    // offline after the user has panned around with internet at least once,
    // or after they've explicitly pre-downloaded terrain for the region.
    final supportDir = await getApplicationSupportDirectory();
    final demCacheDir = Directory(
        '${supportDir.path}${Platform.pathSeparator}dem_cache');
    if (!mounted) return;
    final server = MapTileServer(pmtilesPath, demCacheDir: demCacheDir);
    final port = await server.start();
    if (!mounted) return;
    setState(() {
      _server = server;
      _url = 'http://127.0.0.1:$port/map.html';
    });
    _locShare = ref.read(locationSharingProvider.notifier);
    _deadMan = ref.read(deadManMonitorProvider);
    _currentSettings = ref.read(settingsControllerProvider).valueOrNull;
    _locShare!.start(widget.partyId);
  }

  @override
  void dispose() {
    _netSub?.cancel();
    _camera.dispose();
    _locShare?.stop();
    // Tear the WebView's GL context down deterministically — otherwise the old
    // (heavy) renderer lingers while re-entry spins up a new one, and the phone
    // hands back a black surface. dispose() the controller, then the server.
    _ctrl?.dispose();
    _ctrl = null;
    _server?.stop();
    super.dispose();
  }

  // ---- JS bridge ----------------------------------------------------------
  /// Guarded JS eval — never throws if the WebView is gone/unready (e.g. its
  /// renderer was killed). Returns the JS result string, or null.
  Future<String?> _eval(String source) async {
    if (_ctrl == null || !mounted) return null;
    try {
      final r = await _ctrl!.evaluateJavascript(source: source);
      return r?.toString();
    } catch (_) {
      return null; // renderer gone / not attached yet
    }
  }

  Future<void> _push(String fn, Object data) async {
    if (!_ready) return;
    await _eval('$fn(${jsonEncode(data)})');
  }

  /// Fly the camera to a single point (used by drawer pin taps + the search
  /// result list). Picks a moderate zoom so the user sees context, not a
  /// pixel-sniff close-up.
  Future<void> _flyToPoint(LatLng pt, {double zoom = 14}) =>
      _eval('flyTo(${pt.longitude},${pt.latitude},$zoom)');

  /// Frame an entire route in the viewport (used by drawer route taps).
  /// Falls back to flyToPoint for trivially short routes.
  Future<void> _flyToRoute(MapRoute r) async {
    if (r.points.isEmpty) return;
    if (r.points.length == 1) return _flyToPoint(r.points.first);
    var minLng = r.points.first.longitude;
    var maxLng = minLng;
    var minLat = r.points.first.latitude;
    var maxLat = minLat;
    for (final p in r.points) {
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
    }
    await _eval('fitBounds($minLng, $minLat, $maxLng, $maxLat)');
  }

  void _pushAll() {
    if (!mounted) return;
    _push('setMembers', _membersGeo(_members));
    _push('setPins', _pinsGeo(_pins));
    _push('setRoutes', _routesGeo(_routes));
    _push('setRouteWaypoints', _waypointsGeo(_waypoints));
    _pushOverlays();
    _pushMaxBounds();
  }

  /// Clamp panning to the active region's bbox plus a small buffer so the
  /// user can't silently wander into ungloaded continents (which would
  /// trigger live DEM streaming and drain battery for terrain they have no
  /// vector data behind). 0.5° on each side ≈ 35-55 km depending on
  /// latitude — enough breathing room for trails that cross state lines,
  /// not enough to download Idaho by accident.
  void _pushMaxBounds() {
    if (!_ready) return;
    final activeId = ref.read(activeRegionProvider).valueOrNull;
    if (activeId == null) {
      _eval('clearMaxBounds()');
      return;
    }
    final region = ref.read(regionCatalogProvider).byId(activeId);
    if (region == null) {
      _eval('clearMaxBounds()');
      return;
    }
    const buf = 0.5;
    final b = region.bbox;
    _eval('setMaxBounds(${b[0] - buf}, ${b[1] - buf}, '
        '${b[2] + buf}, ${b[3] + buf})');
  }

  List<MemberPosition> get _members =>
      ref.read(partyLiveProvider(widget.partyId)).valueOrNull ?? const [];
  List<MapPin> get _pins =>
      ref.read(partyPinsProvider(widget.partyId)).valueOrNull ?? const [];
  List<MapRoute> get _routes =>
      ref.read(partyRoutesProvider(widget.partyId)).valueOrNull ?? const [];
  List<RouteWaypoint> get _waypoints =>
      ref.read(partyRouteWaypointsProvider(widget.partyId)).valueOrNull ??
      const [];

  Map<String, dynamic> _membersGeo(List<MemberPosition> m) => {
        'type': 'FeatureCollection',
        'features': [
          for (final x in m)
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [x.location.longitude, x.location.latitude]
              },
              'properties': {
                'id': x.userId,
                'callsign': x.callsign,
                'color': x.isStale ? '#9e9e9e' : x.color,
                'self': x.isSelf,
                'heading': x.heading ?? -1, // -1 = no heading (no arrow)
                'hasHeading': x.heading != null && x.heading! >= 0,
              },
            }
        ],
      };

  Map<String, dynamic> _pinsGeo(List<MapPin> pins) => {
        'type': 'FeatureCollection',
        'features': [
          for (final pin in pins)
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [pin.location.longitude, pin.location.latitude]
              },
              'properties': {'id': pin.id, 'name': pin.name, 'type': pin.type},
            }
        ],
      };

  Map<String, dynamic> _waypointsGeo(List<RouteWaypoint> wps) => {
        'type': 'FeatureCollection',
        'features': [
          for (final w in wps)
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [w.location.longitude, w.location.latitude],
              },
              'properties': {
                'id': w.id,
                'name': w.name,
                'icon': w.icon.emoji,
                'routeId': w.routeId,
              },
            }
        ],
      };

  Map<String, dynamic> _trackGeo(List<TrackPoint> points) => {
        'type': 'FeatureCollection',
        'features': points.length < 2
            ? const <Map<String, dynamic>>[]
            : [
                {
                  'type': 'Feature',
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [
                      for (final p in points) [p.lng, p.lat]
                    ],
                  },
                  'properties': const <String, dynamic>{},
                },
              ],
      };

  Map<String, dynamic> _routesGeo(List<MapRoute> routes) => {
        'type': 'FeatureCollection',
        'features': [
          for (final r in routes)
            {
              'type': 'Feature',
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  for (final pt in r.points) [pt.longitude, pt.latitude]
                ]
              },
              'properties': {
                'id': r.id,
                'name': r.name,
                if (r.color != null) 'color': r.color,
              },
            }
        ],
      };

  void _onMapTap(String json) {
    if (!mounted) return;
    final m = jsonDecode(json) as Map<String, dynamic>;
    final point =
        LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
    if (_placingWaypointForRouteId != null) {
      final routeId = _placingWaypointForRouteId!;
      setState(() => _placingWaypointForRouteId = null);
      _pushPlacementMode();
      _dropWaypointAt(routeId, point);
      return;
    }
    if (_placingPin) {
      setState(() => _placingPin = false);
      _pushPlacementMode();
      _dropPinAt(point);
      return;
    }
    if (_measuring) {
      _addMeasurePoint(point);
      return;
    }
    if (_drawing) _addDrawPoint(point);
  }

  /// Tap on a rendered trail / minor road → pop the info sheet. Payload from
  /// map.html carries the OSM-derived properties (name, kind, surface, …)
  /// plus the rendered LineString coords so we can sample elevation and —
  /// in route-designer mode — splice the trail into the active draft.
  Future<void> _onTrailTap(String json) async {
    if (!mounted) return;
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return; // malformed payload, ignore
    }
    final coordsRaw = (m['coords'] as List?) ?? const [];
    final coords = <LatLng>[
      for (final c in coordsRaw)
        if (c is List && c.length >= 2)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
    final info = _TrailHitInfo(
      tap: LatLng((m['tapLat'] as num).toDouble(),
          (m['tapLng'] as num).toDouble()),
      name: ((m['name'] as String?) ?? '').trim(),
      kind: ((m['kind'] as String?) ?? '').trim(),
      kindDetail: ((m['kindDetail'] as String?) ?? '').trim(),
      surface: ((m['surface'] as String?) ?? '').trim(),
      coords: coords,
    );
    final baseUrl = (_url ?? '').replaceFirst('/map.html', '');
    // Highlight the tapped segment so the user can see what they'd be
    // adding. Cleared on sheet close regardless of which button (if any)
    // they chose. Pre-fly: highlight is just the segment under their
    // finger. If they hit "Add whole" we re-highlight the full chain
    // before committing so they get a visual moment of "yep, that's it."
    _eval('setHighlightTrail(${jsonEncode(_lineStringGeo(coords))})');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.surfaceGrey,
      builder: (_) => _TrailInfoSheet(
        info: info,
        baseUrl: baseUrl,
        canAddToRoute: _drawing && coords.length >= 2,
        onAddToRoute: () {
          Navigator.of(context).pop();
          _appendTrailToDraft(coords);
        },
        // "Add whole trail" is offered only when we have an OSM name to
        // stitch by. queryTrailByName + assembly happens on demand so we
        // don't pre-compute a chain the user may not want. If the chain
        // assembled to the same length as the tapped segment, we surface
        // that — it's a useful signal that there are no other named
        // segments visible (zoom out or pan around to find more).
        onAddWholeTrail: info.name.isEmpty
            ? null
            : () async {
                final whole = await _assembleNamedTrail(info.name, info.tap);
                if (!mounted) return;
                Navigator.of(context).pop();
                if (whole == null || whole.length <= coords.length + 1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Only one segment of "${info.name}" is in '
                          'loaded tiles. Pan along the trail to load '
                          'more, then try again.'),
                    ),
                  );
                  _appendTrailToDraft(whole ?? coords);
                  return;
                }
                _eval('setHighlightTrail(${jsonEncode(_lineStringGeo(whole))})');
                _appendTrailToDraft(whole);
              },
      ),
    );
    // Sheet dismissed (any path: button, scrim tap, system back). Drop the
    // highlight so the bright cyan doesn't linger on the map.
    if (mounted) _eval('clearHighlightTrail()');
  }

  /// FeatureCollection wrapper around a single LineString — same shape
  /// the JS-side `setHighlightTrail` source expects.
  Map<String, dynamic> _lineStringGeo(List<LatLng> coords) => {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final p in coords) [p.longitude, p.latitude]
              ],
            },
            'properties': const {},
          }
        ],
      };

  /// Append a trail polyline to the active draft route.
  ///
  /// When the draft already has a tail, a STRAIGHT-LINE connector joins it
  /// to the trail's entrance — we deliberately don't run the routing
  /// service here because it tends to dogleg through unrelated streets
  /// when the tap-target is far from the draft, producing the "weird
  /// back-and-forth" visual the user reported. Snap-to-roads is a
  /// click-by-click affordance; trail splice is a "this exact line"
  /// commitment.
  ///
  /// Layout invariant preserved: every call adds the same number of items
  /// to _draft and _segments, so the existing undo (one waypoint + one
  /// segment per click) cleanly removes the trail in two undos —
  /// connector first, then the trail itself.
  Future<void> _appendTrailToDraft(List<LatLng> trail) async {
    if (trail.length < 2 || !_drawing || !mounted) return;
    setState(() {
      if (_draft.isEmpty) {
        // First action on a fresh draft: seed with the trail's entrance.
        _draft.add(trail.first);
      } else {
        // Existing draft: drop a straight-line connector to the trail's
        // entrance, plus the entrance as a waypoint so the user can undo
        // back to "just before the trail."
        final prev = _draft.last;
        _segments.add([prev, trail.first]);
        _draft.add(trail.first);
      }
      // Now the trail itself, with its endpoint as the closing waypoint.
      _segments.add(List.of(trail));
      _draft.add(trail.last);
    });
    _push('setDraft', _draftGeo());
  }

  /// Find every rendered segment with the same OSM `name` and stitch them
  /// into one polyline. Protomaps fragments long ways at tile boundaries;
  /// this assembles the user-perceived trail back together by chaining
  /// segments head-to-tail. The first segment is the one whose endpoint is
  /// closest to [seedNear] (the user's tap point); each subsequent segment
  /// is the unattached one whose endpoint best matches the chain's tail.
  /// Returns null if [name] is empty or no segments are found.
  Future<List<LatLng>?> _assembleNamedTrail(
    String name,
    LatLng seedNear,
  ) async {
    if (name.isEmpty) return null;
    final raw = await _eval('queryTrailByName(${jsonEncode(name)})');
    if (raw == null) return null;
    final List<dynamic> list;
    try {
      list = jsonDecode(raw) as List;
    } catch (_) {
      return null;
    }
    if (list.isEmpty) return null;

    // Parse each LineString into a List<LatLng>.
    final segs = <List<LatLng>>[];
    for (final s in list) {
      if (s is! List) continue;
      final pts = <LatLng>[
        for (final c in s)
          if (c is List && c.length >= 2)
            LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      if (pts.length >= 2) segs.add(pts);
    }
    if (segs.isEmpty) return null;

    // Pick the seed segment: whichever segment contains an endpoint closest
    // to the user's tap. Orientation doesn't matter — we grow from BOTH
    // ends so a mid-trail tap captures the trail in both directions.
    const dist = Distance();
    double seedDist = double.infinity;
    int seedIdx = 0;
    for (var i = 0; i < segs.length; i++) {
      final dHead = dist.as(LengthUnit.Meter, seedNear, segs[i].first);
      final dTail = dist.as(LengthUnit.Meter, seedNear, segs[i].last);
      final d = dHead < dTail ? dHead : dTail;
      if (d < seedDist) {
        seedDist = d;
        seedIdx = i;
      }
    }
    final chain = List<LatLng>.of(segs[seedIdx]);
    final used = <int>{seedIdx};

    // Grow at BOTH ends. Each pass tries to extend chain.last AND chain.first
    // using the same 5 m endpoint-match epsilon (tolerates tile-boundary
    // float jitter without welding unrelated ways that just happen to
    // share a name). Stops when neither end can grow anymore.
    const eps = 5.0;
    var grew = true;
    while (grew) {
      grew = false;
      // Grow the tail (append).
      for (var i = 0; i < segs.length; i++) {
        if (used.contains(i)) continue;
        final dHead = dist.as(LengthUnit.Meter, chain.last, segs[i].first);
        final dTail = dist.as(LengthUnit.Meter, chain.last, segs[i].last);
        if (dHead <= eps) {
          chain.addAll(segs[i].skip(1));
          used.add(i);
          grew = true;
          break;
        }
        if (dTail <= eps) {
          chain.addAll(segs[i].reversed.skip(1));
          used.add(i);
          grew = true;
          break;
        }
      }
      // Grow the head (prepend).
      for (var i = 0; i < segs.length; i++) {
        if (used.contains(i)) continue;
        final dHead = dist.as(LengthUnit.Meter, chain.first, segs[i].first);
        final dTail = dist.as(LengthUnit.Meter, chain.first, segs[i].last);
        if (dTail <= eps) {
          chain.insertAll(0, segs[i].take(segs[i].length - 1));
          used.add(i);
          grew = true;
          break;
        }
        if (dHead <= eps) {
          chain.insertAll(0,
              segs[i].reversed.take(segs[i].length - 1).toList());
          used.add(i);
          grew = true;
          break;
        }
      }
    }
    return chain.length >= 2 ? chain : null;
  }

  Future<void> _dropWaypointAt(String routeId, LatLng point) async {
    if (!mounted) return;
    final picked = await showModalBottomSheet<_WaypointPickResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _NewWaypointSheet(),
    );
    if (picked == null) return;
    await ref.read(routeWaypointServiceProvider).create(
          partyId: widget.partyId,
          routeId: routeId,
          name: picked.name,
          icon: picked.icon,
          location: point,
          note: picked.note,
        );
  }

  void _onPinTap(String id) {
    if (!mounted) return;
    final pin = _pins.where((p) => p.id == id).firstOrNull;
    if (pin != null) _showPin(pin);
  }

  void _onRouteTap(String id) {
    if (!mounted) return;
    final route = _routes.where((r) => r.id == id).firstOrNull;
    if (route == null) return;
    _showRouteSheet(route);
  }

  void _onMemberTap(String id) {
    if (!mounted) return;
    final member = _members.where((m) => m.userId == id).firstOrNull;
    if (member == null) return;
    if (member.isSelf) {
      HapticFeedback.selectionClick();
      _showWhereAmI(member);
    } else {
      HapticFeedback.selectionClick();
      _showMemberInfo(member);
    }
  }

  Future<void> _showWhereAmI(MemberPosition self) async {
    final fmt = _currentSettings?.coordFormat ?? CoordFormat.latLonDecimal;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WhereAmISheet(member: self, format: fmt),
    );
  }

  /// Detailed sheet for a tapped party member — matches the depth of the
  /// "Where am I" sheet for the self dot (callsign, coords, last-seen,
  /// speed, heading, accuracy, altitude + distance and bearing from us).
  Future<void> _showMemberInfo(MemberPosition m) async {
    final fmt = _currentSettings?.coordFormat ?? CoordFormat.latLonDecimal;
    final self = _members.where((mp) => mp.isSelf).firstOrNull;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberInfoSheet(member: m, self: self, format: fmt),
    );
  }

  Future<void> _showRouteSheet(MapRoute route) async {
    HapticFeedback.selectionClick();
    await _eval('setSelectedRoute(${jsonEncode(route.id)})');
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteSheet(
        route: route,
        // Strip "/map.html" so the DEM sampler can hit `/dem/...` on the
        // same in-app server.
        serverBaseUrl: (_url ?? '').replaceFirst('/map.html', ''),
        onSurfaceMix: () => _computeSurfaceMix(route),
        onRename: (newName) => ref
            .read(routeServiceProvider)
            .update(partyId: widget.partyId, route: route, name: newName),
        onPickColor: (c) => ref
            .read(routeServiceProvider)
            .update(partyId: widget.partyId, route: route, color: c),
        onShare: () => Share.share(_shareTextFor(route)),
        onExportGpx: () => _exportRouteGpx(route),
        onAddWaypoint: () {
          // Close the drawer, then enter placement mode. Next map tap will
          // open the new-waypoint sheet at that coord.
          Navigator.of(context).pop();
          setState(() => _placingWaypointForRouteId = route.id);
          _pushPlacementMode();
        },
        onDelete: route.mine
            ? () async {
                await ref.read(routeServiceProvider).delete(route.id);
                if (mounted) Navigator.of(context).pop();
              }
            : null,
      ),
    );
    if (!mounted) return;
    // Sheet dismissed (drag-down, backdrop tap, back) — clear selection.
    await _eval('setSelectedRoute(null)');
  }

  /// Tell the map to fit the route's bbox (loads the tiles along it), wait
  /// for the camera to settle, then run the surface-mix query in JS.
  Future<Map<String, double>> _computeSurfaceMix(MapRoute route) async {
    if (route.points.length < 2) return const {};
    // Bounding box of the route.
    double minLat = route.points.first.latitude;
    double maxLat = minLat;
    double minLng = route.points.first.longitude;
    double maxLng = minLng;
    for (final p in route.points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    await _eval('fitBounds($minLng, $minLat, $maxLng, $maxLat)');
    // Give the easeTo + tile load a beat to finish.
    await Future.delayed(const Duration(milliseconds: 900));
    final coordsJson = jsonEncode(
        [for (final p in route.points) [p.longitude, p.latitude]]);
    final raw = await _eval('surfaceMixForLine(${jsonEncode(coordsJson)})');
    if (raw == null || raw.isEmpty) return const {};
    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      return parsed.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return const {};
    }
  }

  String _shareTextFor(MapRoute r) {
    if (r.points.isEmpty) return r.name;
    final first = r.points.first;
    return '${r.name} — start: ${first.latitude.toStringAsFixed(5)}, '
        '${first.longitude.toStringAsFixed(5)}';
  }

  Future<void> _exportRouteGpx(MapRoute r) async {
    final gpx = ref.read(gpxServiceProvider).routeToGpx(r.name, r.points);
    await Share.share(gpx, subject: '${r.name}.gpx');
  }

  // ---- Drawing ------------------------------------------------------------
  List<LatLng> get _drawnLine =>
      _segments.isEmpty ? _draft : [for (final s in _segments) ...s];

  Future<void> _addDrawPoint(LatLng point) async {
    final prev = _draft.isNotEmpty ? _draft.last : null;
    setState(() => _draft.add(point));
    if (prev != null) {
      if (_snap) {
        setState(() => _snapping = true);
        final seg = await ref.read(routingServiceProvider).snap(prev, point);
        if (!mounted) return;
        setState(() {
          _segments.add(seg);
          _snapping = false;
        });
      } else {
        setState(() => _segments.add([prev, point]));
      }
    }
    _push('setDraft', _draftGeo());
  }

  Map<String, dynamic> _draftGeo() => {
        'type': 'FeatureCollection',
        'features': _drawnLine.length < 2
            ? []
            : [
                {
                  'type': 'Feature',
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [
                      for (final pt in _drawnLine) [pt.longitude, pt.latitude]
                    ]
                  },
                  'properties': {},
                }
              ],
      };

  void _clearDraft() {
    _draft.clear();
    _segments.clear();
    _freehandPts.clear();
    _push('setDraft', _draftGeo());
  }

  /// Decimate a screen-space polyline so we don't ship every onPanUpdate
  /// frame to JS. Drops points whose perpendicular distance from the line
  /// connecting their neighbours is below [epsilonPx] — Ramer-Douglas-Peucker
  /// in its iterative one-pass form. Keeps the natural curve of the finger
  /// drag while cutting most points.
  List<Offset> _decimate(List<Offset> pts, {double epsilonPx = 3}) {
    if (pts.length < 3) return List.of(pts);
    final out = <Offset>[pts.first];
    for (int i = 1; i < pts.length - 1; i++) {
      final a = out.last;
      final b = pts[i];
      final c = pts[i + 1];
      // Perpendicular distance from b to line ac.
      final dx = c.dx - a.dx, dy = c.dy - a.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) continue;
      final d = ((b.dx - a.dx) * dy - (b.dy - a.dy) * dx).abs() / len;
      if (d > epsilonPx) out.add(b);
    }
    out.add(pts.last);
    return out;
  }

  // ---- Freehand multi-touch routing ----------------------------------------
  //
  // The overlay's Listener calls these directly. Goal: 1 finger drives a
  // freehand draw stroke, 2 fingers drive a pan + pinch-zoom + rotate on
  // the WebView via JS. A touch sequence "becomes" a pan the moment a
  // second finger lands; from that point on, we don't draw again until
  // every finger lifts (avoids accidental strokes when you let one finger
  // go but keep the other on the map).

  void _freehandPointerDown(PointerDownEvent e) {
    _activePtrs[e.pointer] = e.localPosition;
    if (_activePtrs.length == 1 && !_gestureIsPan) {
      setState(() {
        _freehandActive = true;
        _freehandPts
          ..clear()
          ..add(e.localPosition);
      });
    } else if (_activePtrs.length == 2) {
      // Escalate to two-finger pan/pinch/rotate. Throw away whatever
      // partial stroke we had — the user is now manipulating the map.
      _gestureIsPan = true;
      setState(() {
        _freehandActive = false;
        _freehandPts.clear();
      });
      _initTwoFinger();
    }
    // 3+ fingers — extras are tracked but don't change behaviour.
  }

  void _freehandPointerMove(PointerMoveEvent e) {
    if (!_activePtrs.containsKey(e.pointer)) return;
    _activePtrs[e.pointer] = e.localPosition;
    if (_activePtrs.length == 1 && _freehandActive && !_gestureIsPan) {
      setState(() => _freehandPts.add(e.localPosition));
    } else if (_activePtrs.length >= 2 && _gestureIsPan) {
      _applyTwoFingerDelta();
    }
  }

  Future<void> _freehandPointerUp(PointerUpEvent e) async {
    if (!_activePtrs.containsKey(e.pointer)) return;
    _activePtrs.remove(e.pointer);
    if (_activePtrs.isEmpty) {
      // All fingers up — terminate the gesture. If we were drawing, commit;
      // if we were panning, just reset.
      final wasDrawing = _freehandActive && !_gestureIsPan;
      final hadStroke = wasDrawing && _freehandPts.length >= 2;
      setState(() => _freehandActive = false);
      _gestureIsPan = false;
      _twoFingerMid = null;
      _twoFingerDist = null;
      _twoFingerAngle = null;
      if (hadStroke) await _commitFreehand();
    } else if (_gestureIsPan && _activePtrs.length < 2) {
      // Dropped from 2 fingers to 1 — keep panning mode locked off so
      // the lingering finger doesn't start a new stroke.
      _twoFingerMid = null;
      _twoFingerDist = null;
      _twoFingerAngle = null;
    }
  }

  void _freehandPointerCancel(PointerCancelEvent e) {
    _activePtrs.remove(e.pointer);
    if (_activePtrs.isEmpty) {
      setState(() {
        _freehandActive = false;
        _freehandPts.clear();
      });
      _gestureIsPan = false;
      _twoFingerMid = null;
      _twoFingerDist = null;
      _twoFingerAngle = null;
    } else if (_activePtrs.length < 2) {
      _twoFingerMid = null;
      _twoFingerDist = null;
      _twoFingerAngle = null;
    }
  }

  /// Snapshot the two-finger geometry — midpoint, finger separation,
  /// angle between the two fingers in radians.
  void _initTwoFinger() {
    if (_activePtrs.length < 2) return;
    final pts = _activePtrs.values.toList(growable: false);
    _twoFingerMid = (pts[0] + pts[1]) / 2;
    _twoFingerDist = (pts[0] - pts[1]).distance;
    _twoFingerAngle = math.atan2(
        pts[1].dy - pts[0].dy, pts[1].dx - pts[0].dx);
  }

  /// Compute the diff vs. the last sampled two-finger geometry and route
  /// it to the map: midpoint delta → panBy, finger-separation ratio →
  /// zoomBy, angle delta → rotateBy. Skips degenerate samples to avoid
  /// NaN-floods when the fingers happen to be co-located mid-frame.
  void _applyTwoFingerDelta() {
    if (_activePtrs.length < 2 ||
        _twoFingerMid == null ||
        _twoFingerDist == null ||
        _twoFingerAngle == null) {
      _initTwoFinger();
      return;
    }
    final pts = _activePtrs.values.toList(growable: false);
    final newMid = (pts[0] + pts[1]) / 2;
    final newDist = (pts[0] - pts[1]).distance;
    final newAngle = math.atan2(
        pts[1].dy - pts[0].dy, pts[1].dx - pts[0].dx);

    // Pan — map content follows the midpoint, so the camera moves
    // opposite to the finger delta.
    final panDelta = newMid - _twoFingerMid!;
    if (panDelta.distance >= 0.5) {
      _eval('panBy(${-panDelta.dx},${-panDelta.dy})');
    }
    // Zoom — exponent of finger-distance ratio. ≥10% change to avoid
    // jitter on near-static pinches.
    if (newDist > 1 && _twoFingerDist! > 1) {
      final ratio = newDist / _twoFingerDist!;
      if ((ratio - 1).abs() >= 0.005) {
        final dz = math.log(ratio) / math.ln2;
        _eval('zoomBy($dz,${newMid.dx},${newMid.dy})');
      }
    }
    // Rotate — wrap the angle delta into [-π, π] so a sweep across the
    // ±π boundary doesn't flip the camera 360° in one frame.
    double dA = newAngle - _twoFingerAngle!;
    if (dA > math.pi) dA -= 2 * math.pi;
    if (dA < -math.pi) dA += 2 * math.pi;
    if (dA.abs() >= 0.005) {
      final deg = dA * 180 / math.pi;
      _eval('rotateBy($deg,${newMid.dx},${newMid.dy})');
    }

    _twoFingerMid = newMid;
    _twoFingerDist = newDist;
    _twoFingerAngle = newAngle;
  }

  /// Finger-lift handler for freehand mode. Batch-converts screen points
  /// to lat/lng via the JS bridge, optionally snaps the polyline to the
  /// road network, then APPENDS to whatever the user has already drawn —
  /// so lifting your finger and starting again continues the same route
  /// instead of resetting it. (QA: "the route resets if you lift your
  /// finger and then redraws from where you redraw the route, instead of
  /// continuing the same route".)
  Future<void> _commitFreehand() async {
    if (_freehandPts.length < 2) return;
    setState(() => _snapping = _snap);
    final pruned = _decimate(_freehandPts);
    final xyJson =
        jsonEncode([for (final p in pruned) [p.dx, p.dy]]);
    final llRaw = await _eval(
        'screenPointsToLatLngs(${jsonEncode(xyJson)})');
    if (!mounted) return;
    if (llRaw == null) {
      setState(() {
        _snapping = false;
        _freehandPts.clear();
      });
      return;
    }
    String coordsJson = llRaw;
    if (_snap) {
      final snapped =
          await _eval('snapToRoads(${jsonEncode(coordsJson)})');
      if (!mounted) return;
      if (snapped != null) coordsJson = snapped;
    }
    List<LatLng> coords;
    try {
      coords = (jsonDecode(coordsJson) as List).map((e) {
        final l = e as List;
        return LatLng(
            (l[1] as num).toDouble(), (l[0] as num).toDouble());
      }).toList();
    } catch (_) {
      setState(() {
        _snapping = false;
        _freehandPts.clear();
      });
      return;
    }
    setState(() {
      // Append this stroke as its own segment so undo can peel them off
      // one at a time. The full route is the concatenation of segments
      // (see `_drawnLine`). _draft mirrors that for accurate UI labels.
      _segments.add(coords);
      _draft
        ..clear()
        ..addAll([for (final seg in _segments) ...seg]);
      _freehandPts.clear();
      _snapping = false;
    });
    _push('setDraft', _draftGeo());
  }

  Future<void> _saveRoute() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Name this route'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, controller.text.trim()),
              child: const Text('Share')),
        ],
      ),
    );
    if (name == null) return;
    try {
      await ref.read(routeServiceProvider).create(
            partyId: widget.partyId,
            name: name.isEmpty ? 'Route' : name,
            points: _drawnLine,
          );
      if (mounted) setState(() => _drawing = false);
      _clearDraft();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(humanizeError(e))));
      }
    }
  }

  // ---- Pins ---------------------------------------------------------------
  /// Open the new-pin sheet at the given coordinate.
  Future<void> _dropPinAt(LatLng point) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NewPinSheet(
        onSubmit: (type, name, note, photo) async {
          // Save the photo locally FIRST so it's already on disk by the time
          // the realtime INSERT round-trips and we look it up by photoId.
          if (photo != null) {
            await ref
                .read(photoStoreProvider)
                .saveFromPath(photo.id, photo.sourcePath);
          }
          await ref.read(pinServiceProvider).drop(
                partyId: widget.partyId,
                type: type,
                name: name,
                location: point,
                note: note,
                photoId: photo?.id,
              );
          // "Meet here" pins auto-broadcast a chat ping so the crew sees the
          // rendezvous without needing to find it on the map.
          if (type == PinType.meet.id) {
            try {
              final fmt = _currentSettings?.coordFormat ??
                  CoordFormat.latLonDecimal;
              final coords =
                  formatCoord(point.latitude, point.longitude, fmt);
              await ref.read(chatServiceProvider).send(
                    partyId: widget.partyId,
                    text: '📍 Meet here — $name · $coords',
                  );
            } catch (_) {/* chat failure shouldn't void the pin */}
          }
        },
      ),
    );
  }

  /// Drop a pin at the user's most recent live position.
  Future<void> _dropPinOnSelf() async {
    HapticFeedback.mediumImpact();
    final self = _members.where((m) => m.isSelf).firstOrNull;
    if (self == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No location fix yet')),
      );
      return;
    }
    await _dropPinAt(self.location);
  }

  Future<void> _showPin(MapPin pin) async {
    String? photoPath;
    if (pin.photoId != null) {
      photoPath = await ref.read(photoStoreProvider).pathFor(pin.photoId!);
      if (!await File(photoPath).exists()) photoPath = null;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(pin.name),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photoPath != null) ...[
                GestureDetector(
                  onTap: () {
                    Navigator.pop(dctx);
                    showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        backgroundColor: Colors.black,
                        insetPadding: EdgeInsets.zero,
                        child: InteractiveViewer(
                          child: Image.file(File(photoPath!)),
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(photoPath),
                        width: 240, height: 160, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(PinType.fromId(pin.type).label),
              if (pin.note != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(pin.note!)),
              if (pin.photoId != null && photoPath == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Photo was taken on another device.',
                    style:
                        TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
                  ),
                ),
            ]),
        actions: [
          if (pin.mine)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              onPressed: () async {
                await ref.read(pinServiceProvider).delete(pin.id);
                if (pin.photoId != null) {
                  await ref.read(photoStoreProvider).delete(pin.photoId!);
                }
                if (dctx.mounted) Navigator.pop(dctx);
              },
              child: const Text('Delete'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('Close')),
        ],
      ),
    );
  }

  // ---- Search -------------------------------------------------------------
  /// Fetch nearby POIs from the basemap's `pois` source-layer for the current
  /// viewport. Limited to currently-loaded tiles — zoom in to see more.
  Future<List<_NearbyPoi>> _nearbyPois() async {
    final raw = await _eval('nearbyPois()');
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list) _NearbyPoi.fromJson(Map<String, dynamic>.from(e as Map))
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _showSearch() async {
    final place = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SearchSheet(
        // Bias search toward where the user is currently looking. Photon
        // ranks results by distance to (lat, lon) when provided, so a query
        // like "Salmon Creek" prefers the one 20 mi from the viewport over
        // the one in Maine. When `searchLimitToRegion` is on, we additionally
        // pass the active region's bbox so distant matches are dropped
        // outright — the "I'm only ever going to be in WA" workflow.
        onSearch: (q) {
          final limit = _currentSettings?.searchLimitToRegion ?? false;
          List<double>? bbox;
          if (limit) {
            final activeId = ref.read(activeRegionProvider).valueOrNull;
            if (activeId != null) {
              final region = ref.read(regionCatalogProvider).byId(activeId);
              if (region != null) bbox = region.bbox;
            }
          }
          return ref.read(geocoderServiceProvider).search(
                q,
                near: LatLng(_camera.value.lat, _camera.value.lng),
                bbox: bbox,
              );
        },
        onNearby: _nearbyPois,
      ),
    );
    if (place != null) {
      await _eval('flyTo(${place.location.longitude},${place.location.latitude},13)');
      _push('setSearch', {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [place.location.longitude, place.location.latitude]
            },
            'properties': {},
          }
        ],
      });
    }
  }

  /// Show the layers sheet for toggling overlay layers.
  void _showLayersSheet() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget overlayTile(
                  String id, IconData icon, String title, String sub) =>
              SwitchListTile(
                value: _overlays[id] ?? false,
                onChanged: (v) async {
                  await _setOverlay(id, v);
                  setSheet(() {});
                },
                secondary: Icon(icon),
                title: Text(title),
                subtitle: Text(sub),
              );

          Widget imageryTile(String? id, IconData icon, String title, String sub) =>
              RadioListTile<String?>(
                value: id,
                groupValue: _imagery,
                onChanged: (v) async {
                  await _setImagery(v);
                  setSheet(() {});
                },
                secondary: Icon(icon),
                title: Text(title),
                subtitle: Text(sub),
              );

          Widget header(String t) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(t,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70)),
                ),
              );

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Layers',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  header('Basemap imagery'),
                  imageryTile(null, Icons.map_outlined, 'Vector basemap',
                      'Offline PMTiles (default). Fast, low data.'),
                  imageryTile('sat-esri', Icons.satellite_alt, 'Satellite',
                      'Esri World Imagery — global high-res, needs internet.'),
                  imageryTile('sat-usgs', Icons.satellite_outlined,
                      'USGS aerial',
                      'Federal aerial imagery (US only, needs internet).'),
                  imageryTile('opentopo', Icons.landscape_outlined,
                      'OpenTopoMap',
                      'Hiker topo style — contours + relief.'),
                  if (_imagery != null)
                    SwitchListTile(
                      value: _hybrid,
                      onChanged: (v) async {
                        await _setHybrid(v);
                        setSheet(() {});
                      },
                      secondary: const Icon(Icons.layers_outlined),
                      title: const Text('Hybrid (show roads + labels)'),
                      subtitle: const Text(
                          'Drape PMTiles roads, trails, and labels over the '
                          'imagery.'),
                    ),
                  const Divider(height: 16),
                  header('Overlays'),
                  overlayTile('overlay-trails', Icons.alt_route,
                      'Trails & tracks',
                      'Paths + unpaved roads from the offline basemap.'),
                  overlayTile('usgs-topo', Icons.terrain, 'USGS Topo (overlay)',
                      'Translucent USGS topo on top of whatever\'s below.'),
                  overlayTile('blm-sma', Icons.public_outlined,
                      'BLM public lands',
                      'Federal land ownership (BLM Surface Management Agency).'),
                  overlayTile('wildfires', Icons.local_fire_department_outlined,
                      'Current wildfires',
                      'NIFC perimeters — refreshed when toggled on.'),
                  const Divider(height: 16),
                  header('Map style'),
                  SwitchListTile(
                    value: _currentSettings?.offRoadStyle ?? false,
                    onChanged: (v) async {
                      final s = _currentSettings;
                      if (s == null) return;
                      await ref
                          .read(settingsControllerProvider.notifier)
                          .save(s.copyWith(offRoadStyle: v));
                      setSheet(() {});
                    },
                    secondary: const Icon(Icons.terrain_outlined),
                    title: const Text('Off-road style'),
                    subtitle: const Text(
                        'Mute highways, bolden trails, stronger hillshade.'),
                  ),
                  // Activity-based trail filter. Filters only the path/track
                  // layers — major roads always visible. Distinct visual
                  // styling (green vs amber dashes) means even in "All" mode
                  // you can tell paths from forest tracks at a glance.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Show trails',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70)),
                          const SizedBox(height: 8),
                          SegmentedButton<MapActivity>(
                            segments: const [
                              ButtonSegment(
                                  value: MapActivity.all,
                                  label: Text('All'),
                                  icon: Icon(Icons.alt_route, size: 16)),
                              ButtonSegment(
                                  value: MapActivity.hike,
                                  label: Text('Hike'),
                                  icon: Icon(Icons.hiking, size: 16)),
                              ButtonSegment(
                                  value: MapActivity.orv,
                                  label: Text('ORV'),
                                  icon: Icon(Icons.terrain, size: 16)),
                            ],
                            selected: {
                              _currentSettings?.mapActivity ?? MapActivity.all
                            },
                            onSelectionChanged: (selection) async {
                              final s = _currentSettings;
                              if (s == null || selection.isEmpty) return;
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .save(s.copyWith(
                                      mapActivity: selection.first));
                              setSheet(() {});
                            },
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Hike paths render green dashes; ORV tracks '
                            'render amber. Major roads always visible.',
                            style: TextStyle(
                                fontSize: 11, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 16),
                  header('Tools'),
                  ListTile(
                    leading: const Icon(Icons.straighten),
                    title: const Text('Measure distance'),
                    subtitle: const Text(
                        'Tap the map to drop points; total distance lives at '
                        'the top until you tap Done.'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _startMeasure();
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Toggle 3D tilt. Applies the user's terrain-height setting before tilting in.
  Future<void> _toggle3d() async {
    HapticFeedback.selectionClick();
    final on = !_is3d;
    setState(() => _is3d = on);
    if (on) {
      final exag =
          ref.read(settingsControllerProvider).valueOrNull?.terrainExaggeration ??
              1.2;
      await _eval('setExaggeration($exag)');
    }
    await _eval('setMode($on)');
  }

  /// Handle a fresh local GPS fix — runs every time `selfPositionProvider`
  /// emits (roughly every 5 m of movement). Two responsibilities:
  ///   • Follow-mode camera: keep the user's dot on screen at the user's
  ///     current zoom (set by recenter / pinch / never overridden).
  ///   • Auto heading-up: when sustained speed ≥ 4 mph, flip into heading-up
  ///     mode and rotate the camera to match the device course. Drops back
  ///     to north-up when speed falls below 2 mph (hysteresis prevents
  ///     flapping at the threshold).
  void _onLocalPosition(Position pos) {
    if (!_ready) return;
    // 1. Follow-mode camera.
    if (_following && !_drawing && !_measuring && !_placingPin &&
        _placingWaypointForRouteId == null) {
      final z = _camera.value.zoom;
      final keepZoom = (z.isFinite && z > 0) ? z : 14.0;
      _eval('flyToZoom(${pos.longitude},${pos.latitude},$keepZoom)');
    }
    // 2. Auto heading-up. 4 mph ≈ 1.788 m/s; drop threshold at 2 mph
    // ≈ 0.894 m/s to avoid toggling between every footfall.
    final s = _currentSettings;
    if (s == null || !s.autoHeadingUp) return;
    final speed = pos.speed.isFinite ? pos.speed : 0.0;
    final shouldBe = _autoHeadUpActive
        ? speed >= 0.894     // hysteresis low — keep heading-up until we're slow
        : speed >= 1.788;    // hysteresis high — only engage above brisk walk
    if (shouldBe == _autoHeadUpActive) {
      // Already in the right mode — still feed the heading so rotation tracks.
      if (_autoHeadUpActive && pos.heading.isFinite && pos.heading >= 0) {
        _eval('setBearing(${pos.heading})');
      }
      return;
    }
    setState(() => _autoHeadUpActive = shouldBe);
    if (shouldBe && pos.heading.isFinite && pos.heading >= 0) {
      _eval('setBearing(${pos.heading})');
    } else if (!shouldBe) {
      _eval('resetBearing()');
    }
  }

  /// Snap the camera back to the user's last known position. Preserves the
  /// current zoom (per QA: "make recenter stay at the zoom level you were at
  /// when you pushed the button"), re-enables follow-mode, and triggers a
  /// repaint so any stale tiles refetch.
  void _recenter() {
    if (!mounted) return;
    final self = _members.where((m) => m.isSelf).firstOrNull ??
        (_members.isNotEmpty ? _members.first : null);
    if (self == null) return;
    HapticFeedback.selectionClick();
    final z = _camera.value.zoom;
    final keepZoom = (z.isFinite && z > 0) ? z : 14.0;
    _eval(
        'flyToZoom(${self.location.longitude},${self.location.latitude},$keepZoom)');
    _eval('refreshMap()');
    // Re-push our own state too — pins/routes/members — in case the WebView
    // dropped any while the user was elsewhere.
    _pushAll();
    setState(() => _following = true);
  }

  @override
  Widget build(BuildContext context) {
    // Local self-position stream — fires every ~5 m of movement. Drives
    // (a) follow-mode camera updates, (b) the auto-heading-up logic when
    // the user's sustained speed is ≥4 mph. Independent from the encrypted
    // Supabase round-trip so the dot feels instant.
    ref.listen(selfPositionProvider, (_, next) {
      if (!mounted) return;
      final pos = next.valueOrNull;
      if (pos == null) return;
      _onLocalPosition(pos);
    });
    ref.listen(partyLiveProvider(widget.partyId), (_, next) {
      if (!mounted) return;
      final members = next.valueOrNull ?? const <MemberPosition>[];
      _push('setMembers', _membersGeo(members));
      // First fix → fly to the user so their dot is on-screen.
      if (!_autoCentered) {
        final self = members.where((m) => m.isSelf).firstOrNull;
        if (self != null) {
          _autoCentered = true;
          _eval('flyTo(${self.location.longitude},${self.location.latitude},14)');
        }
      }
      final s = _currentSettings;
      if (s != null && s.deadManEnabled) {
        _deadMan?.evaluate(next.valueOrNull ?? const [],
            enabled: true, thresholdMinutes: s.deadManMinutes);
      }
      // (Heading-up is now driven entirely by `_onLocalPosition` off the
      // local GPS stream — no need to re-evaluate it from the encrypted
      // partyLive round-trip too.)
    });
    ref.listen(settingsControllerProvider, (_, next) {
      if (!mounted) return;
      final before = _currentSettings;
      _currentSettings = next.valueOrNull;
      // Off-road style is reversible JS — re-apply on every change.
      if (before?.offRoadStyle != _currentSettings?.offRoadStyle) {
        _eval('setOffRoadStyle(${_currentSettings?.offRoadStyle == true})');
      }
      // Activity filter (hike / ORV / all) — push only when it actually
      // changes so we don't churn layer-visibility ops on every settings
      // notify.
      if (before?.mapActivity != _currentSettings?.mapActivity) {
        _pushActivityFilter();
      }
      // Trip mode → kill the GPU-expensive bits when entering, restore on
      // exit. The big costs: (a) 3D tilt continuously rendering the DEM
      // terrain mesh, (b) the always-on hillshade layer sampling DEM tiles
      // and shading every fill. Both off → 2x-ish frame-time win, which
      // adds up over a multi-hour trip.
      if (before?.tripMode != _currentSettings?.tripMode) {
        final on = _currentSettings?.tripMode == true;
        if (on) {
          if (_is3d) {
            setState(() => _is3d = false);
            _eval('setMode(false)');
          }
          _eval('setHillshade(false)');
        } else {
          _eval('setHillshade(true)');
          // Leave 3D off on exit — user re-tilts manually if they want it.
        }
      }
      // If the user just disabled auto-heads-up while we're currently
      // engaged, snap back to north so the map doesn't stay rotated.
      if (before?.autoHeadingUp == true &&
          _currentSettings?.autoHeadingUp == false &&
          _autoHeadUpActive) {
        setState(() => _autoHeadUpActive = false);
        _eval('resetBearing()');
      }
    });
    ref.listen(partyPinsProvider(widget.partyId), (_, next) {
      if (!mounted) return;
      _push('setPins', _pinsGeo(next.valueOrNull ?? const []));
    });
    ref.listen(partyRoutesProvider(widget.partyId), (_, next) {
      if (!mounted) return;
      _push('setRoutes', _routesGeo(next.valueOrNull ?? const []));
    });
    ref.listen(partyRouteWaypointsProvider(widget.partyId), (_, next) {
      if (!mounted) return;
      _push('setRouteWaypoints', _waypointsGeo(next.valueOrNull ?? const []));
    });
    // Stream the live recording breadcrumb to the map's `track` source.
    ref.listen(activeRecordingProvider, (_, next) {
      if (!mounted) return;
      final live = next.valueOrNull;
      _push('setTrack', _trackGeo(live?.points ?? const []));
    });
    ref.listen(activeRegionProvider, (_, _) {
      // Region switched (e.g. user downloaded MT, set it active) — refresh
      // the pan lock so they can immediately use the new region without
      // having to restart the screen.
      if (mounted) _pushMaxBounds();
    });
    ref.listen(partyMessagesProvider(widget.partyId), (_, next) {
      if (!mounted) return;
      final list = next.valueOrNull ?? const <ChatMessage>[];
      if (_lastSeenMsgCount < 0) {
        _lastSeenMsgCount = list.length;
        return;
      }
      if (list.length > _lastSeenMsgCount) {
        final fresh = list.skip(_lastSeenMsgCount);
        _lastSeenMsgCount = list.length;
        if (fresh.any((m) => !m.mine)) setState(() => _unread = true);
      }
    });

    final party = ref.watch(partyByIdProvider(widget.partyId)).valueOrNull;

    if (_noRegion) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_outlined, size: 56, color: Colors.white54),
                const SizedBox(height: 12),
                const Text('No map downloaded',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                  'Download a region for offline use — the map only works when '
                  'at least one region is on the device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Download a map'),
                  onPressed: () => context.push('/maps'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_url == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_url!)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              useHybridComposition: true,
            ),
            // Let the map win the gesture arena (pan/zoom/tilt) over the
            // overlaying bottom sheet. Stable Set (see _mapGestures).
            gestureRecognizers: _mapGestures,
            onWebViewCreated: (controller) {
              _ctrl = controller;
              controller.addJavaScriptHandler(
                  handlerName: 'mapReady',
                  callback: (a) {
                    if (!mounted) return null;
                    _ready = true;
                    _pushAll();
                    return null;
                  });
              controller.addJavaScriptHandler(
                  handlerName: 'mapTap',
                  callback: (a) {
                    if (a.isNotEmpty) _onMapTap(a.first as String);
                    return null;
                  });
              controller.addJavaScriptHandler(
                  handlerName: 'pinTap',
                  callback: (a) {
                    if (a.isNotEmpty) _onPinTap(a.first as String);
                    return null;
                  });
              controller.addJavaScriptHandler(
                  handlerName: 'routeTap',
                  callback: (a) {
                    if (a.isNotEmpty) _onRouteTap(a.first as String);
                    return null;
                  });
              controller.addJavaScriptHandler(
                  handlerName: 'memberTap',
                  callback: (a) {
                    if (a.isNotEmpty) _onMemberTap(a.first as String);
                    return null;
                  });
              controller.addJavaScriptHandler(
                  handlerName: 'trailTap',
                  callback: (a) {
                    if (a.isNotEmpty) _onTrailTap(a.first as String);
                    return null;
                  });
              controller.addJavaScriptHandler(
                  handlerName: 'cameraChanged',
                  callback: (a) {
                    if (!mounted || a.isEmpty) return null;
                    try {
                      final j = jsonDecode(a.first as String)
                          as Map<String, dynamic>;
                      _camera.value = _Camera(
                        bearing: (j['bearing'] as num).toDouble(),
                        zoom: (j['zoom'] as num).toDouble(),
                        lat: (j['lat'] as num).toDouble(),
                        lng: (j['lng'] as num).toDouble(),
                      );
                    } catch (_) {/* ignore malformed */}
                    return null;
                  });
              // Drops follow-mode the moment the user manually pans / pinches
              // / rotates — the JS bridge only fires this for input-driven
              // camera changes, not for our programmatic flyTo calls.
              controller.addJavaScriptHandler(
                  handlerName: 'userPan',
                  callback: (_) {
                    if (!mounted) return null;
                    if (_following) setState(() => _following = false);
                    return null;
                  });
            },
            onConsoleMessage: (c, msg) => debugPrint('MAP_CONSOLE: ${msg.message}'),
            onRenderProcessGone: (controller, detail) async {
              // WebView renderer was killed (e.g. low memory). Recover instead
              // of leaving a black, frozen screen.
              debugPrint('MAP renderer gone: ${detail.didCrash}');
              _ready = false;
              await controller.reload();
            },
          ),
          _TopBar(
            label: party?.displayLabel ?? 'Party',
            unread: _unread,
            onBack: () => context.canPop() ? context.pop() : context.go('/'),
            onSearch: _showSearch,
            onChat: () {
              setState(() {
                _unread = false;
                _lastSeenMsgCount = -1;
              });
              context.push('/party/${widget.partyId}/chat');
            },
          ),
          // Measure mode pill — distance + Undo/Done. Floats below TopBar.
          if (_measuring)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 56),
                  child: Center(child: _MeasurePill(
                    distanceM: _measureDistanceM,
                    pointCount: _measurePoints.length,
                    onUndo: _measurePoints.isEmpty ? null : _undoMeasurePoint,
                    onDone: _stopMeasure,
                  )),
                ),
              ),
            ),
          // Slim status chips just under the top bar — offline + placement hint
          // + trip mode badge + mesh status.
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 56), // clear the TopBar
                  child: Column(
                    children: [
                      // Mesh status — visible whenever a radio is paired so the
                      // user can see at a glance that the LoRa transport is up.
                      Consumer(builder: (_, wref, _) {
                        final state = wref
                                .watch(meshConnectionStateProvider)
                                .valueOrNull ??
                            MeshConnectionState.disconnected;
                        final radio =
                            wref.watch(connectedRadioProvider).valueOrNull;
                        if (state == MeshConnectionState.disconnected ||
                            radio == null) {
                          return const SizedBox.shrink();
                        }
                        final (icon, color, label) = switch (state) {
                          MeshConnectionState.ready => (
                              Icons.signal_cellular_alt,
                              Colors.lightGreenAccent,
                              'Mesh · ${radio.nodeCount} nodes'
                            ),
                          MeshConnectionState.syncing => (
                              Icons.sync,
                              Colors.amberAccent,
                              'Mesh syncing'
                            ),
                          MeshConnectionState.connecting => (
                              Icons.bluetooth_connected,
                              Colors.amberAccent,
                              'Mesh connecting'
                            ),
                          _ => (Icons.bluetooth_searching,
                              Colors.lightBlueAccent, 'Mesh scanning'),
                        };
                        return _StatusChip(
                            icon: icon, label: label, color: color);
                      }),
                      if (_offline) _StatusChip(
                        icon: Icons.cloud_off,
                        label: 'Offline mode',
                        color: Colors.orangeAccent,
                      ),
                      if (_currentSettings?.tripMode == true) _StatusChip(
                        icon: Icons.eco,
                        label: 'TRIP · 90s updates',
                        color: Colors.lightGreenAccent,
                      ),
                      if (_placingPin) _StatusChip(
                        icon: Icons.touch_app,
                        label: 'Tap the map to place a pin',
                        color: Colors.lightBlueAccent,
                        onCancel: () {
                          setState(() => _placingPin = false);
                          _pushPlacementMode();
                        },
                      ),
                      if (_placingWaypointForRouteId != null) _StatusChip(
                        icon: Icons.add_location_alt_outlined,
                        label: 'Tap the route to place a waypoint',
                        color: Colors.lightGreenAccent,
                        onCancel: () {
                          setState(() => _placingWaypointForRouteId = null);
                          _pushPlacementMode();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // REC pill — visible whenever a track is being recorded. Tap to open
          // the Tracks screen (pause/resume/stop live there).
          Consumer(
            builder: (_, wref, _) {
              final live = wref.watch(activeRecordingProvider).valueOrNull;
              if (live == null) return const SizedBox.shrink();
              return Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 56),
                    child: Center(
                      child: GestureDetector(
                        onTap: () => context.push('/tracks'),
                        child: _RecPill(live: live),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Compass — bottom-left, ALWAYS visible. Single tap snaps the
          // camera back to north. Heading-up is now driven entirely by the
          // auto-at-4mph speed logic (toggleable in Settings); the old
          // double-tap-to-toggle felt clunky and was removed.
          Positioned(
            left: 12,
            bottom: 130, // sits above the Flutter scale bar at bottom 96
            child: ValueListenableBuilder<_Camera>(
              valueListenable: _camera,
              builder: (_, cam, _) {
                final inHeadsUp = _autoHeadUpActive;
                return FloatingActionButton.small(
                  heroTag: 'compass',
                  backgroundColor: inHeadsUp
                      ? Colors.amber.withValues(alpha: 0.85)
                      : Colors.black.withValues(alpha: 0.6),
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    await _eval('resetBearing()');
                  },
                  child: Transform.rotate(
                    angle: -cam.bearing * 3.14159265 / 180,
                    child: Icon(
                      inHeadsUp ? Icons.my_location : Icons.navigation,
                      color: inHeadsUp ? Colors.black87 : Colors.white,
                    ),
                  ),
                );
              },
            ),
          ),
          // Scale bar — bottom-left, below the compass FAB. Recomputed live
          // from the camera state (zoom + latitude) so it always reflects
          // what's actually rendered.
          Positioned(
            left: 12,
            bottom: 96,
            child: ValueListenableBuilder<_Camera>(
              valueListenable: _camera,
              builder: (_, cam, _) => _ScaleBar(camera: cam),
            ),
          ),
          // Right-side FABs — sit just above the collapsed roster drawer.
          Positioned(
            right: 12,
            bottom: 96,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'layers',
                  onPressed: _showLayersSheet,
                  child: const Icon(Icons.layers_outlined),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'mode',
                  onPressed: _toggle3d,
                  child: Text(_is3d ? '2D' : '3D'),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'recenter',
                  onPressed: _recenter,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onLongPress: _drawing ? null : _dropPinOnSelf,
                  child: FloatingActionButton.small(
                    heroTag: 'pin',
                    backgroundColor: _placingPin ? Colors.lightBlueAccent : null,
                    onPressed: _drawing
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            setState(() => _placingPin = !_placingPin);
                            _pushPlacementMode();
                          },
                    child: const Icon(Icons.add_location_alt),
                  ),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'draw',
                  backgroundColor: _drawing ? Colors.lightBlueAccent : null,
                  onPressed: () => setState(() {
                    _drawing = !_drawing;
                    if (!_drawing) _clearDraft();
                  }),
                  child: const Icon(Icons.edit_road),
                ),
              ],
            ),
          ),
          // Freehand draw overlay — only mounted when in draw mode AND the
          // user has flipped the "Freehand" switch in the drawing panel.
          // The Listener captures pointer events directly (opaque, so the
          // WebView below never sees them) and disambiguates 1 finger →
          // freehand draw, 2 fingers → map pan/pinch/rotate via JS bridge.
          if (_drawing && _freehand)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _freehandPointerDown,
                onPointerMove: _freehandPointerMove,
                onPointerUp: _freehandPointerUp,
                onPointerCancel: _freehandPointerCancel,
                child: _freehandActive
                    ? CustomPaint(
                        painter: _FreehandPainter(_freehandPts))
                    : const SizedBox.expand(),
              ),
            ),
          if (_drawing)
            _DrawingPanel(
              points: _draft.length,
              snap: _snap,
              snapping: _snapping,
              freehand: _freehand,
              onToggleSnap: (v) => setState(() => _snap = v),
              onToggleFreehand: (v) => setState(() => _freehand = v),
              onUndo: _draft.isEmpty
                  ? null
                  : () {
                      setState(() {
                        if (_draft.isNotEmpty) _draft.removeLast();
                        if (_segments.isNotEmpty) _segments.removeLast();
                      });
                      _push('setDraft', _draftGeo());
                    },
              onCancel: () => setState(() {
                _drawing = false;
                _clearDraft();
              }),
              onSave: _drawnLine.length < 2 ? null : _saveRoute,
            )
          else
            _RosterSheet(
              partyId: widget.partyId,
              party: party,
              onFlyToPoint: _flyToPoint,
              onFlyToRoute: _flyToRoute,
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Bottom sheet: roster + pins + routes + actions
// ===========================================================================
class _RosterSheet extends ConsumerWidget {
  const _RosterSheet({
    required this.partyId,
    this.party,
    required this.onFlyToPoint,
    required this.onFlyToRoute,
  });
  final String partyId;
  final Party? party;

  /// Fly the camera to a single coordinate (pin taps, etc.).
  final Future<void> Function(LatLng) onFlyToPoint;

  /// Fit a route's full extent into the viewport.
  final Future<void> Function(MapRoute) onFlyToRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    final members = ref.watch(partyLiveProvider(partyId)).valueOrNull ?? const <MemberPosition>[];
    final pins = ref.watch(partyPinsProvider(partyId)).valueOrNull ?? const <MapPin>[];
    final routes = ref.watch(partyRoutesProvider(partyId)).valueOrNull ?? const <MapRoute>[];
    final isHost = party?.createdBy == uid;

    return DraggableScrollableSheet(
      initialChildSize: 0.1,
      minChildSize: 0.08,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surfaceGrey,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(
                width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              Flexible(
                child: Text('${party?.displayLabel ?? 'Crew'} (${members.length})',
                    style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
              ),
              const Spacer(),
              IconButton(icon: const Icon(Icons.ios_share), onPressed: () => _share(context, ref)),
            ]),
            for (final m in members) _MemberRow(m: m),
            const SizedBox(height: 12),
            Row(children: [
              Text('Pins (${pins.length})', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (pins.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _exportPins(ref, pins),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('GPX'),
                ),
            ]),
            for (final pin in pins)
              ListTile(
                contentPadding: EdgeInsets.zero, dense: true,
                leading: Icon(PinType.fromId(pin.type).icon, color: AppTheme.amber),
                title: Text(pin.name), subtitle: Text(PinType.fromId(pin.type).label),
                // Tap a pin in the list → fly the camera to it. The sheet
                // stays where the user has it; they can drag it down to see.
                onTap: () => onFlyToPoint(pin.location),
              ),
            const SizedBox(height: 12),
            Text('Routes (${routes.length})', style: Theme.of(context).textTheme.titleMedium),
            const Text('Use the ✏️ button to draw a route.',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
            for (final r in routes)
              ListTile(
                contentPadding: EdgeInsets.zero, dense: true,
                leading: const Icon(Icons.route, color: AppTheme.amber),
                title: Text(r.name), subtitle: Text('${r.points.length} points'),
                // Tap a route in the list → frame the whole route in the
                // viewport. fitBounds in the helper handles single-point
                // routes gracefully.
                onTap: () => onFlyToRoute(r),
                trailing: IconButton(
                  icon: const Icon(Icons.download, size: 20),
                  onPressed: () => _exportRoute(ref, r),
                ),
              ),
            const SizedBox(height: 16),
            _Actions(partyId: partyId, isHost: isHost),
          ],
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final pty = party;
    if (pty == null) return;
    final link = await ref.read(partyServiceProvider).shareLinkFor(pty);
    if (link == null || !context.mounted) return;
    // Offer QR first — it's the only zero-typo option when both devices are
    // out of cell signal. Fall back to the OS share sheet (SMS, copy, etc.)
    // for the case where the recipient is somewhere else entirely.
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('Show QR'),
              subtitle: const Text(
                  'They scan with their innawoods → Join screen.'),
              onTap: () => Navigator.of(context).pop('qr'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Send link'),
              subtitle: const Text(
                  'OS share sheet — SMS, Signal, copy, etc.'),
              onTap: () => Navigator.of(context).pop('link'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (picked == 'qr') {
      await InviteQrDialog.show(context, link);
    } else if (picked == 'link') {
      await Share.share('Join my innawoods party:\n$link',
          subject: 'innawoods invite');
    }
  }

  Future<void> _exportPins(WidgetRef ref, List<MapPin> pins) async {
    final gpx = ref.read(gpxServiceProvider);
    await gpx.shareGpx('innawoods-pins.gpx', gpx.pinsToGpx(pins));
  }

  Future<void> _exportRoute(WidgetRef ref, MapRoute route) async {
    final gpx = ref.read(gpxServiceProvider);
    final safe = route.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    await gpx.shareGpx('$safe.gpx', gpx.routeToGpx(route.name, route.points));
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.m});
  final MemberPosition m;
  @override
  Widget build(BuildContext context) {
    final color = m.isStale ? Colors.grey : AppTheme.hexColor(m.color);
    final subtitle = m.isStale
        ? 'last seen ${_ago(m.age)} ago'
        : (m.speed != null && m.speed! > 0.5 ? '${(m.speed! * 3.6).toStringAsFixed(0)} km/h' : 'here now');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: color, radius: 12),
      title: Text(m.callsign),
      subtitle: Text(subtitle),
      trailing: m.isSelf ? const Chip(label: Text('you'), visualDensity: VisualDensity.compact) : null,
    );
  }

  String _ago(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    return '${d.inHours}h';
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.partyId, required this.isHost});
  final String partyId;
  final bool isHost;
  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _busy = false;
  Future<void> _run(Future<void> Function() action, String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      ref.read(locationSharingProvider.notifier).stop();
      await action();
      ref.invalidate(myPartiesProvider);
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(humanizeError(e))));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) return const Center(child: CircularProgressIndicator());
    final svc = ref.read(partyServiceProvider);
    if (widget.isHost) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
        onPressed: () => _run(() => svc.endParty(widget.partyId), 'End party?',
            'Self-destructs all locations, pins, routes and messages for everyone. Cannot be undone.'),
        icon: const Icon(Icons.delete_forever),
        label: const Text('End party (self-destruct)'),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _run(() => svc.leaveParty(widget.partyId), 'Leave party?',
          'You’ll stop sharing your location and your local key for this party will be wiped.'),
      icon: const Icon(Icons.logout),
      label: const Text('Leave party'),
    );
  }
}

// ===========================================================================
// Top bar: back · search · identify-toggle · chat(glow)
// ===========================================================================
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.label,
    required this.unread,
    required this.onBack,
    required this.onSearch,
    required this.onChat,
  });
  final String label;
  final bool unread;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          children: [
            _RoundButton(icon: Icons.arrow_back, onTap: onBack),
            const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                onTap: onSearch,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(children: [
                    Icon(Icons.search, size: 18, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Search places', style: TextStyle(color: Colors.white70)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _RoundButton(icon: Icons.chat_bubble_outline, onTap: onChat, glow: unread),
          ],
        ),
      ),
    );
  }
}

/// Live track-recording pill — visible only while a recording is active.
class _RecPill extends StatefulWidget {
  const _RecPill({required this.live});
  final TrackInProgress live;
  @override
  State<_RecPill> createState() => _RecPillState();
}

class _RecPillState extends State<_RecPill> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // 1-Hz refresh for the duration text.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.live;
    final active = !live.paused;
    return Material(
      color: Colors.black.withValues(alpha: 0.75),
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _ctl,
              builder: (_, _) {
                final a = active ? (0.4 + 0.6 * _ctl.value) : 1.0;
                return Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: (active ? Colors.redAccent : Colors.white54)
                        .withValues(alpha: a),
                    shape: BoxShape.circle,
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            Text(
              '${active ? 'REC' : 'PAUSED'}  '
              '${_fmtDur(live.duration)}  ·  '
              '${_fmtMi(live.distanceMeters)}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDur(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  static String _fmtMi(double m) {
    final mi = m / 1609.344;
    final ft = m * 3.28084;
    if (mi < 0.1) return '${ft.toStringAsFixed(0)} ft';
    return '${mi.toStringAsFixed(mi < 10 ? 2 : 1)} mi';
  }
}

/// Snapshot of the map camera streamed from JS (`cameraChanged`). Drives the
/// compass FAB rotation + the scale bar.
@immutable
class _Camera {
  const _Camera({
    this.bearing = 0,
    this.zoom = 11,
    this.lat = 47.5,
    this.lng = -120.5,
  });
  final double bearing;
  final double zoom;
  final double lat;
  final double lng;
}

/// A live, latitude-aware map scale bar. Picks a "nice" round unit (50 ft,
/// 100 ft, 0.1 mi, 0.5 mi, …) for the current zoom and renders a notched
/// horizontal bar with the label above it.
class _ScaleBar extends StatelessWidget {
  const _ScaleBar({required this.camera});
  final _Camera camera;

  /// Meters per CSS pixel at the camera's zoom + latitude.
  /// `156543.03392` is Web-Mercator's meters-per-pixel at z0 at the equator.
  double get _mppCss =>
      156543.03392 * math.cos(camera.lat * math.pi / 180) /
      math.pow(2, camera.zoom);

  /// Returns (pixelWidth, label) for the nearest "nice" scale-bar value
  /// whose physical width is close to [targetPx] logical pixels.
  (double, String) _niceScale(double targetPx) {
    final mpp = _mppCss;
    if (mpp <= 0 || !mpp.isFinite) return (targetPx, '—');
    final targetMeters = mpp * targetPx;
    final targetFt = targetMeters * 3.28084;
    final targetMi = targetMeters / 1609.344;
    // Pick the right unit and round to a nice number.
    final useMiles = targetMi >= 0.2;
    if (useMiles) {
      final nice = _niceNumber(targetMi);
      final px = (nice * 1609.344) / mpp;
      final label = nice >= 1
          ? '${nice.toStringAsFixed(nice >= 10 ? 0 : 1)} mi'
          : '${nice.toStringAsFixed(2)} mi';
      return (px, label);
    } else {
      final nice = _niceNumber(targetFt);
      final px = (nice * 0.3048) / mpp;
      return (px, '${nice.toStringAsFixed(0)} ft');
    }
  }

  /// …0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, … — pick the highest such number ≤ x.
  ///
  /// The previous version derived magnitude from `x.toString().split('.')[0]
  /// .length`, which rounds any sub-1 value up to 1 (e.g. 0.3 mi → 1 mi),
  /// giving a 3× discrepancy between the scale bar and the route distance.
  /// Using `log10` gives the right magnitude for fractional inputs too.
  double _niceNumber(double x) {
    if (x <= 0) return 1;
    final exp = math.log(x) / math.ln10;
    final mag = math.pow(10, exp.floor()).toDouble();
    final norm = x / mag;
    final nice = norm >= 5
        ? 5.0
        : norm >= 2
            ? 2.0
            : 1.0;
    return nice * mag;
  }

  @override
  Widget build(BuildContext context) {
    final (px, label) = _niceScale(100);
    final width = px.clamp(40, 160).toDouble();
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, height: 1.2)),
            const SizedBox(height: 2),
            CustomPaint(
              size: Size(width, 6),
              painter: _ScaleBarPainter(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stacked horizontal bar showing what fraction of a route falls on each
/// road `kind`. Driven by `surfaceMixForLine` in the map.
class _SurfaceMixBar extends StatelessWidget {
  const _SurfaceMixBar({required this.mix});
  final Map<String, double> mix;

  // Friendly labels + colors per Protomaps `kind`.
  static const _kindMeta = <String, ({String label, Color color})>{
    'highway': (label: 'Highway', color: Color(0xFFEF5350)),
    'major_road': (label: 'Major road', color: Color(0xFFFFA726)),
    'minor_road': (label: 'Minor road', color: Color(0xFFFFD54F)),
    'path': (label: 'Path / track', color: Color(0xFF8BC34A)),
    'other': (label: 'Other road', color: Color(0xFF9CCC65)),
    'pedestrian': (label: 'Pedestrian', color: Color(0xFF26C6DA)),
    'rail': (label: 'Rail', color: Color(0xFF7E57C2)),
    'unknown': (label: 'Unknown', color: Color(0xFF455A64)),
  };

  @override
  Widget build(BuildContext context) {
    // Sort by descending share. Anything not in the meta table buckets into
    // "unknown" so colors stay coherent.
    final entries = mix.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final e in entries)
                  Expanded(
                    flex: (e.value * 1000).round(),
                    child: ColoredBox(
                      color: (_kindMeta[e.key] ?? _kindMeta['unknown']!).color,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            for (final e in entries)
              if (e.value >= 0.02)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: (_kindMeta[e.key] ?? _kindMeta['unknown']!).color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(_kindMeta[e.key] ?? _kindMeta['unknown']!).label} '
                      '${(e.value * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
          ],
        ),
      ],
    );
  }
}

/// Sparkline of elevation along the route — area-filled, simple, no labels.
class _ElevationSparkPainter extends CustomPainter {
  _ElevationSparkPainter({required this.samples, required this.color});
  final List<double?> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final valid = [for (final s in samples) if (s != null) s];
    if (valid.length < 2) return;
    final mn = valid.reduce(math.min);
    final mx = valid.reduce(math.max);
    final range = (mx - mn).abs() < 0.001 ? 1.0 : (mx - mn);
    final fill = Paint()
      ..color = color.withValues(alpha: 0.30)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    final n = samples.length;
    final path = ui.Path();
    final fillPath = ui.Path();
    bool started = false;
    for (var i = 0; i < n; i++) {
      final v = samples[i];
      if (v == null) continue;
      final x = i / (n - 1) * size.width;
      final y = size.height - (v - mn) / range * size.height;
      if (!started) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_ElevationSparkPainter old) =>
      old.samples != samples || old.color != color;
}

class _ScaleBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    // Horizontal line.
    canvas.drawLine(
        Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
    // Tick marks at the ends.
    canvas.drawLine(const Offset(0, 0), Offset(0, size.height), paint);
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_ScaleBarPainter oldDelegate) => false;
}

/// Measure-mode pill — shows live distance + Undo + Done buttons.
class _MeasurePill extends StatelessWidget {
  const _MeasurePill({
    required this.distanceM,
    required this.pointCount,
    required this.onUndo,
    required this.onDone,
  });
  final double distanceM;
  final int pointCount;
  final VoidCallback? onUndo;
  final VoidCallback onDone;

  String _label() {
    final mi = distanceM / 1609.344;
    final ft = distanceM * 3.28084;
    if (pointCount < 2) return 'Tap the map to start measuring';
    if (mi < 0.1) return '${ft.toStringAsFixed(0)} ft';
    return '${mi.toStringAsFixed(mi < 10 ? 2 : 1)} mi';
  }

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF26C6DA).withValues(alpha: 0.92),
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.straighten, size: 18, color: Colors.black87),
              const SizedBox(width: 8),
              Text(_label(),
                  style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              const SizedBox(width: 6),
              IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.undo, color: Colors.black87, size: 18),
                onPressed: onUndo,
                tooltip: 'Undo last point',
              ),
              IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.check, color: Colors.black87, size: 20),
                onPressed: onDone,
                tooltip: 'Done',
              ),
            ],
          ),
        ),
      );
}

/// A slim pill that floats under the top bar (offline mode, placement hint).
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onCancel,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onCancel;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Material(
          color: Colors.black.withValues(alpha: 0.7),
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                if (onCancel != null) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onCancel,
                    child: const Icon(Icons.close,
                        size: 16, color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.glow = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool glow;
  @override
  Widget build(BuildContext context) => Material(
        color: glow
            ? AppTheme.amber.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: glow ? Colors.black87 : null),
          ),
        ),
      );
}

// ===========================================================================
// Drawing panel
// ===========================================================================
class _DrawingPanel extends StatelessWidget {
  const _DrawingPanel({
    required this.points,
    required this.snap,
    required this.snapping,
    required this.freehand,
    required this.onToggleSnap,
    required this.onToggleFreehand,
    required this.onUndo,
    required this.onCancel,
    required this.onSave,
  });
  final int points;
  final bool snap;
  final bool snapping;
  final bool freehand;
  final ValueChanged<bool> onToggleSnap;
  final ValueChanged<bool> onToggleFreehand;
  final VoidCallback? onUndo;
  final VoidCallback onCancel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.surfaceGrey, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero, dense: true,
              value: freehand, onChanged: onToggleFreehand,
              title: const Text('Freehand draw'),
              subtitle: const Text(
                  'Drag your finger to draw. Releases auto-snap if Snap-to-trail is on.'),
              secondary: const Icon(Icons.gesture),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero, dense: true,
              value: snap, onChanged: onToggleSnap,
              title: const Text('Snap to trail'),
              secondary: snapping
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.route),
            ),
            Text(freehand
                ? 'Drag to draw · $points pts'
                : 'Tap the map to add points · $points'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: onUndo, icon: const Icon(Icons.undo), label: const Text('Undo'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: onCancel, icon: const Icon(Icons.close), label: const Text('Cancel'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: onSave, icon: const Icon(Icons.check), label: const Text('Save'))),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Renders the live finger-drag polyline during a freehand draw. Sits
/// inside the GestureDetector overlay so the user can see what they've
/// drawn before lift; the path is replaced by the real (snapped) line on
/// finger-up.
class _FreehandPainter extends CustomPainter {
  _FreehandPainter(this.points);
  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = Colors.lightBlueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      p.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(_FreehandPainter old) =>
      old.points.length != points.length;
}

// ===========================================================================
// New-pin sheet
// ===========================================================================
// ===========================================================================
// Route detail sheet — opens on route tap; stats, color, share/export/delete.
// ===========================================================================
class _RouteSheet extends StatefulWidget {
  const _RouteSheet({
    required this.route,
    required this.serverBaseUrl,
    required this.onRename,
    required this.onPickColor,
    required this.onShare,
    required this.onExportGpx,
    required this.onAddWaypoint,
    required this.onSurfaceMix,
    required this.onDelete,
  });
  final MapRoute route;
  final String serverBaseUrl;
  final Future<void> Function(String newName) onRename;
  final Future<void> Function(String hex) onPickColor;
  final VoidCallback onShare;
  final VoidCallback onExportGpx;
  final VoidCallback onAddWaypoint;
  final Future<Map<String, double>> Function() onSurfaceMix;
  final VoidCallback? onDelete;

  @override
  State<_RouteSheet> createState() => _RouteSheetState();
}

class _RouteSheetState extends State<_RouteSheet> {
  late String _color;
  late String _name;
  bool _editingName = false;
  late TextEditingController _nameCtl;

  // Elevation profile, sampled lazily after the sheet opens.
  List<double?>? _elevSamples;
  ElevationStats? _elevStats;
  bool _elevLoading = true;
  DemSampler? _sampler;

  // Surface mix (% by kind) — depends on which tiles are currently rendered;
  // an opening-time fitBounds nudges the camera to load most of the route.
  Map<String, double>? _surfaceMix;

  @override
  void initState() {
    super.initState();
    _color = widget.route.color ?? kRouteColors.first;
    _name = widget.route.name;
    _nameCtl = TextEditingController(text: _name);
    _loadElevation();
  }

  Future<void> _loadElevation() async {
    if (widget.serverBaseUrl.isEmpty || widget.route.points.length < 2) {
      if (mounted) setState(() => _elevLoading = false);
      return;
    }
    final s = DemSampler(baseUrl: widget.serverBaseUrl);
    _sampler = s;
    final samples = await s.sampleAlong(widget.route.points, n: 80);
    if (!mounted) return;
    setState(() {
      _elevSamples = samples;
      _elevStats = ElevationStats.from(samples);
      _elevLoading = false;
    });
    // Fire-and-forget the surface mix query — runs in parallel, updates UI
    // when done. Caller flies the camera to fit + waits for tiles.
    final mix = await widget.onSurfaceMix();
    if (!mounted) return;
    setState(() => _surfaceMix = mix);
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _sampler?.close();
    super.dispose();
  }

  /// Great-circle distance along the route polyline, in meters.
  double get _distanceM {
    if (widget.route.points.length < 2) return 0;
    const d = Distance();
    double total = 0;
    for (var i = 1; i < widget.route.points.length; i++) {
      total += d.as(LengthUnit.Meter, widget.route.points[i - 1],
          widget.route.points[i]);
    }
    return total;
  }

  String _ftLabel(double meters) => '${(meters * 3.28084).toStringAsFixed(0)} ft';

  /// Imperial first — feet for short routes, miles otherwise. US default.
  String _distanceLabel(double meters) {
    final mi = meters / 1609.344;
    final ft = meters * 3.28084;
    if (mi < 0.1) return '${ft.toStringAsFixed(0)} ft';
    return '${mi.toStringAsFixed(mi < 10 ? 2 : 1)} mi';
  }

  Future<void> _commitName() async {
    final next = _nameCtl.text.trim();
    setState(() => _editingName = false);
    if (next.isEmpty || next == _name) return;
    setState(() => _name = next); // optimistic
    await widget.onRename(next);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    return DraggableScrollableSheet(
      initialChildSize: 0.42,
      minChildSize: 0.18,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1E1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _parseHex(_color),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _editingName
                      ? TextField(
                          controller: _nameCtl,
                          autofocus: true,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600),
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: UnderlineInputBorder(),
                          ),
                          onSubmitted: (_) => _commitName(),
                          onTapOutside: (_) => _commitName(),
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: r.mine
                              ? () {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _nameCtl.text = _name;
                                    _editingName = true;
                                  });
                                }
                              : null,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(_name,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600)),
                              ),
                              if (r.mine) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.edit,
                                    size: 14, color: Colors.white38),
                              ],
                            ],
                          ),
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Top stat row — distance + point count.
            _StatRow(items: [
              _Stat('Distance', _distanceLabel(_distanceM)),
              _Stat('Points', '${r.points.length}'),
            ]),
            const SizedBox(height: 14),
            if (_elevLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Sampling elevation…',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              )
            else if (_elevStats != null && _elevSamples != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 56,
                    child: CustomPaint(
                      size: const Size(double.infinity, 56),
                      painter: _ElevationSparkPainter(
                        samples: _elevSamples!,
                        color: _parseHex(_color),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StatRow(items: [
                    _Stat('Ascent', _ftLabel(_elevStats!.ascentM)),
                    _Stat('Descent', _ftLabel(_elevStats!.descentM)),
                    _Stat('Max', _ftLabel(_elevStats!.maxM)),
                  ]),
                ],
              ),
            if (_surfaceMix != null && _surfaceMix!.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Surface mix',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              _SurfaceMixBar(mix: _surfaceMix!),
              const SizedBox(height: 4),
              const Text(
                'Based on the visible portion of the route.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
            if (r.mine) ...[
              const SizedBox(height: 18),
              const Text('Color', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kRouteColors.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final hex = kRouteColors[i];
                    final selected = hex.toLowerCase() == _color.toLowerCase();
                    return GestureDetector(
                      onTap: () {
                        // Optimistic: update local swatch immediately so the
                        // picker feels instant. The await syncs to the server
                        // in the background; realtime UPDATE re-paints the map.
                        HapticFeedback.lightImpact();
                        setState(() => _color = hex);
                        widget.onPickColor(hex);
                      },
                      child: Container(
                        width: 38,
                        decoration: BoxDecoration(
                          color: _parseHex(hex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                selected ? Colors.white : Colors.white24,
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.add_location_alt_outlined,
                    label: 'Add waypoint',
                    onTap: widget.onAddWaypoint,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.share_outlined,
                    label: 'Share',
                    onTap: widget.onShare,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.file_download_outlined,
                    label: 'GPX',
                    onTap: widget.onExportGpx,
                  ),
                ),
              ],
            ),
            if (widget.onDelete != null) ...[
              const SizedBox(height: 8),
              _ActionButton(
                icon: Icons.delete_outline,
                label: 'Delete route',
                danger: true,
                onTap: widget.onDelete!,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

Color _parseHex(String hex) {
  final v = int.parse(hex.replaceFirst('#', ''), radix: 16);
  return Color(0xFF000000 | v);
}

class _Stat {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.items});
  final List<_Stat> items;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (final s in items)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.label,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(s.value,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final fg = danger ? Colors.redAccent : Colors.white;
    return Material(
      color: Colors.white.withValues(alpha: danger ? 0.04 : 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.w500, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Member info — full readout for another party member's dot. Matches the
// depth of the self-dot "Where am I" sheet (coords, last seen, speed,
// heading, accuracy, altitude) and adds the relative bits that only make
// sense when looking at someone ELSE: range from us and bearing from us.
// ===========================================================================
class _MemberInfoSheet extends StatelessWidget {
  const _MemberInfoSheet({
    required this.member,
    required this.self,
    required this.format,
  });
  final MemberPosition member;
  final MemberPosition? self;
  final CoordFormat format;

  String _agoText(Duration d) {
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) {
      final m = d.inMinutes.remainder(60);
      return '${d.inHours} h ${m == 0 ? '' : '$m m '}ago';
    }
    return '${d.inDays} d ago';
  }

  /// Compass bearing from `from` → `to`, degrees [0, 360).
  double _bearing(LatLng from, LatLng to) {
    const d = Distance();
    return d.bearing(from, to) % 360;
  }

  /// Cardinal label for a degrees bearing, 8-way.
  String _cardinal(double deg) {
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx = ((deg + 22.5) / 45).floor() % 8;
    return labels[idx];
  }

  String _distLabel(double meters) {
    final mi = meters / 1609.344;
    final ft = meters * 3.28084;
    if (mi < 0.1) return '${ft.toStringAsFixed(0)} ft';
    return '${mi.toStringAsFixed(mi < 10 ? 2 : 1)} mi';
  }

  String _altLabel(double m) {
    final ft = m * 3.28084;
    return '${ft.toStringAsFixed(0)} ft (${m.toStringAsFixed(0)} m)';
  }

  Widget _row(String label, String value, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 14, color: valueColor ?? Colors.white)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final m = member;
    final coords =
        formatCoord(m.location.latitude, m.location.longitude, format);
    final ago = _agoText(m.age);
    final stale = m.isStale;
    double? rangeM;
    double? bearingDeg;
    if (self != null) {
      const d = Distance();
      rangeM = d.as(LengthUnit.Meter, self!.location, m.location);
      bearingDeg = _bearing(self!.location, m.location);
    }
    return DraggableScrollableSheet(
      initialChildSize: 0.46,
      minChildSize: 0.22,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1E1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(children: [
              Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  color: _parseHex(m.color),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(m.callsign,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              if (stale)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.warning_amber,
                      color: Colors.amber, size: 18),
                ),
            ]),
            const Divider(height: 22),
            _row('Position', coords),
            _row('Last seen', ago,
                valueColor: stale ? Colors.amber : null),
            if (rangeM != null && bearingDeg != null) ...[
              _row('Range from you', _distLabel(rangeM)),
              _row(
                  'Bearing',
                  '${bearingDeg.toStringAsFixed(0)}° ${_cardinal(bearingDeg)}'),
            ],
            if (m.speed != null && m.speed!.isFinite)
              _row(
                  'Speed',
                  '${(m.speed! * 2.23694).toStringAsFixed(1)} mph '
                      '(${(m.speed!).toStringAsFixed(1)} m/s)'),
            if (m.heading != null &&
                m.heading!.isFinite &&
                m.heading! >= 0)
              _row(
                  'Heading',
                  '${m.heading!.toStringAsFixed(0)}° '
                      '${_cardinal(m.heading!)}'),
            if (m.accuracy != null && m.accuracy!.isFinite)
              _row('GPS accuracy', '±${m.accuracy!.toStringAsFixed(0)} m'),
            if (m.altitude != null && m.altitude!.isFinite)
              _row('Elevation', _altLabel(m.altitude!)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: coords));
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy coords'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Where am I — full readout of self position: coords (in chosen format),
// elevation, GPS accuracy, heading, speed. Re-queries on open for freshness.
// ===========================================================================
class _WhereAmISheet extends StatefulWidget {
  const _WhereAmISheet({required this.member, required this.format});
  final MemberPosition member;
  final CoordFormat format;

  @override
  State<_WhereAmISheet> createState() => _WhereAmISheetState();
}

class _WhereAmISheetState extends State<_WhereAmISheet> {
  Position? _pos;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 4));
      if (mounted) setState(() { _pos = p; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final lat = _pos?.latitude ?? m.location.latitude;
    final lng = _pos?.longitude ?? m.location.longitude;
    final coords = formatCoord(lat, lng, widget.format);
    return DraggableScrollableSheet(
      initialChildSize: 0.46,
      minChildSize: 0.22,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1E1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    color: _parseHex(m.color),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(m.callsign,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                if (_loading)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _CoordRow(label: 'Position', value: coords, copyable: true),
            const SizedBox(height: 10),
            if (_pos != null) ...[
              _CoordRow(
                  label: 'Elevation',
                  value: '${(_pos!.altitude * 3.28084).toStringAsFixed(0)} ft'),
              _CoordRow(
                  label: 'GPS accuracy',
                  value: '±${(_pos!.accuracy * 3.28084).toStringAsFixed(0)} ft'),
              _CoordRow(
                  label: 'Heading',
                  value: _pos!.heading.isNaN || _pos!.heading < 0
                      ? '—'
                      : '${_pos!.heading.toStringAsFixed(0)}°'),
              _CoordRow(
                  label: 'Speed',
                  value: '${(_pos!.speed * 2.23694).toStringAsFixed(1)} mph'),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: coords));
                HapticFeedback.selectionClick();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Coordinates copied'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy position'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordRow extends StatelessWidget {
  const _CoordRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });
  final String label;
  final String value;
  final bool copyable;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
            Expanded(
              child: GestureDetector(
                onTap: copyable
                    ? () {
                        Clipboard.setData(ClipboardData(text: value));
                        HapticFeedback.selectionClick();
                      }
                    : null,
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      );
}

/// Returned by the new-waypoint sheet when the user taps Save.
class _WaypointPickResult {
  const _WaypointPickResult({
    required this.name,
    required this.icon,
    required this.note,
  });
  final String name;
  final RouteWaypointIcon icon;
  final String? note;
}

class _NewWaypointSheet extends StatefulWidget {
  const _NewWaypointSheet();
  @override
  State<_NewWaypointSheet> createState() => _NewWaypointSheetState();
}

class _NewWaypointSheetState extends State<_NewWaypointSheet> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  RouteWaypointIcon _icon = RouteWaypointIcon.flag;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Add waypoint',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: RouteWaypointIcon.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final v = RouteWaypointIcon.values[i];
              final selected = v == _icon;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _icon = v);
                },
                child: Container(
                  width: 56,
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.lightBlueAccent.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? Colors.lightBlueAccent : Colors.white24,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(v.emoji,
                      style: const TextStyle(fontSize: 24)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name (e.g. Water source)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Save waypoint'),
            onPressed: () {
              final name = _name.text.trim();
              if (name.isEmpty) return;
              final note = _note.text.trim();
              Navigator.of(context).pop(_WaypointPickResult(
                name: name,
                icon: _icon,
                note: note.isEmpty ? null : note,
              ));
            },
          ),
        ),
      ]),
    );
  }
}

class _NewPinSheet extends StatefulWidget {
  const _NewPinSheet({required this.onSubmit});
  final Future<void> Function(
      String type, String name, String? note, _PendingPhoto? photo) onSubmit;
  @override
  State<_NewPinSheet> createState() => _NewPinSheetState();
}

class _NewPinSheetState extends State<_NewPinSheet> {
  PinType _type = PinType.waypoint;
  final _name = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  _PendingPhoto? _photo;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto({required ImageSource src}) async {
    try {
      final x = await _picker.pickImage(
          source: src, maxWidth: 2048, imageQuality: 85);
      if (x == null || !mounted) return;
      setState(() => _photo =
          _PendingPhoto(id: const Uuid().v4(), sourcePath: x.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(humanizeError(e))));
      }
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await widget.onSubmit(
          _type.id,
          _name.text.trim().isEmpty ? _type.label : _name.text.trim(),
          _note.text.trim().isEmpty ? null : _note.text.trim(),
          _photo);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(humanizeError(e))));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Drop a pin', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final t in PinType.values)
                ChoiceChip(
                  avatar: Icon(t.icon, size: 18),
                  label: Text(t.label),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name (optional)')),
            const SizedBox(height: 8),
            TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note (optional)')),
            const SizedBox(height: 12),
            // Photo row — thumbnail preview + actions. Photos are private to
            // the device that took them.
            Row(children: [
              if (_photo != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(_photo!.sourcePath),
                      width: 64, height: 64, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 6, children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(_photo == null ? 'Photo' : 'Retake'),
                    onPressed: () => _pickPhoto(src: ImageSource.camera),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                    onPressed: () => _pickPhoto(src: ImageSource.gallery),
                  ),
                  if (_photo != null)
                    TextButton.icon(
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Remove'),
                      onPressed: () => setState(() => _photo = null),
                    ),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Drop pin'),
            ),
          ]),
    );
  }
}

/// Photo selected in the new-pin sheet but not yet committed. Carries the
/// generated client id (UUID) that goes into the pin's encrypted payload AND
/// the source path so the caller can copy the file into PhotoStore after the
/// pin successfully drops.
class _PendingPhoto {
  const _PendingPhoto({required this.id, required this.sourcePath});
  final String id;
  final String sourcePath;
}

// ===========================================================================
// Search sheet
// ===========================================================================
/// A nearby POI lifted from the basemap's `pois` source-layer.
class _NearbyPoi {
  const _NearbyPoi({
    required this.name,
    required this.icon,
    required this.group,
    required this.lng,
    required this.lat,
    required this.meters,
  });
  final String name;
  final String icon;
  final String group;
  final double lng;
  final double lat;
  final double meters;

  factory _NearbyPoi.fromJson(Map<String, dynamic> j) => _NearbyPoi(
        name: j['name'] as String,
        icon: (j['icon'] as String?) ?? '📍',
        group: (j['group'] as String?) ?? 'POI',
        lng: (j['lng'] as num).toDouble(),
        lat: (j['lat'] as num).toDouble(),
        meters: (j['meters'] as num).toDouble(),
      );

  Place toPlace() => Place(name: name, subtitle: group, location: LatLng(lat, lng));

  String get distanceLabel {
    final ft = meters * 3.28084;
    final mi = meters / 1609.344;
    if (mi < 0.1) return '${ft.toStringAsFixed(0)} ft';
    return '${mi.toStringAsFixed(mi < 10 ? 1 : 0)} mi';
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.onSearch, required this.onNearby});
  final Future<List<Place>> Function(String query) onSearch;
  final Future<List<_NearbyPoi>> Function() onNearby;
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  List<Place> _results = const [];
  List<_NearbyPoi> _nearby = const [];
  bool _busy = false;
  bool _loadingNearby = true;

  @override
  void initState() {
    super.initState();
    _loadNearby();
  }

  Future<void> _loadNearby() async {
    final n = await widget.onNearby();
    if (!mounted) return;
    setState(() {
      _nearby = n;
      _loadingNearby = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (q.trim().length < 2) {
        setState(() => _results = const []);
        return;
      }
      setState(() => _busy = true);
      final res = await widget.onSearch(q);
      if (mounted && _ctl.text == q) {
        setState(() {
          _results = res;
          _busy = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _ctl.text.trim().length >= 2;
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _ctl,
          autofocus: true,
          onChanged: (q) {
            setState(() {}); // refresh hasQuery
            _onChanged(q);
          },
          decoration: InputDecoration(
            hintText: 'Town, peak, trailhead…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _busy
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
          child: hasQuery
              ? ListView(shrinkWrap: true, children: [
                  for (final pl in _results)
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(pl.name),
                      subtitle: pl.subtitle.isEmpty ? null : Text(pl.subtitle),
                      onTap: () => Navigator.pop(context, pl),
                    ),
                ])
              : _loadingNearby
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()))
                  : _nearby.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No POIs in this view. Zoom in or pan to a more '
                            'populated area to see places like water, parks, '
                            'and trailheads.',
                            style: TextStyle(color: Colors.white54),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView(shrinkWrap: true, children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                            child: Text('Nearby (${_nearby.length})',
                                style: const TextStyle(color: Colors.white54)),
                          ),
                          for (final p in _nearby)
                            ListTile(
                              dense: true,
                              leading: Text(p.icon,
                                  style: const TextStyle(fontSize: 20)),
                              title: Text(p.name),
                              subtitle: Text('${p.group} · ${p.distanceLabel}'),
                              onTap: () => Navigator.pop(context, p.toPlace()),
                            ),
                        ]),
        ),
      ]),
    );
  }
}

// ===========================================================================
// Trail info sheet — appears when the user taps a rendered path / track
// ===========================================================================

/// Properties + geometry decoded from the JS `trailTap` payload.
class _TrailHitInfo {
  const _TrailHitInfo({
    required this.tap,
    required this.name,
    required this.kind,
    required this.kindDetail,
    required this.surface,
    required this.coords,
  });

  /// Where the user actually tapped (used for the elevation read-out).
  final LatLng tap;

  /// OSM `name` if present, else empty.
  final String name;

  /// Protomaps `kind` (e.g. `path`, `other`).
  final String kind;

  /// Protomaps `kind_detail` (e.g. `track`, `footway`) — present on
  /// pmtiles built with the extended attribute set; falls back to empty
  /// when our extract didn't preserve it.
  final String kindDetail;

  /// OSM `surface` tag (e.g. `gravel`, `dirt`).
  final String surface;

  /// The rendered LineString in [lat,lng] order. Used to sample elevation
  /// and to splice into a draft route.
  final List<LatLng> coords;

  String get displayName => name.isNotEmpty ? name : 'Unnamed trail';

  /// Great-circle length of the rendered segment in meters. Used to give the
  /// info sheet the same distance read-out the route detail screen has.
  double get lengthMeters {
    if (coords.length < 2) return 0;
    const d = Distance();
    double total = 0;
    for (var i = 1; i < coords.length; i++) {
      total += d.as(LengthUnit.Meter, coords[i - 1], coords[i]);
    }
    return total;
  }

  /// Human-readable trail type assembled from the OSM tags we got back.
  /// Falls back to bare "Trail" when we have nothing.
  String get displayKind {
    final parts = <String>[];
    final detail = kindDetail.isNotEmpty ? kindDetail : kind;
    if (detail.isNotEmpty) {
      parts.add(_humaniseKind(detail));
    }
    if (surface.isNotEmpty) parts.add(_humaniseSurface(surface));
    return parts.isEmpty ? 'Trail' : parts.join(' · ');
  }

  static String _humaniseKind(String k) {
    switch (k) {
      case 'path':
      case 'footway':
        return 'Path';
      case 'track':
        return 'Track';
      case 'cycleway':
        return 'Cycleway';
      case 'bridleway':
        return 'Bridleway';
      case 'other':
        return 'Minor road';
      default:
        return k[0].toUpperCase() + k.substring(1).replaceAll('_', ' ');
    }
  }

  static String _humaniseSurface(String s) {
    return s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
  }
}

/// Modal sheet shown on trail-tap. Loads an elevation profile lazily,
/// shows the tap-point elevation alongside the trail's name/kind/surface,
/// and offers an "Add to route" action when the user is mid-design.
class _TrailInfoSheet extends StatefulWidget {
  const _TrailInfoSheet({
    required this.info,
    required this.baseUrl,
    required this.canAddToRoute,
    required this.onAddToRoute,
    this.onAddWholeTrail,
  });

  final _TrailHitInfo info;
  final String baseUrl;
  final bool canAddToRoute;

  /// Append just the visible segment under the user's finger.
  final VoidCallback onAddToRoute;

  /// Append every connected segment that shares this trail's OSM name. Null
  /// when the trail has no name (no way to find related segments).
  final VoidCallback? onAddWholeTrail;

  @override
  State<_TrailInfoSheet> createState() => _TrailInfoSheetState();
}

class _TrailInfoSheetState extends State<_TrailInfoSheet> {
  DemSampler? _sampler;
  double? _tapElevM;
  ElevationStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadElevation();
  }

  Future<void> _loadElevation() async {
    if (widget.baseUrl.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final s = DemSampler(baseUrl: widget.baseUrl);
    _sampler = s;
    final tapEl = await s.elevationAt(widget.info.tap.latitude,
        widget.info.tap.longitude);
    if (!mounted) return;
    setState(() => _tapElevM = tapEl);
    // Profile is optional polish — skip when the trail segment is trivially
    // short (one-segment edges of a tile, etc.).
    if (widget.info.coords.length >= 2) {
      final samples = await s.sampleAlong(widget.info.coords, n: 48);
      if (!mounted) return;
      setState(() {
        _stats = ElevationStats.from(samples);
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _sampler?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    // SafeArea(top: false) gets us the bottom gesture-bar inset that
    // showModalBottomSheet doesn't apply itself. viewInsetsOf still has to
    // be added on top of that to clear the keyboard if it ever shows up
    // here (it shouldn't, but defensive).
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 12,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(children: [
              const Icon(Icons.hiking, color: AppTheme.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  info.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              info.displayKind,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            // Length always shows (it's geometry-only, doesn't wait on the DEM).
            // Ascent / descent fill in once the elevation sample finishes.
            _TrailStatsRow(
              lengthM: info.lengthMeters,
              stats: _stats,
              loadingElev: _loading,
            ),
            if (_tapElevM != null) ...[
              const SizedBox(height: 8),
              Text(
                'Elev. at tap point: ${_fmtFt(_tapElevM!)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            if (widget.canAddToRoute) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.onAddToRoute,
                  icon: const Icon(Icons.add_road),
                  label: const Text('Add segment to route'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.amber,
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
              if (widget.onAddWholeTrail != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onAddWholeTrail,
                    icon: const Icon(Icons.linear_scale),
                    label: Text('Add whole "${info.name}"'),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                widget.onAddWholeTrail != null
                    ? 'Segment = just the part under your finger. Whole = '
                        'every connected piece of this named trail visible '
                        'in the current view.'
                    : 'Splices this visible trail segment into your draft. '
                        'Tap successive trails to chain them.',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtFt(double m) => '${(m * 3.28084).round()} ft';
}

/// Compact stats triplet for the trail sheet — distance always shown, ascent
/// + descent fill in once the elevation sample finishes (shows "…" until
/// then so the row doesn't shift size mid-load).
class _TrailStatsRow extends StatelessWidget {
  const _TrailStatsRow({
    required this.lengthM,
    required this.stats,
    required this.loadingElev,
  });

  final double lengthM;
  final ElevationStats? stats;
  final bool loadingElev;

  static String _fmtMi(double m) {
    final mi = m / 1609.344;
    final ft = m * 3.28084;
    if (mi < 0.1) return '${ft.toStringAsFixed(0)} ft';
    return '${mi.toStringAsFixed(mi < 10 ? 2 : 1)} mi';
  }

  String _ft(double m) => '${(m * 3.28084).round()} ft';

  @override
  Widget build(BuildContext context) {
    final s = stats;
    String ascent;
    String descent;
    if (s != null) {
      ascent = '+${_ft(s.ascentM)}';
      descent = '−${_ft(s.descentM)}';
    } else if (loadingElev) {
      ascent = '…';
      descent = '…';
    } else {
      ascent = '—';
      descent = '—';
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _StatCell(label: 'Length', value: _fmtMi(lengthM)),
        _StatCell(label: 'Ascent', value: ascent),
        _StatCell(label: 'Descent', value: descent),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      ],
    );
  }
}

