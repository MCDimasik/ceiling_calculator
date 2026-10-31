import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/project_repository.dart';
import 'data/supplier_repository.dart';
import 'domain/account_cloud_sync.dart';
import 'domain/app_update.dart';
import 'domain/ceiling_sync_client.dart';
import 'domain/legacy_migration.dart';
import 'domain/local_user_role.dart';
import 'domain/offline_device_sync.dart';
import 'domain/theme_controller.dart';
import 'domain/transfer_activity.dart';
import 'domain/work_rates_catalog.dart';
import 'ui/widgets/app_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initDatabaseFactory();
  final db = await openAppDatabase();
  final projects = ProjectRepository(db);
  final suppliers = SupplierRepository(db);
  final theme = ThemeController();
  await theme.load();
  final user = LocalUserController();
  await user.load();
  await projects.ensureOwnerPartition();
  await projects.setActiveOwnerLogin(user.profile?.login ?? '__guest__');
  final sync = CeilingSyncController();
  await sync.load();
  final transfers = TransferActivityController();
  final offlineSync = OfflineDeviceSyncController(
    projects: projects,
    suppliers: suppliers,
    user: user,
    transfers: transfers,
  );
  await offlineSync.load();
  final accountCloud = AccountCloudSyncController(
    projects: projects,
    suppliers: suppliers,
    sync: sync,
    offlineSync: offlineSync,
    transfers: transfers,
  );
  accountCloud.startAutoSync();
  final appUpdate = AppUpdateController(transfers: transfers);
  await appUpdate.load();
  await bootstrapSuppliers(suppliers);
  // Warm work-rates catalog for KS-2 price fallback / pickers.
  await WorkRatesCatalogStore.ensureLoaded();
  // Warm project list so first «Проекты» open is from memory.
  await projects.warmCaches();
  // Pre-blur light+dark backgrounds once (memory + disk) — no flash on finish screens.
  await BgBlurCache.warm(const [
    'assets/media/bg_light.png',
    'assets/media/bg_dark.png',
  ]);
  // Restore cloud account if session already signed in (reinstall / new device).
  if (sync.isSignedIn) {
    // Fire-and-forget; UI will show status when ready.
    // ignore: unawaited_futures
    accountCloud.syncNow();
  }
  runApp(CeilingCalculatorApp(
    projects: projects,
    suppliers: suppliers,
    theme: theme,
    user: user,
    sync: sync,
    offlineSync: offlineSync,
    accountCloud: accountCloud,
    appUpdate: appUpdate,
    transfers: transfers,
  ));
}
