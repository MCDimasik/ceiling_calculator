import 'dart:io';

import 'package:roomplan_flutter/roomplan_flutter.dart';

import 'room_scan_import.dart';

/// iOS RoomPlan scan wrapper (LiDAR devices, iOS 16+).
class RoomPlanService {
  static Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    try {
      return await RoomPlanScanner.isSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<RoomScanImportResult?> scanRoom() async {
    if (!Platform.isIOS) return null;
    final scanner = RoomPlanScanner();
    try {
      final result = await scanner.startScanning(
        configuration: const ScanConfiguration(
          detectDoors: true,
          detectWindows: true,
          detectFurniture: false,
          quality: ScanQuality.balanced,
        ),
      );
      if (result == null) return null;
      return importFromRoomPlanScan(result);
    } finally {
      scanner.dispose();
    }
  }
}
