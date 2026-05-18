"""Поделиться файлом проекта и выбор файла для импорта (Android + десктоп)."""
import os
import shutil
from kivy.utils import platform

from project_export import FILE_EXTENSION, MIME_TYPE, safe_export_basename

REQUEST_OPEN_DOCUMENT = 44001

_import_callback = None


def set_import_callback(callback):
    global _import_callback
    _import_callback = callback


def get_import_callback():
    return _import_callback


def _exports_dir():
    from kivy.app import App

    app = App.get_running_app()
    base = getattr(app, "user_data_dir", None) or os.path.expanduser("~")
    path = os.path.join(base, "exports")
    os.makedirs(path, exist_ok=True)
    return path


def make_export_path(project_name: str) -> str:
    base = safe_export_basename(project_name)
    return os.path.join(_exports_dir(), base + FILE_EXTENSION)


def share_project_file(filepath: str, chooser_title: str = "Поделиться проектом"):
    if not filepath or not os.path.isfile(filepath):
        return False

    if platform == "android":
        return _share_file_android(filepath, chooser_title)
    return _share_file_desktop(filepath, chooser_title)


def _share_file_android(filepath: str, chooser_title: str) -> bool:
    try:
        from jnius import autoclass

        PythonActivity = autoclass("org.kivy.android.PythonActivity")
        Intent = autoclass("android.content.Intent")
        File = autoclass("java.io.File")
        Uri = autoclass("android.net.Uri")
        FileProvider = autoclass("androidx.core.content.FileProvider")

        activity = PythonActivity.mActivity
        context = activity.getApplicationContext()
        pkg = context.getPackageName()
        authority = pkg + ".fileprovider"
        java_file = File(filepath)
        uri = FileProvider.getUriForFile(context, authority, java_file)

        intent = Intent(Intent.ACTION_SEND)
        intent.setType(MIME_TYPE)
        intent.putExtra(Intent.EXTRA_STREAM, uri)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.putExtra(Intent.EXTRA_SUBJECT, os.path.basename(filepath))

        chooser = Intent.createChooser(intent, chooser_title)
        activity.startActivity(chooser)
        return True
    except Exception as e:
        print(f"Android share failed: {e}")
        return _share_text_fallback(filepath)


def _share_text_fallback(filepath: str) -> bool:
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            text = f.read()
        from jnius import autoclass

        Intent = autoclass("android.content.Intent")
        PythonActivity = autoclass("org.kivy.android.PythonActivity")
        intent = Intent(Intent.ACTION_SEND)
        intent.setType("text/plain")
        intent.putExtra(Intent.EXTRA_TEXT, text)
        chooser = Intent.createChooser(intent, "Поделиться")
        PythonActivity.mActivity.startActivity(chooser)
        return True
    except Exception:
        return False


def _share_file_desktop(filepath: str, chooser_title: str) -> bool:
    """На ПК сохраняем файл в exports/ и показываем путь пользователю."""
    try:
        from kivy.core.clipboard import Clipboard

        Clipboard.copy(filepath)
    except Exception:
        pass
    folder = os.path.dirname(filepath)
    try:
        if platform == "win":
            os.startfile(folder)
        elif platform == "linux":
            os.system(f'xdg-open "{folder}"')
        elif platform == "macosx":
            os.system(f'open "{folder}"')
    except Exception:
        pass
    _notify_desktop_share(filepath)
    return True


def _notify_desktop_share(filepath: str):
    try:
        from kivy.app import App
        from kivy.uix.boxlayout import BoxLayout
        from kivy.uix.label import Label
        from kivy.uix.popup import Popup
        from kivy.metrics import dp
        from ui_style import COLORS, apply_btn_style
        from widgets.ui_components import RoundedButton

        content = BoxLayout(orientation="vertical", padding=dp(16), spacing=dp(10))
        msg = Label(
            text=f"Файл проекта сохранён:\n{filepath}\n\nПуть скопирован в буфер обмена.",
            font_size=dp(13),
            halign="center",
            valign="middle",
            color=COLORS["text"],
        )
        msg.bind(size=lambda inst, val: setattr(inst, "text_size", val))
        content.add_widget(msg)
        btn = RoundedButton(text="ОК", size_hint=(1, None), height=dp(44))
        btn.corner_radius = dp(12)
        apply_btn_style(btn, role="secondary")
        popup = Popup(
            title="Поделиться",
            content=content,
            size_hint=(0.88, None),
            height=dp(220),
        )
        btn.bind(on_press=popup.dismiss)
        content.add_widget(btn)
        popup.open()
    except Exception:
        pass


def pick_project_file(on_result):
    """on_result(path: str|None)"""
    set_import_callback(on_result)
    if platform == "android":
        if not _pick_file_android():
            set_import_callback(None)
            on_result(None)
    else:
        path = _pick_file_desktop()
        set_import_callback(None)
        on_result(path)


def _pick_file_desktop():
    try:
        import tkinter as tk
        from tkinter import filedialog

        root = tk.Tk()
        root.withdraw()
        root.attributes("-topmost", True)
        path = filedialog.askopenfilename(
            title="Выберите файл проекта",
            filetypes=[("Проект потолка", f"*{FILE_EXTENSION}"), ("JSON", "*.json"), ("Все файлы", "*.*")],
        )
        root.destroy()
        return path or None
    except Exception as e:
        print(f"Desktop file pick failed: {e}")
        return None


def _pick_file_android() -> bool:
    try:
        from jnius import autoclass

        Intent = autoclass("android.content.Intent")
        PythonActivity = autoclass("org.kivy.android.PythonActivity")
        activity = PythonActivity.mActivity

        intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
        intent.addCategory(Intent.CATEGORY_OPENABLE)
        intent.setType("*/*")
        intent.putExtra("android.intent.extra.MIME_TYPES", ["application/json", MIME_TYPE, "text/plain"])

        activity.startActivityForResult(intent, REQUEST_OPEN_DOCUMENT)
        return True
    except Exception as e:
        print(f"Android pick file failed: {e}")
        return False


def handle_activity_result(request_code, result_code, intent):
    if request_code != REQUEST_OPEN_DOCUMENT:
        return False
    cb = get_import_callback()
    set_import_callback(None)
    if not cb:
        return True

    path = None
    try:
        from jnius import autoclass, cast

        PythonActivity = autoclass("org.kivy.android.PythonActivity")
        Activity = autoclass("android.app.Activity")
        if result_code != Activity.RESULT_OK or intent is None:
            cb(None)
            return True

        uri = intent.getData()
        if uri is None:
            cb(None)
            return True
        path = _uri_to_local_file(uri)
    except Exception as e:
        print(f"Import read URI failed: {e}")
        path = None

    cb(path)
    return True


def _uri_to_local_file(uri):
    from jnius import autoclass

    PythonActivity = autoclass("org.kivy.android.PythonActivity")
    context = PythonActivity.mActivity
    stream = context.getContentResolver().openInputStream(uri)
    if stream is None:
        return None

    dest = os.path.join(_exports_dir(), "import_pending.ccproj")
    Reader = autoclass("java.io.InputStreamReader")
    BufferedReader = autoclass("java.io.BufferedReader")
    reader = BufferedReader(Reader(stream))
    StringBuilder = autoclass("java.lang.StringBuilder")
    sb = StringBuilder()
    line = reader.readLine()
    while line is not None:
        sb.append(line)
        sb.append("\n")
        line = reader.readLine()
    reader.close()
    text = str(sb.toString())
    with open(dest, "w", encoding="utf-8") as f:
        f.write(text)
    return dest


def register_android_callbacks():
    if platform != "android":
        return
    try:
        from android.activity import bind

        def _on_activity_result(request_code, result_code, intent, *args):
            handle_activity_result(request_code, result_code, intent)

        bind(on_activity_result=_on_activity_result)
    except Exception as e:
        print(f"Could not bind android activity: {e}")
