import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/models/track.dart';
import '../../../shared/services/track_recorder.dart';
import '../../../shared/services/track_store.dart';

part 'tracks_provider.g.dart';

@Riverpod(keepAlive: true)
TrackStore trackStore(Ref ref) => TrackStore();

@Riverpod(keepAlive: true)
TrackRecorder trackRecorder(Ref ref) =>
    TrackRecorder(ref.watch(trackStoreProvider));

/// In-flight recording state (null when idle). Updates as new points stream in.
/// Yields the recorder's *current* state immediately on subscribe so listeners
/// joining mid-recording (e.g. the map screen re-entered while a track is
/// active) don't have to wait for the next point to learn it's recording.
@riverpod
Stream<TrackInProgress?> activeRecording(Ref ref) async* {
  final r = ref.watch(trackRecorderProvider);
  yield r.current;
  yield* r.stream;
}

/// Saved tracks from disk. Refreshable after save/delete.
@riverpod
Future<List<Track>> savedTracks(Ref ref) =>
    ref.watch(trackStoreProvider).list();
