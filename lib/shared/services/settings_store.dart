// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:shared_preferences/shared_preferences.dart';

import 'coord_format.dart';

/// Which trail-style filter the map is currently showing. Used to mute
/// motorised ways when you're hiking and the other way around.
///
/// `all` is the default and renders every classified path/track. The other
/// modes hide the irrelevant layer (`orv` hides hike paths, `hike` hides
/// motorised tracks). Major roads, bridges, and tunnels stay visible in
/// every mode — you always want to see where the highway is.
///
/// Filtering accuracy depends on which OSM attributes the active region's
/// pmtiles preserved. Today's extract only keeps `kind` ∈ {path, other},
/// which catches most cases but isn't surface-aware; a future rebuild
/// (`kind_detail` + `surface`) will tighten this.
enum MapActivity {
  all('all', 'All trails'),
  hike('hike', 'Hike only'),
  orv('orv', 'ORV / track only');

  const MapActivity(this.id, this.label);
  final String id;
  final String label;

  static MapActivity fromId(String? id) =>
      MapActivity.values.firstWhere((a) => a.id == id, orElse: () => all);
}

/// User-tunable settings (battery + safety). Persisted locally.
class AppSettings {
  const AppSettings({
    this.locationIntervalSeconds = 30,
    this.deadManEnabled = false,
    this.deadManMinutes = 10,
    this.terrainExaggeration = 1.2,
    this.coordFormat = CoordFormat.latLonDecimal,
    this.nightMode = false,
    this.headingUp = false,
    this.tripMode = false,
    this.offRoadStyle = false,
    this.autoHeadingUp = true,
    this.searchLimitToRegion = false,
    this.mapActivity = MapActivity.all,
  });

  /// How often to publish your position. 30 s default; up to 5 min to save battery.
  final int locationIntervalSeconds;

  /// Alert the crew (locally) when a member goes silent.
  final bool deadManEnabled;

  /// Silence threshold for the dead-man's switch, in minutes.
  final int deadManMinutes;

  /// 3D terrain height multiplier. 1.0 ≈ true-to-life; higher = more dramatic.
  final double terrainExaggeration;

  /// How coordinates are displayed (lat/lon decimal, DMS, MGRS, UTM).
  final CoordFormat coordFormat;

  /// Red-filter overlay for headlamp / night-vision-preserving use.
  final bool nightMode;

  /// Rotate the map so the user's travel direction is "up". Compass FAB
  /// double-tap also toggles this; single-tap still snaps the camera to north.
  final bool headingUp;

  /// Battery-saver mode for long trips. Forces a slower location publish
  /// cadence (90 s) regardless of [locationIntervalSeconds]; shows a "TRIP"
  /// badge on the map.
  final bool tripMode;

  /// Re-styles the basemap for off-road readability — narrower muted highways,
  /// bolder trails, stronger hillshade. Reversible.
  final bool offRoadStyle;

  /// Automatically flips into heading-up mode while moving at ≥ 4 mph so the
  /// map rotates to your travel direction. Returns to north-up when you stop.
  /// Off → heading-up is a manual toggle only (compass double-tap).
  final bool autoHeadingUp;

  /// When true, place-search results are hard-filtered to the active
  /// region's bounding box. Default false — the geocoder still biases by
  /// camera center, but distant matches can rank in. Useful for "I'm only
  /// going to be in WA, stop showing me Salmon Creek in Maine."
  final bool searchLimitToRegion;

  /// Trail-style filter — see [MapActivity]. Default `all` (no filter).
  final MapActivity mapActivity;

  /// Effective location-publish interval (in seconds) accounting for trip mode.
  int get effectiveLocationIntervalSeconds =>
      tripMode ? 90 : locationIntervalSeconds;

  AppSettings copyWith({
    int? locationIntervalSeconds,
    bool? deadManEnabled,
    int? deadManMinutes,
    double? terrainExaggeration,
    CoordFormat? coordFormat,
    bool? nightMode,
    bool? headingUp,
    bool? tripMode,
    bool? offRoadStyle,
    bool? autoHeadingUp,
    bool? searchLimitToRegion,
    MapActivity? mapActivity,
  }) =>
      AppSettings(
        locationIntervalSeconds:
            locationIntervalSeconds ?? this.locationIntervalSeconds,
        deadManEnabled: deadManEnabled ?? this.deadManEnabled,
        deadManMinutes: deadManMinutes ?? this.deadManMinutes,
        terrainExaggeration: terrainExaggeration ?? this.terrainExaggeration,
        coordFormat: coordFormat ?? this.coordFormat,
        nightMode: nightMode ?? this.nightMode,
        headingUp: headingUp ?? this.headingUp,
        tripMode: tripMode ?? this.tripMode,
        offRoadStyle: offRoadStyle ?? this.offRoadStyle,
        autoHeadingUp: autoHeadingUp ?? this.autoHeadingUp,
        searchLimitToRegion: searchLimitToRegion ?? this.searchLimitToRegion,
        mapActivity: mapActivity ?? this.mapActivity,
      );
}

class SettingsStore {
  static const _kInterval = 'innawoods.settings.locInterval';
  static const _kDeadEnabled = 'innawoods.settings.deadEnabled';
  static const _kDeadMinutes = 'innawoods.settings.deadMinutes';
  static const _kTerrainExag = 'innawoods.settings.terrainExag';
  static const _kCoordFormat = 'innawoods.settings.coordFormat';
  static const _kNightMode = 'innawoods.settings.nightMode';
  static const _kHeadingUp = 'innawoods.settings.headingUp';
  static const _kTripMode = 'innawoods.settings.tripMode';
  static const _kOffRoadStyle = 'innawoods.settings.offRoadStyle';
  static const _kAutoHeadingUp = 'innawoods.settings.autoHeadingUp';
  static const _kSearchLimit = 'innawoods.settings.searchLimitToRegion';
  static const _kMapActivity = 'innawoods.settings.mapActivity';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      locationIntervalSeconds: prefs.getInt(_kInterval) ?? 30,
      deadManEnabled: prefs.getBool(_kDeadEnabled) ?? false,
      deadManMinutes: prefs.getInt(_kDeadMinutes) ?? 10,
      terrainExaggeration: prefs.getDouble(_kTerrainExag) ?? 1.2,
      coordFormat: CoordFormatLabel.fromId(
          prefs.getString(_kCoordFormat) ?? CoordFormat.latLonDecimal.id),
      nightMode: prefs.getBool(_kNightMode) ?? false,
      headingUp: prefs.getBool(_kHeadingUp) ?? false,
      tripMode: prefs.getBool(_kTripMode) ?? false,
      offRoadStyle: prefs.getBool(_kOffRoadStyle) ?? false,
      autoHeadingUp: prefs.getBool(_kAutoHeadingUp) ?? true,
      searchLimitToRegion: prefs.getBool(_kSearchLimit) ?? false,
      mapActivity: MapActivity.fromId(prefs.getString(_kMapActivity)),
    );
  }

  Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kInterval, s.locationIntervalSeconds);
    await prefs.setBool(_kDeadEnabled, s.deadManEnabled);
    await prefs.setInt(_kDeadMinutes, s.deadManMinutes);
    await prefs.setDouble(_kTerrainExag, s.terrainExaggeration);
    await prefs.setString(_kCoordFormat, s.coordFormat.id);
    await prefs.setBool(_kNightMode, s.nightMode);
    await prefs.setBool(_kHeadingUp, s.headingUp);
    await prefs.setBool(_kTripMode, s.tripMode);
    await prefs.setBool(_kOffRoadStyle, s.offRoadStyle);
    await prefs.setBool(_kAutoHeadingUp, s.autoHeadingUp);
    await prefs.setBool(_kSearchLimit, s.searchLimitToRegion);
    await prefs.setString(_kMapActivity, s.mapActivity.id);
  }
}
