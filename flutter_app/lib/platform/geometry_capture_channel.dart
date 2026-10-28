import 'dart:io';

import 'package:flutter/services.dart';

enum ArCoreAvailability {
  unsupported,
  supportedNotInstalled,
  supportedInstalled,
  unknown,
}

/// Native geometry capture (ARCore on Android; RoomPlan via plugin on iOS).
class GeometryCaptureChannel {
  static const _channel = MethodChannel('org.ceiling/geometry_capture');

  static Future<ArCoreAvailability> arCoreAvailability() async {
    if (!Platform.isAndroid) return ArCoreAvailability.unsupported;
    try {
      final v = await _channel.invokeMethod<String>('arCoreAvailability');
      return switch (v) {
        'installed' => ArCoreAvailability.supportedInstalled,
        'not_installed' => ArCoreAvailability.supportedNotInstalled,
        'unsupported' => ArCoreAvailability.unsupported,
        _ => ArCoreAvailability.unknown,
      };
    } catch (_) {
      return ArCoreAvailability.unknown;
    }
  }

  static Future<bool> isArCoreAvailable() async {
    final a = await arCoreAvailability();
    return a == ArCoreAvailability.supportedInstalled ||
        a == ArCoreAvailability.supportedNotInstalled;
  }

  /// Triggers Play Services for AR install dialog when needed.
  /// Returns `ready`, `installing`, `unsupported`, or `error:…`.
  static Future<String> ensureArCoreInstalled() async {
    if (!Platform.isAndroid) return 'unsupported';
    try {
      final v = await _channel.invokeMethod<String>('ensureArCoreInstalled');
      return v ?? 'error:null';
    } on PlatformException catch (e) {
      return 'error:${e.message}';
    } catch (e) {
      return 'error:$e';
    }
  }

  /// Opens Play Маркет page for Google Play Services for AR.
  static Future<bool> openArCorePlayStore() async {
    if (!Platform.isAndroid) return false;
    try {
      final v = await _channel.invokeMethod<bool>('openArCorePlayStore');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Starts AR corner scan. Throws [PlatformException] on hard failures
  /// (unsupported / launch) so UI can offer Play Маркет instead of crashing.
  static Future<List<List<double>>?> startArRoomScan() async {
    if (!Platform.isAndroid) return null;
    final raw = await _channel.invokeMethod<List<dynamic>>('startArRoomScan');
    if (raw == null) return null;
    return raw
        .map((w) => (w as List).map((n) => (n as num).toDouble()).toList())
        .toList();
  }
}
