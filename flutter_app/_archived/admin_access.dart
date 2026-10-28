import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

const prefAdminUnlocked = 'admin_unlocked';

/// Precomputed SHA-256 of the admin passphrase (plain text not stored in source).
const _adminPasswordHash =
    'e24a1e873d6e7a23e83030ba8f8bbf06d867d9fe854111cb67eb8a61c7897613';

String _hash(String password) =>
    sha256.convert(utf8.encode(password.trim())).toString();

/// Admin unlock (parity with Python `app_access.py`).
class AdminAccess {
  AdminAccess();

  bool unlocked = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    unlocked = prefs.getBool(prefAdminUnlocked) ?? false;
  }

  Future<bool> tryUnlock(String password) async {
    if (_hash(password) != _adminPasswordHash) return false;
    unlocked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefAdminUnlocked, true);
    return true;
  }

  Future<void> lock() async {
    unlocked = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefAdminUnlocked, false);
  }
}
