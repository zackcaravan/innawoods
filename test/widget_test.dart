// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innawoods/features/auth/providers/auth_provider.dart';
import 'package:innawoods/features/party/providers/party_provider.dart';
import 'package:innawoods/main.dart';
import 'package:innawoods/shared/models/app_user.dart';
import 'package:innawoods/shared/models/party.dart';

void main() {
  testWidgets('home shows empty state + actions when bootstrapped', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWith(
            (ref) async => const AppUser(
              id: 'test-user',
              avatarColor: '#8A9A5B',
              publicKey: 'pk',
            ),
          ),
          myPartiesProvider.overrideWith((ref) async => <Party>[]),
        ],
        child: const InnawoodsApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('innawoods'), findsOneWidget);
    expect(find.text('Create party'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
    expect(find.textContaining('No active parties'), findsOneWidget);
  });
}
