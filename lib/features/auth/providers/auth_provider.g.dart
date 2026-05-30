// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$supabaseClientHash() => r'de6240783d7dddb57e07d034deb0ddf8e2fcc3e4';

/// See also [supabaseClient].
@ProviderFor(supabaseClient)
final supabaseClientProvider = AutoDisposeProvider<SupabaseClient>.internal(
  supabaseClient,
  name: r'supabaseClientProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$supabaseClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SupabaseClientRef = AutoDisposeProviderRef<SupabaseClient>;
String _$cryptoServiceHash() => r'bfbb2cb91fea5683ad3097b84499fcf3a3a6dbb0';

/// See also [cryptoService].
@ProviderFor(cryptoService)
final cryptoServiceProvider = AutoDisposeProvider<CryptoService>.internal(
  cryptoService,
  name: r'cryptoServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$cryptoServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CryptoServiceRef = AutoDisposeProviderRef<CryptoService>;
String _$identityKeyStoreHash() => r'cef433cb721849c03d5dfad5e665a456679d9378';

/// See also [identityKeyStore].
@ProviderFor(identityKeyStore)
final identityKeyStoreProvider = AutoDisposeProvider<IdentityKeyStore>.internal(
  identityKeyStore,
  name: r'identityKeyStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$identityKeyStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef IdentityKeyStoreRef = AutoDisposeProviderRef<IdentityKeyStore>;
String _$authServiceHash() => r'78e43cdf26a1a8236cb2a2bc14a26a1d668bfbc7';

/// See also [authService].
@ProviderFor(authService)
final authServiceProvider = AutoDisposeProvider<AuthService>.internal(
  authService,
  name: r'authServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$authServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AuthServiceRef = AutoDisposeProviderRef<AuthService>;
String _$appBootstrapHash() => r'f4e720b82072789f3dc6bba1c072d360cace3c67';

/// Runs once on launch: anonymous session + identity + profile row.
///
/// Copied from [appBootstrap].
@ProviderFor(appBootstrap)
final appBootstrapProvider = AutoDisposeFutureProvider<AppUser>.internal(
  appBootstrap,
  name: r'appBootstrapProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appBootstrapHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AppBootstrapRef = AutoDisposeFutureProviderRef<AppUser>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
