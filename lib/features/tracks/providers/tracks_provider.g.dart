// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tracks_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$trackStoreHash() => r'ee6b6fa3e9afa6209a60b8a8b1ae87686e353c78';

/// See also [trackStore].
@ProviderFor(trackStore)
final trackStoreProvider = Provider<TrackStore>.internal(
  trackStore,
  name: r'trackStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$trackStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TrackStoreRef = ProviderRef<TrackStore>;
String _$trackRecorderHash() => r'32704d415fdf437894e9c0aba1ee9570f69789bb';

/// See also [trackRecorder].
@ProviderFor(trackRecorder)
final trackRecorderProvider = Provider<TrackRecorder>.internal(
  trackRecorder,
  name: r'trackRecorderProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$trackRecorderHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TrackRecorderRef = ProviderRef<TrackRecorder>;
String _$activeRecordingHash() => r'e75d2f043c642e2219fd30783778ef7b0bf0a91d';

/// In-flight recording state (null when idle). Updates as new points stream in.
/// Yields the recorder's *current* state immediately on subscribe so listeners
/// joining mid-recording (e.g. the map screen re-entered while a track is
/// active) don't have to wait for the next point to learn it's recording.
///
/// Copied from [activeRecording].
@ProviderFor(activeRecording)
final activeRecordingProvider =
    AutoDisposeStreamProvider<TrackInProgress?>.internal(
      activeRecording,
      name: r'activeRecordingProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$activeRecordingHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ActiveRecordingRef = AutoDisposeStreamProviderRef<TrackInProgress?>;
String _$savedTracksHash() => r'05a4c8dbe5f24f0adc86236882744d106d291d97';

/// Saved tracks from disk. Refreshable after save/delete.
///
/// Copied from [savedTracks].
@ProviderFor(savedTracks)
final savedTracksProvider = AutoDisposeFutureProvider<List<Track>>.internal(
  savedTracks,
  name: r'savedTracksProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$savedTracksHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SavedTracksRef = AutoDisposeFutureProviderRef<List<Track>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
