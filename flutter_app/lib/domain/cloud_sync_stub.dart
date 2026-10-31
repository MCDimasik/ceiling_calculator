import 'package:flutter/foundation.dart';

/// Client-side placeholders for sync / archive / OTA.
///
/// Server work on VPS is **blocked** until explicit SSH/API approval.
/// These types exist so UI can wire inbox badges and SURFACE flavors
/// without talking to the network yet.
enum CloudSyncStatus {
  offlineLocal,
  awaitingServerApproval,
  ready,
}

/// Build surface: phone UI vs future desktop director layout.
enum AppSurface {
  phone,
  desktop;

  static AppSurface fromEnvironment() {
    const raw = String.fromEnvironment('SURFACE', defaultValue: 'phone');
    return raw == 'desktop' ? AppSurface.desktop : AppSurface.phone;
  }

  bool get isDesktop => this == AppSurface.desktop;
}

class CloudSyncStub extends ChangeNotifier {
  CloudSyncStub();

  final AppSurface surface = AppSurface.fromEnvironment();

  CloudSyncStatus status = CloudSyncStatus.awaitingServerApproval;

  /// Red-dot targets (import / inbox) — always empty until server is approved.
  int get pendingProjectOffers => 0;
  int get pendingPricePushes => 0;
  int get pendingKitOffers => 0;

  int get pendingTotal =>
      pendingProjectOffers + pendingPricePushes + pendingKitOffers;

  bool get cloudUiEnabled => status == CloudSyncStatus.ready;

  /// Phone layout vs future Full HD director desktop (`--dart-define=SURFACE=`).
  bool get useDesktopChrome => surface.isDesktop;

  String get statusHintRu => switch (status) {
        CloudSyncStatus.offlineLocal => 'Только локальные данные',
        CloudSyncStatus.awaitingServerApproval =>
          'Облако и синк ждут согласования сервера',
        CloudSyncStatus.ready => 'Синхронизация активна',
      };
}
