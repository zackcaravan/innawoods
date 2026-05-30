// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'maps_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$regionCatalogHash() => r'ab033dd900dec7c3f08f4fbe6f8c790c167cdc7b';

/// See also [regionCatalog].
@ProviderFor(regionCatalog)
final regionCatalogProvider = Provider<RegionCatalog>.internal(
  regionCatalog,
  name: r'regionCatalogProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$regionCatalogHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RegionCatalogRef = ProviderRef<RegionCatalog>;
String _$regionStoreHash() => r'0fa135578e8630590d1fb7c519a22bc45ff7d3b4';

/// See also [regionStore].
@ProviderFor(regionStore)
final regionStoreProvider = Provider<RegionStore>.internal(
  regionStore,
  name: r'regionStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$regionStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RegionStoreRef = ProviderRef<RegionStore>;
String _$activeRegionHash() => r'cf30c95d9617a0f27c3606f5877748ea211f097c';

/// Which region the map currently reads from (null = none downloaded yet).
///
/// Copied from [ActiveRegion].
@ProviderFor(ActiveRegion)
final activeRegionProvider =
    AutoDisposeAsyncNotifierProvider<ActiveRegion, String?>.internal(
      ActiveRegion.new,
      name: r'activeRegionProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$activeRegionHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ActiveRegion = AutoDisposeAsyncNotifier<String?>;
String _$downloadedRegionsHash() => r'6e46019f09f1e244587e98e98b9a0df56cec7916';

/// Filesystem-truth list of downloaded region ids.
///
/// Copied from [DownloadedRegions].
@ProviderFor(DownloadedRegions)
final downloadedRegionsProvider =
    AutoDisposeAsyncNotifierProvider<DownloadedRegions, List<String>>.internal(
      DownloadedRegions.new,
      name: r'downloadedRegionsProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$downloadedRegionsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$DownloadedRegions = AutoDisposeAsyncNotifier<List<String>>;
String _$regionDownloadControllerHash() =>
    r'9332ba063c3c3d788163535c33ca4bc2a7b1aa49';

/// In-flight downloads keyed by region id. Pauses/cancellation just drop the
/// stream; the downloader cleans up its `.part` file on error.
///
/// Copied from [RegionDownloadController].
@ProviderFor(RegionDownloadController)
final regionDownloadControllerProvider =
    NotifierProvider<
      RegionDownloadController,
      Map<String, RegionDownloadProgress>
    >.internal(
      RegionDownloadController.new,
      name: r'regionDownloadControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$regionDownloadControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$RegionDownloadController =
    Notifier<Map<String, RegionDownloadProgress>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
