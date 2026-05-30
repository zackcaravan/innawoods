import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/crypto_service.dart';
import '../../../core/crypto/identity_key_store.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/services/auth_service.dart';

part 'auth_provider.g.dart';

@riverpod
SupabaseClient supabaseClient(Ref ref) => Supabase.instance.client;

@riverpod
CryptoService cryptoService(Ref ref) => CryptoService();

@riverpod
IdentityKeyStore identityKeyStore(Ref ref) =>
    IdentityKeyStore(crypto: ref.watch(cryptoServiceProvider));

@riverpod
AuthService authService(Ref ref) => AuthService(
      ref.watch(supabaseClientProvider),
      ref.watch(identityKeyStoreProvider),
      ref.watch(cryptoServiceProvider),
    );

/// Runs once on launch: anonymous session + identity + profile row.
@riverpod
Future<AppUser> appBootstrap(Ref ref) =>
    ref.watch(authServiceProvider).bootstrap();
