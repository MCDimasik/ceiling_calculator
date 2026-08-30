import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const prefThemeMode = 'theme_mode';
const prefUseVideoBg = 'use_video_bg_v2';

/// Windows/Linux: video_player often crashes the embedder (external GL textures).
bool get videoBgUnsupported {
  if (kIsWeb) return false;
  try {
    return Platform.isWindows || Platform.isLinux;
  } catch (_) {
    return false;
  }
}

class ThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;
  bool useVideoBg = false;

  bool get isDarkEffective {
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  }

  String get bgImageAsset =>
      isDarkEffective ? 'assets/media/bg_dark.png' : 'assets/media/bg_light.png';

  String get bgVideoAsset =>
      isDarkEffective ? 'assets/media/dark_theme.mp4' : 'assets/media/white_theme.mp4';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefThemeMode) ?? 'system';
    mode = switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    if (videoBgUnsupported) {
      useVideoBg = false;
    } else {
      useVideoBg = prefs.getBool(prefUseVideoBg) ?? false;
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode next) async {
    mode = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefThemeMode,
      switch (next) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      },
    );
    notifyListeners();
  }

  Future<void> setUseVideoBg(bool value) async {
    if (videoBgUnsupported) {
      useVideoBg = false;
      notifyListeners();
      return;
    }
    useVideoBg = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefUseVideoBg, value);
    notifyListeners();
  }
}
