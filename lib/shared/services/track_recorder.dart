// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../models/track.dart';
import 'track_store.dart';

/// In-flight recording state — what the UI listens to.
@immutable
class TrackInProgress {
  const TrackInProgress({
    required this.id,
    required this.startedAt,
    required this.points,
    required this.paused,
  });
  final String id;
  final DateTime startedAt;
  final List<TrackPoint> points;
  final bool paused;

  Duration get duration => DateTime.now().difference(startedAt);

  double get distanceMeters {
    if (points.length < 2) return 0;
    const d = Distance();
    double total = 0;
    for (var i = 1; i < points.length; i++) {
      total += d.as(LengthUnit.Meter, points[i - 1].latLng, points[i].latLng);
    }
    return total;
  }

  TrackInProgress copyWith({List<TrackPoint>? points, bool? paused}) =>
      TrackInProgress(
        id: id,
        startedAt: startedAt,
        points: points ?? this.points,
        paused: paused ?? this.paused,
      );
}

/// Records a breadcrumb track from the device's location stream.
///
/// Lifecycle: idle → start() → recording → pause()/resume() → stop() → saved.
/// Filters jitter (skips points <5 m from the last one) so a still device
/// doesn't accumulate fake distance from GPS wander.
class TrackRecorder {
  TrackRecorder(this._store);

  final TrackStore _store;
  final _ctl = StreamController<TrackInProgress?>.broadcast();
  StreamSubscription<Position>? _sub;
  TrackInProgress? _state;

  Stream<TrackInProgress?> get stream => _ctl.stream;
  TrackInProgress? get current => _state;

  Future<void> start() async {
    if (_state != null) return; // already going
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      final asked = await Geolocator.requestPermission();
      if (asked == LocationPermission.denied ||
          asked == LocationPermission.deniedForever) {
        throw StateError('Location permission required to record a track');
      }
    }
    _state = TrackInProgress(
      id: const Uuid().v4(),
      startedAt: DateTime.now(),
      points: const [],
      paused: false,
    );
    _ctl.add(_state);
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 4, // meters
      ),
    ).listen((pos) {
      final s = _state;
      if (s == null || s.paused) return;
      // Extra jitter guard on top of distanceFilter.
      if (s.points.isNotEmpty) {
        const d = Distance();
        final last = s.points.last.latLng;
        final delta = d.as(
            LengthUnit.Meter, last, LatLng(pos.latitude, pos.longitude));
        if (delta < 3) return;
      }
      final next = [
        ...s.points,
        TrackPoint(
          lat: pos.latitude,
          lng: pos.longitude,
          alt: pos.altitude,
          t: DateTime.now(),
        ),
      ];
      _state = s.copyWith(points: next);
      _ctl.add(_state);
    });
  }

  void pause() {
    final s = _state;
    if (s == null || s.paused) return;
    _state = s.copyWith(paused: true);
    _ctl.add(_state);
  }

  void resume() {
    final s = _state;
    if (s == null || !s.paused) return;
    _state = s.copyWith(paused: false);
    _ctl.add(_state);
  }

  /// Finalize the recording. Saves a [Track] under [name] (or a default
  /// timestamped name) and returns it. State returns to idle.
  Future<Track?> stop({String? name}) async {
    final s = _state;
    if (s == null) return null;
    await _sub?.cancel();
    _sub = null;
    final endedAt = DateTime.now();
    final track = Track(
      id: s.id,
      name: name ?? _defaultName(s.startedAt),
      startedAt: s.startedAt,
      endedAt: endedAt,
      points: s.points,
    );
    if (track.points.isNotEmpty) {
      await _store.save(track);
    }
    _state = null;
    _ctl.add(null);
    return track.points.isEmpty ? null : track;
  }

  /// Drop the current recording without saving it.
  Future<void> discard() async {
    await _sub?.cancel();
    _sub = null;
    _state = null;
    _ctl.add(null);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _ctl.close();
  }

  String _defaultName(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Track ${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}

