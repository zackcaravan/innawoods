// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$notificationServiceHash() =>
    r'585c1e42ea844e71a2b76b80b165adfe2c5c8529';

/// See also [notificationService].
@ProviderFor(notificationService)
final notificationServiceProvider = Provider<NotificationService>.internal(
  notificationService,
  name: r'notificationServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$notificationServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NotificationServiceRef = ProviderRef<NotificationService>;
String _$deadManMonitorHash() => r'3a3772c988a9b3442fab06e523431433b61fd7e5';

/// See also [deadManMonitor].
@ProviderFor(deadManMonitor)
final deadManMonitorProvider = Provider<DeadManMonitor>.internal(
  deadManMonitor,
  name: r'deadManMonitorProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$deadManMonitorHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DeadManMonitorRef = ProviderRef<DeadManMonitor>;
String _$settingsControllerHash() =>
    r'e49245937c19787b454d6539f384e058420e78a4';

/// See also [SettingsController].
@ProviderFor(SettingsController)
final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>.internal(
      SettingsController.new,
      name: r'settingsControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$settingsControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SettingsController = AsyncNotifier<AppSettings>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
