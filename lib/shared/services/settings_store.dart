import 'package:shared_preferences/shared_preferences.dart';

import 'coord_format.dart';

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
  }
}
