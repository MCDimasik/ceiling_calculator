"""Режим приложения: обычный пользователь / администратор (цены, поставщики)."""

import hashlib

from theme import load_pref_bool, save_pref_bool

PREF_ADMIN_UNLOCKED = "admin_unlocked"

# Пароль для разблокировки (SHA-256 от строки ниже). Сменить: замените _ADMIN_PASSWORD_PLAIN.
_ADMIN_PASSWORD_PLAIN = "Gfhjkm-lkz-flvbyf"
_ADMIN_PASSWORD_HASH = hashlib.sha256(_ADMIN_PASSWORD_PLAIN.encode("utf-8")).hexdigest()


def _password_ok(password: str) -> bool:
    raw = (password or "").strip()
    if not raw:
        return False
    return hashlib.sha256(raw.encode("utf-8")).hexdigest() == _ADMIN_PASSWORD_HASH


def load_admin_unlocked(prefs_path: str) -> bool:
    return load_pref_bool(prefs_path, PREF_ADMIN_UNLOCKED, False)


def save_admin_unlocked(prefs_path: str, unlocked: bool) -> None:
    save_pref_bool(prefs_path, PREF_ADMIN_UNLOCKED, unlocked)


def is_admin(app=None) -> bool:
    if app is None:
        from kivy.app import App

        app = App.get_running_app()
    if app is None:
        return False
    return bool(getattr(app, "admin_unlocked", False))


def try_unlock_admin(password: str, prefs_path: str, app=None) -> bool:
    if not _password_ok(password):
        return False
    save_admin_unlocked(prefs_path, True)
    if app is None:
        from kivy.app import App

        app = App.get_running_app()
    if app is not None:
        app.admin_unlocked = True
    return True


def admin_screen_names():
    return frozenset({"suppliers", "supplier_edit", "receipt_import", "project_cost"})


def guard_admin_navigation(screen_manager, target_name: str, fallback: str = "main") -> bool:
    """Вернуть False и перенаправить, если экран только для админа."""
    if target_name not in admin_screen_names():
        return True
    if is_admin():
        return True
    screen_manager.current = fallback
    return False
