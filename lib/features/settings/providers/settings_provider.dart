// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/services/dead_man_monitor.dart';
import '../../../shared/services/notification_service.dart';
import '../../../shared/services/settings_store.dart';

part 'settings_provider.g.dart';

@Riverpod(keepAlive: true)
NotificationService notificationService(Ref ref) => NotificationService();

@Riverpod(keepAlive: true)
DeadManMonitor deadManMonitor(Ref ref) =>
    DeadManMonitor(ref.watch(notificationServiceProvider));

@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  @override
  Future<AppSettings> build() => SettingsStore().load();

  Future<void> save(AppSettings settings) async {
    await SettingsStore().save(settings);
    state = AsyncData(settings);
    // Asking for notification permission is only meaningful once enabled.
    if (settings.deadManEnabled) {
      await ref.read(notificationServiceProvider).requestPermission();
    }
  }
}
