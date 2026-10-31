import 'package:flutter/material.dart';

import 'data/project_repository.dart';
import 'data/supplier_repository.dart';
import 'domain/account_cloud_sync.dart';
import 'domain/app_update.dart';
import 'domain/ceiling_sync_client.dart';
import 'domain/local_user_role.dart';
import 'domain/offline_device_sync.dart';
import 'domain/theme_controller.dart';
import 'domain/transfer_activity.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.projects,
    required this.suppliers,
    required this.theme,
    required this.user,
    required this.sync,
    required this.offlineSync,
    required this.accountCloud,
    required this.appUpdate,
    required this.transfers,
    required super.child,
  });

  final ProjectRepository projects;
  final SupplierRepository suppliers;
  final ThemeController theme;
  final LocalUserController user;
  final CeilingSyncController sync;
  final OfflineDeviceSyncController offlineSync;
  final AccountCloudSyncController accountCloud;
  final AppUpdateController appUpdate;
  final TransferActivityController transfers;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      projects != oldWidget.projects ||
      suppliers != oldWidget.suppliers ||
      theme != oldWidget.theme ||
      user != oldWidget.user ||
      sync != oldWidget.sync ||
      offlineSync != oldWidget.offlineSync ||
      accountCloud != oldWidget.accountCloud ||
      appUpdate != oldWidget.appUpdate ||
      transfers != oldWidget.transfers;
}
