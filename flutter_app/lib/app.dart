import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'data/project_repository.dart';
import 'data/supplier_repository.dart';
import 'domain/account_cloud_sync.dart';
import 'domain/app_update.dart';
import 'domain/ceiling_sync_client.dart';
import 'domain/local_user_role.dart';
import 'domain/offline_device_sync.dart';
import 'domain/theme_controller.dart';
import 'domain/transfer_activity.dart';
import 'ui/adaptive_layout.dart';
import 'ui/app_theme.dart';
import 'ui/desktop_shell.dart';
import 'ui/widgets/transfer_progress_banner.dart';

/// Touch + mouse + trackpad drag scrolling (phone finger and desktop).
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class CeilingCalculatorApp extends StatelessWidget {
  const CeilingCalculatorApp({
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

  @override
  Widget build(BuildContext context) {
    return AppScope(
      projects: projects,
      suppliers: suppliers,
      theme: theme,
      user: user,
      sync: sync,
      offlineSync: offlineSync,
      accountCloud: accountCloud,
      appUpdate: appUpdate,
      transfers: transfers,
      child: AnimatedBuilder(
        animation: Listenable.merge(
          [theme, user, sync, offlineSync, accountCloud, appUpdate, transfers],
        ),
        builder: (context, _) {
          return MaterialApp(
            title: 'Высота Калькулятор',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: theme.mode,
            scrollBehavior: AppScrollBehavior(),
            builder: (context, child) {
              Widget page = child ?? const SizedBox.shrink();
              if (AdaptiveBreakpoints.useDesktopChrome(context)) {
                page = MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: DesktopMetrics.textScaler(context),
                  ),
                  child: Theme(
                    data: desktopThemeOverlay(Theme.of(context)),
                    child: page,
                  ),
                );
              }
              return TransferProgressBannerHost(child: page);
            },
            home: const AppRootHome(),
          );
        },
      ),
    );
  }
}
