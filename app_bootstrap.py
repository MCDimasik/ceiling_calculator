"""Инициализация хранилища и БД после полного старта Kivy App (важно для Android)."""

import traceback

from kivy.logger import Logger

_initialized = False


def ensure_app_storage_ready():
    """Один раз создаёт БД и таблицы поставщиков в user_data_dir."""
    global _initialized
    if _initialized:
        return True
    try:
        from database import init_db
        from supplier_db import init_supplier_tables

        init_db()
        init_supplier_tables()
        _initialized = True
        return True
    except Exception as exc:
        Logger.exception("ensure_app_storage_ready failed: %s", exc)
        _write_crash_log("ensure_app_storage_ready", exc)
        return False


def _write_crash_log(where, exc):
    try:
        from kivy.app import App

        app = App.get_running_app()
        if not app or not getattr(app, "user_data_dir", None):
            return
        import os

        path = os.path.join(app.user_data_dir, "startup_error.log")
        with open(path, "a", encoding="utf-8") as f:
            f.write(f"\n--- {where} ---\n")
            f.write("".join(traceback.format_exception(type(exc), exc, exc.__traceback__)))
    except Exception:
        pass
