// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'party_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$partySecretStoreHash() => r'dc3192873e773d5f1626a5f6a363886b1f48b76f';

/// See also [partySecretStore].
@ProviderFor(partySecretStore)
final partySecretStoreProvider = AutoDisposeProvider<PartySecretStore>.internal(
  partySecretStore,
  name: r'partySecretStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$partySecretStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PartySecretStoreRef = AutoDisposeProviderRef<PartySecretStore>;
String _$cryptoSessionHash() => r'62809abdad6f997b0901d66a1c27966b73598ffa';

/// See also [cryptoSession].
@ProviderFor(cryptoSession)
final cryptoSessionProvider = AutoDisposeProvider<CryptoSession>.internal(
  cryptoSession,
  name: r'cryptoSessionProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$cryptoSessionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CryptoSessionRef = AutoDisposeProviderRef<CryptoSession>;
String _$partyServiceHash() => r'81980ecae3c3ca65f413a987cc4fb4dead3eb4e5';

/// See also [partyService].
@ProviderFor(partyService)
final partyServiceProvider = AutoDisposeProvider<PartyService>.internal(
  partyService,
  name: r'partyServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$partyServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PartyServiceRef = AutoDisposeProviderRef<PartyService>;
String _$myPartiesHash() => r'f4616abf1f38596c3468e3f1a799f0ad2250ccca';

/// Parties the current user belongs to (newest first).
///
/// Copied from [myParties].
@ProviderFor(myParties)
final myPartiesProvider = AutoDisposeFutureProvider<List<Party>>.internal(
  myParties,
  name: r'myPartiesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$myPartiesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MyPartiesRef = AutoDisposeFutureProviderRef<List<Party>>;
String _$partyMembersHash() => r'bb287282dddbf77a472b7fc0a039d73b44e5b3c3';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// Live-ish roster for a party. Refresh-on-demand for now; Phase 3 wires
/// realtime so the roster and dots update without a manual refresh.
///
/// Copied from [partyMembers].
@ProviderFor(partyMembers)
const partyMembersProvider = PartyMembersFamily();

/// Live-ish roster for a party. Refresh-on-demand for now; Phase 3 wires
/// realtime so the roster and dots update without a manual refresh.
///
/// Copied from [partyMembers].
class PartyMembersFamily extends Family<AsyncValue<List<PartyMember>>> {
  /// Live-ish roster for a party. Refresh-on-demand for now; Phase 3 wires
  /// realtime so the roster and dots update without a manual refresh.
  ///
  /// Copied from [partyMembers].
  const PartyMembersFamily();

  /// Live-ish roster for a party. Refresh-on-demand for now; Phase 3 wires
  /// realtime so the roster and dots update without a manual refresh.
  ///
  /// Copied from [partyMembers].
  PartyMembersProvider call(String partyId) {
    return PartyMembersProvider(partyId);
  }

  @override
  PartyMembersProvider getProviderOverride(
    covariant PartyMembersProvider provider,
  ) {
    return call(provider.partyId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'partyMembersProvider';
}

/// Live-ish roster for a party. Refresh-on-demand for now; Phase 3 wires
/// realtime so the roster and dots update without a manual refresh.
///
/// Copied from [partyMembers].
class PartyMembersProvider
    extends AutoDisposeFutureProvider<List<PartyMember>> {
  /// Live-ish roster for a party. Refresh-on-demand for now; Phase 3 wires
  /// realtime so the roster and dots update without a manual refresh.
  ///
  /// Copied from [partyMembers].
  PartyMembersProvider(String partyId)
    : this._internal(
        (ref) => partyMembers(ref as PartyMembersRef, partyId),
        from: partyMembersProvider,
        name: r'partyMembersProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$partyMembersHash,
        dependencies: PartyMembersFamily._dependencies,
        allTransitiveDependencies:
            PartyMembersFamily._allTransitiveDependencies,
        partyId: partyId,
      );

  PartyMembersProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.partyId,
  }) : super.internal();

  final String partyId;

  @override
  Override overrideWith(
    FutureOr<List<PartyMember>> Function(PartyMembersRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PartyMembersProvider._internal(
        (ref) => create(ref as PartyMembersRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        partyId: partyId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<PartyMember>> createElement() {
    return _PartyMembersProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PartyMembersProvider && other.partyId == partyId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, partyId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PartyMembersRef on AutoDisposeFutureProviderRef<List<PartyMember>> {
  /// The parameter `partyId` of this provider.
  String get partyId;
}

class _PartyMembersProviderElement
    extends AutoDisposeFutureProviderElement<List<PartyMember>>
    with PartyMembersRef {
  _PartyMembersProviderElement(super.provider);

  @override
  String get partyId => (origin as PartyMembersProvider).partyId;
}

String _$partyByIdHash() => r'f1d7b2614a26a6de0a381203669eaef1d6dbd921';

/// See also [partyById].
@ProviderFor(partyById)
const partyByIdProvider = PartyByIdFamily();

/// See also [partyById].
class PartyByIdFamily extends Family<AsyncValue<Party?>> {
  /// See also [partyById].
  const PartyByIdFamily();

  /// See also [partyById].
  PartyByIdProvider call(String partyId) {
    return PartyByIdProvider(partyId);
  }

  @override
  PartyByIdProvider getProviderOverride(covariant PartyByIdProvider provider) {
    return call(provider.partyId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'partyByIdProvider';
}

/// See also [partyById].
class PartyByIdProvider extends AutoDisposeFutureProvider<Party?> {
  /// See also [partyById].
  PartyByIdProvider(String partyId)
    : this._internal(
        (ref) => partyById(ref as PartyByIdRef, partyId),
        from: partyByIdProvider,
        name: r'partyByIdProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$partyByIdHash,
        dependencies: PartyByIdFamily._dependencies,
        allTransitiveDependencies: PartyByIdFamily._allTransitiveDependencies,
        partyId: partyId,
      );

  PartyByIdProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.partyId,
  }) : super.internal();

  final String partyId;

  @override
  Override overrideWith(
    FutureOr<Party?> Function(PartyByIdRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PartyByIdProvider._internal(
        (ref) => create(ref as PartyByIdRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        partyId: partyId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<Party?> createElement() {
    return _PartyByIdProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PartyByIdProvider && other.partyId == partyId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, partyId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PartyByIdRef on AutoDisposeFutureProviderRef<Party?> {
  /// The parameter `partyId` of this provider.
  String get partyId;
}

class _PartyByIdProviderElement extends AutoDisposeFutureProviderElement<Party?>
    with PartyByIdRef {
  _PartyByIdProviderElement(super.provider);

  @override
  String get partyId => (origin as PartyByIdProvider).partyId;
}

String _$locationPublisherHash() => r'3b0d3c0058af2a31e4c282ba0db28a4f5bbde5c7';

/// See also [locationPublisher].
@ProviderFor(locationPublisher)
final locationPublisherProvider =
    AutoDisposeProvider<LocationPublisher>.internal(
      locationPublisher,
      name: r'locationPublisherProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$locationPublisherHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LocationPublisherRef = AutoDisposeProviderRef<LocationPublisher>;
String _$partyLiveServiceHash() => r'cc61692236a6b3a23ac5ffe45d1910644c5d0558';

/// See also [partyLiveService].
@ProviderFor(partyLiveService)
final partyLiveServiceProvider = AutoDisposeProvider<PartyLiveService>.internal(
  partyLiveService,
  name: r'partyLiveServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$partyLiveServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PartyLiveServiceRef = AutoDisposeProviderRef<PartyLiveService>;
String _$partyLiveHash() => r'd19f2e97b4b203cbc2604eae1118e121cc5f4f87';

/// Live decrypted member positions for a party (realtime).
///
/// Copied from [partyLive].
@ProviderFor(partyLive)
const partyLiveProvider = PartyLiveFamily();

/// Live decrypted member positions for a party (realtime).
///
/// Copied from [partyLive].
class PartyLiveFamily extends Family<AsyncValue<List<MemberPosition>>> {
  /// Live decrypted member positions for a party (realtime).
  ///
  /// Copied from [partyLive].
  const PartyLiveFamily();

  /// Live decrypted member positions for a party (realtime).
  ///
  /// Copied from [partyLive].
  PartyLiveProvider call(String partyId) {
    return PartyLiveProvider(partyId);
  }

  @override
  PartyLiveProvider getProviderOverride(covariant PartyLiveProvider provider) {
    return call(provider.partyId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'partyLiveProvider';
}

/// Live decrypted member positions for a party (realtime).
///
/// Copied from [partyLive].
class PartyLiveProvider
    extends AutoDisposeStreamProvider<List<MemberPosition>> {
  /// Live decrypted member positions for a party (realtime).
  ///
  /// Copied from [partyLive].
  PartyLiveProvider(String partyId)
    : this._internal(
        (ref) => partyLive(ref as PartyLiveRef, partyId),
        from: partyLiveProvider,
        name: r'partyLiveProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$partyLiveHash,
        dependencies: PartyLiveFamily._dependencies,
        allTransitiveDependencies: PartyLiveFamily._allTransitiveDependencies,
        partyId: partyId,
      );

  PartyLiveProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.partyId,
  }) : super.internal();

  final String partyId;

  @override
  Override overrideWith(
    Stream<List<MemberPosition>> Function(PartyLiveRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PartyLiveProvider._internal(
        (ref) => create(ref as PartyLiveRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        partyId: partyId,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<List<MemberPosition>> createElement() {
    return _PartyLiveProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PartyLiveProvider && other.partyId == partyId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, partyId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PartyLiveRef on AutoDisposeStreamProviderRef<List<MemberPosition>> {
  /// The parameter `partyId` of this provider.
  String get partyId;
}

class _PartyLiveProviderElement
    extends AutoDisposeStreamProviderElement<List<MemberPosition>>
    with PartyLiveRef {
  _PartyLiveProviderElement(super.provider);

  @override
  String get partyId => (origin as PartyLiveProvider).partyId;
}

String _$gpxServiceHash() => r'04afacddef4fc2c480b550db3a9b5d680cf265bd';

/// See also [gpxService].
@ProviderFor(gpxService)
final gpxServiceProvider = AutoDisposeProvider<GpxService>.internal(
  gpxService,
  name: r'gpxServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$gpxServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GpxServiceRef = AutoDisposeProviderRef<GpxService>;
String _$geocoderServiceHash() => r'a76f59b20d595bafcee17a044c2215baf2fa7cfe';

/// See also [geocoderService].
@ProviderFor(geocoderService)
final geocoderServiceProvider = AutoDisposeProvider<GeocoderService>.internal(
  geocoderService,
  name: r'geocoderServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$geocoderServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GeocoderServiceRef = AutoDisposeProviderRef<GeocoderService>;
String _$routingServiceHash() => r'253b3c65aaa5e8162fe1fde4ab412dd798c21191';

/// See also [routingService].
@ProviderFor(routingService)
final routingServiceProvider = AutoDisposeProvider<RoutingService>.internal(
  routingService,
  name: r'routingServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$routingServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RoutingServiceRef = AutoDisposeProviderRef<RoutingService>;
String _$photoStoreHash() => r'4083719da1fa98dc2d1027f86dbe8c449fa73dd6';

/// See also [photoStore].
@ProviderFor(photoStore)
final photoStoreProvider = Provider<PhotoStore>.internal(
  photoStore,
  name: r'photoStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$photoStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PhotoStoreRef = ProviderRef<PhotoStore>;
String _$maydayDismissalStoreHash() =>
    r'ec21bfe6457c7e4a86bf83f0e07ab977bd6a2ce0';

/// Persists which inbound maydays this device has already alerted on,
/// keyed by message id. Used to silence repeat pops when the user
/// navigates away and back.
///
/// Copied from [maydayDismissalStore].
@ProviderFor(maydayDismissalStore)
final maydayDismissalStoreProvider = Provider<MaydayDismissalStore>.internal(
  maydayDismissalStore,
  name: r'maydayDismissalStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$maydayDismissalStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MaydayDismissalStoreRef = ProviderRef<MaydayDismissalStore>;
String _$pinServiceHash() => r'3b3c5ee5abb9b66359ad9b884d594486aa50fdc1';

/// See also [pinService].
@ProviderFor(pinService)
final pinServiceProvider = AutoDisposeProvider<PinService>.internal(
  pinService,
  name: r'pinServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$pinServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PinServiceRef = AutoDisposeProviderRef<PinService>;
String _$partyPinsHash() => r'cb12bfcfa638b0075f92a40bc57c2cd44ae77ea7';

/// Live decrypted pins for a party (realtime).
///
/// Copied from [partyPins].
@ProviderFor(partyPins)
const partyPinsProvider = PartyPinsFamily();

/// Live decrypted pins for a party (realtime).
///
/// Copied from [partyPins].
class PartyPinsFamily extends Family<AsyncValue<List<MapPin>>> {
  /// Live decrypted pins for a party (realtime).
  ///
  /// Copied from [partyPins].
  const PartyPinsFamily();

  /// Live decrypted pins for a party (realtime).
  ///
  /// Copied from [partyPins].
  PartyPinsProvider call(String partyId) {
    return PartyPinsProvider(partyId);
  }

  @override
  PartyPinsProvider getProviderOverride(covariant PartyPinsProvider provider) {
    return call(provider.partyId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'partyPinsProvider';
}

/// Live decrypted pins for a party (realtime).
///
/// Copied from [partyPins].
class PartyPinsProvider extends AutoDisposeStreamProvider<List<MapPin>> {
  /// Live decrypted pins for a party (realtime).
  ///
  /// Copied from [partyPins].
  PartyPinsProvider(String partyId)
    : this._internal(
        (ref) => partyPins(ref as PartyPinsRef, partyId),
        from: partyPinsProvider,
        name: r'partyPinsProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$partyPinsHash,
        dependencies: PartyPinsFamily._dependencies,
        allTransitiveDependencies: PartyPinsFamily._allTransitiveDependencies,
        partyId: partyId,
      );

  PartyPinsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.partyId,
  }) : super.internal();

  final String partyId;

  @override
  Override overrideWith(
    Stream<List<MapPin>> Function(PartyPinsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PartyPinsProvider._internal(
        (ref) => create(ref as PartyPinsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        partyId: partyId,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<List<MapPin>> createElement() {
    return _PartyPinsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PartyPinsProvider && other.partyId == partyId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, partyId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PartyPinsRef on AutoDisposeStreamProviderRef<List<MapPin>> {
  /// The parameter `partyId` of this provider.
  String get partyId;
}

class _PartyPinsProviderElement
    extends AutoDisposeStreamProviderElement<List<MapPin>>
    with PartyPinsRef {
  _PartyPinsProviderElement(super.provider);

  @override
  String get partyId => (origin as PartyPinsProvider).partyId;
}

String _$routeServiceHash() => r'f69ea465978dc3e28f78f455ac540edbcd4047c3';

/// See also [routeService].
@ProviderFor(routeService)
final routeServiceProvider = AutoDisposeProvider<RouteService>.internal(
  routeService,
  name: r'routeServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$routeServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RouteServiceRef = AutoDisposeProviderRef<RouteService>;
String _$partyRoutesHash() => r'6bc695c67053661179b3ac128a4834304a7dba0e';

/// Live decrypted shared routes for a party (realtime).
///
/// Copied from [partyRoutes].
@ProviderFor(partyRoutes)
const partyRoutesProvider = PartyRoutesFamily();

/// Live decrypted shared routes for a party (realtime).
///
/// Copied from [partyRoutes].
class PartyRoutesFamily extends Family<AsyncValue<List<MapRoute>>> {
  /// Live decrypted shared routes for a party (realtime).
  ///
  /// Copied from [partyRoutes].
  const PartyRoutesFamily();

  /// Live decrypted shared routes for a party (realtime).
  ///
  /// Copied from [partyRoutes].
  PartyRoutesProvider call(String partyId) {
    return PartyRoutesProvider(partyId);
  }

  @override
  PartyRoutesProvider getProviderOverride(
    covariant PartyRoutesProvider provider,
  ) {
    return call(provider.partyId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'partyRoutesProvider';
}

/// Live decrypted shared routes for a party (realtime).
///
/// Copied from [partyRoutes].
class PartyRoutesProvider extends AutoDisposeStreamProvider<List<MapRoute>> {
  /// Live decrypted shared routes for a party (realtime).
  ///
  /// Copied from [partyRoutes].
  PartyRoutesProvider(String partyId)
    : this._internal(
        (ref) => partyRoutes(ref as PartyRoutesRef, partyId),
        from: partyRoutesProvider,
        name: r'partyRoutesProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$partyRoutesHash,
        dependencies: PartyRoutesFamily._dependencies,
        allTransitiveDependencies: PartyRoutesFamily._allTransitiveDependencies,
        partyId: partyId,
      );

  PartyRoutesProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.partyId,
  }) : super.internal();

  final String partyId;

  @override
  Override overrideWith(
    Stream<List<MapRoute>> Function(PartyRoutesRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PartyRoutesProvider._internal(
        (ref) => create(ref as PartyRoutesRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        partyId: partyId,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<List<MapRoute>> createElement() {
    return _PartyRoutesProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PartyRoutesProvider && other.partyId == partyId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, partyId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PartyRoutesRef on AutoDisposeStreamProviderRef<List<MapRoute>> {
  /// The parameter `partyId` of this provider.
  String get partyId;
}

class _PartyRoutesProviderElement
    extends AutoDisposeStreamProviderElement<List<MapRoute>>
    with PartyRoutesRef {
  _PartyRoutesProviderElement(super.provider);

  @override
  String get partyId => (origin as PartyRoutesProvider).partyId;
}

String _$routeWaypointServiceHash() =>
    r'c7597b18cd7508bb826cd6d7bf66cf998689dbee';

/// See also [routeWaypointService].
@ProviderFor(routeWaypointService)
final routeWaypointServiceProvider =
    AutoDisposeProvider<RouteWaypointService>.internal(
      routeWaypointService,
      name: r'routeWaypointServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$routeWaypointServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RouteWaypointServiceRef = AutoDisposeProviderRef<RouteWaypointService>;
String _$partyRouteWaypointsHash() =>
    r'f8ccf58c6544f50f95550afd662216a039f4ed06';

/// Live decrypted waypoints (across all routes) for a party.
///
/// Copied from [partyRouteWaypoints].
@ProviderFor(partyRouteWaypoints)
const partyRouteWaypointsProvider = PartyRouteWaypointsFamily();

/// Live decrypted waypoints (across all routes) for a party.
///
/// Copied from [partyRouteWaypoints].
class PartyRouteWaypointsFamily
    extends Family<AsyncValue<List<RouteWaypoint>>> {
  /// Live decrypted waypoints (across all routes) for a party.
  ///
  /// Copied from [partyRouteWaypoints].
  const PartyRouteWaypointsFamily();

  /// Live decrypted waypoints (across all routes) for a party.
  ///
  /// Copied from [partyRouteWaypoints].
  PartyRouteWaypointsProvider call(String partyId) {
    return PartyRouteWaypointsProvider(partyId);
  }

  @override
  PartyRouteWaypointsProvider getProviderOverride(
    covariant PartyRouteWaypointsProvider provider,
  ) {
    return call(provider.partyId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'partyRouteWaypointsProvider';
}

/// Live decrypted waypoints (across all routes) for a party.
///
/// Copied from [partyRouteWaypoints].
class PartyRouteWaypointsProvider
    extends AutoDisposeStreamProvider<List<RouteWaypoint>> {
  /// Live decrypted waypoints (across all routes) for a party.
  ///
  /// Copied from [partyRouteWaypoints].
  PartyRouteWaypointsProvider(String partyId)
    : this._internal(
        (ref) => partyRouteWaypoints(ref as PartyRouteWaypointsRef, partyId),
        from: partyRouteWaypointsProvider,
        name: r'partyRouteWaypointsProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$partyRouteWaypointsHash,
        dependencies: PartyRouteWaypointsFamily._dependencies,
        allTransitiveDependencies:
            PartyRouteWaypointsFamily._allTransitiveDependencies,
        partyId: partyId,
      );

  PartyRouteWaypointsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.partyId,
  }) : super.internal();

  final String partyId;

  @override
  Override overrideWith(
    Stream<List<RouteWaypoint>> Function(PartyRouteWaypointsRef provider)
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PartyRouteWaypointsProvider._internal(
        (ref) => create(ref as PartyRouteWaypointsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        partyId: partyId,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<List<RouteWaypoint>> createElement() {
    return _PartyRouteWaypointsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PartyRouteWaypointsProvider && other.partyId == partyId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, partyId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PartyRouteWaypointsRef
    on AutoDisposeStreamProviderRef<List<RouteWaypoint>> {
  /// The parameter `partyId` of this provider.
  String get partyId;
}

class _PartyRouteWaypointsProviderElement
    extends AutoDisposeStreamProviderElement<List<RouteWaypoint>>
    with PartyRouteWaypointsRef {
  _PartyRouteWaypointsProviderElement(super.provider);

  @override
  String get partyId => (origin as PartyRouteWaypointsProvider).partyId;
}

String _$chatServiceHash() => r'cce72ae5d22b3592f5fd989ed5b48459c7a7a418';

/// See also [chatService].
@ProviderFor(chatService)
final chatServiceProvider = AutoDisposeProvider<ChatService>.internal(
  chatService,
  name: r'chatServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$chatServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ChatServiceRef = AutoDisposeProviderRef<ChatService>;
String _$partyMessagesHash() => r'da6bbc7d515ff71d1e32390553018bf44f25f845';

/// Live decrypted chat for a party (realtime).
///
/// Copied from [partyMessages].
@ProviderFor(partyMessages)
const partyMessagesProvider = PartyMessagesFamily();

/// Live decrypted chat for a party (realtime).
///
/// Copied from [partyMessages].
class PartyMessagesFamily extends Family<AsyncValue<List<ChatMessage>>> {
  /// Live decrypted chat for a party (realtime).
  ///
  /// Copied from [partyMessages].
  const PartyMessagesFamily();

  /// Live decrypted chat for a party (realtime).
  ///
  /// Copied from [partyMessages].
  PartyMessagesProvider call(String partyId) {
    return PartyMessagesProvider(partyId);
  }

  @override
  PartyMessagesProvider getProviderOverride(
    covariant PartyMessagesProvider provider,
  ) {
    return call(provider.partyId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'partyMessagesProvider';
}

/// Live decrypted chat for a party (realtime).
///
/// Copied from [partyMessages].
class PartyMessagesProvider
    extends AutoDisposeStreamProvider<List<ChatMessage>> {
  /// Live decrypted chat for a party (realtime).
  ///
  /// Copied from [partyMessages].
  PartyMessagesProvider(String partyId)
    : this._internal(
        (ref) => partyMessages(ref as PartyMessagesRef, partyId),
        from: partyMessagesProvider,
        name: r'partyMessagesProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$partyMessagesHash,
        dependencies: PartyMessagesFamily._dependencies,
        allTransitiveDependencies:
            PartyMessagesFamily._allTransitiveDependencies,
        partyId: partyId,
      );

  PartyMessagesProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.partyId,
  }) : super.internal();

  final String partyId;

  @override
  Override overrideWith(
    Stream<List<ChatMessage>> Function(PartyMessagesRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PartyMessagesProvider._internal(
        (ref) => create(ref as PartyMessagesRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        partyId: partyId,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<List<ChatMessage>> createElement() {
    return _PartyMessagesProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PartyMessagesProvider && other.partyId == partyId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, partyId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PartyMessagesRef on AutoDisposeStreamProviderRef<List<ChatMessage>> {
  /// The parameter `partyId` of this provider.
  String get partyId;
}

class _PartyMessagesProviderElement
    extends AutoDisposeStreamProviderElement<List<ChatMessage>>
    with PartyMessagesRef {
  _PartyMessagesProviderElement(super.provider);

  @override
  String get partyId => (origin as PartyMessagesProvider).partyId;
}

String _$selfPositionHash() => r'7f5c7ad8df53bc0a8720ed4d8c59a5ab5e75903e';

/// Live continuous GPS stream for THIS device. Powers the local UI (camera
/// follow, heading-up auto-mode, instant self-dot updates) without waiting
/// on the Supabase round-trip. Survives screen reloads via keepAlive.
///
/// Uses `getPositionStream` with a 5 m distanceFilter — the OS will only
/// wake the listener when the user actually moves that far, which keeps
/// battery sane while still feeling responsive at a walking pace (5 m at
/// 4 mph ≈ a fresh fix every 2.8 s).
///
/// Copied from [selfPosition].
@ProviderFor(selfPosition)
final selfPositionProvider = StreamProvider<Position>.internal(
  selfPosition,
  name: r'selfPositionProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$selfPositionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SelfPositionRef = StreamProviderRef<Position>;
String _$locationSharingHash() => r'f352d7deb4ca11f9710f10f27102154c24f5668d';

/// Controls whether this device is broadcasting its own (encrypted) location
/// to a party. The map screen turns this on while it's open.
///
/// Previously this polled `getCurrentPosition` on a 30 s timer, which makes
/// the dot feel frozen between fixes even at a brisk walk (54 m gap per
/// tick). Now we subscribe to [selfPositionProvider] and throttle the
/// Supabase publish to no faster than the user's configured interval (still
/// 30 s default, up to 5 min) — so the local UI is smooth but server load /
/// battery cost match the old behaviour.
///
/// Copied from [LocationSharing].
@ProviderFor(LocationSharing)
final locationSharingProvider =
    AutoDisposeNotifierProvider<LocationSharing, bool>.internal(
      LocationSharing.new,
      name: r'locationSharingProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$locationSharingHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$LocationSharing = AutoDisposeNotifier<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
