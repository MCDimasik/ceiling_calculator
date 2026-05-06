"""
Тема оформления: системная / светлая / тёмная.
Определение «как в системе»: Android (Configuration), Windows (реестр), Linux (gsettings, опционально).
"""
from __future__ import annotations

import json
import os
import subprocess
from typing import Any, Dict, Optional

from kivy.logger import Logger
from kivy.utils import platform

THEME_SYSTEM = "system"
THEME_LIGHT = "light"
THEME_DARK = "dark"

# Палитры под фото-фоны (assets/bg_light.png и assets/bg_dark.png).
# Важно: UI рисуется поверх фото, поэтому используем "surface" карточки и четкие токены контраста.
_PALETTE_LIGHT: Dict[str, Any] = {
    "bg": (0.949, 0.945, 0.945, 1),  # #F2F1F1
    "surface": (1.0, 1.0, 1.0, 1),
    "surface_alt": (0.969, 0.965, 0.969, 1),  # #F7F6F7
    "border": (0.851, 0.843, 0.847, 1),  # #D9D7D8
    "text": (0.086, 0.102, 0.133, 1),  # #161A22
    "muted": (0.369, 0.404, 0.459, 1),  # #5E6775
    "primary": (0.184, 0.427, 0.965, 1),  # #2F6DF6
    "primary_alt": (0.243, 0.482, 1.0, 1),  # #3E7BFF
    "danger": (0.878, 0.271, 0.271, 1),  # #E04545
    "secondary_fill": (0.969, 0.965, 0.969, 1),  # = surface_alt
    "title_bar": (1.0, 1.0, 1.0, 0.78),  # "стекло" поверх фото (меньше заливки)
    "spinner_option_down": (0.898, 0.925, 0.992, 1),
    "selection": (0.184, 0.427, 0.965, 0.30),
    "overlay": (0, 0, 0, 0.18),
}

_PALETTE_DARK: Dict[str, Any] = {
    "bg": (0.071, 0.071, 0.071, 1),  # #121212
    "surface": (0.110, 0.110, 0.110, 1),  # #1C1C1C
    "surface_alt": (0.141, 0.141, 0.141, 1),  # #242424
    "border": (0.184, 0.184, 0.184, 1),  # #2F2F2F
    "text": (0.949, 0.957, 0.973, 1),  # #F2F4F8
    "muted": (0.655, 0.686, 0.737, 1),  # #A7AFBC
    "primary": (0.294, 0.545, 1.0, 1),  # #4B8BFF
    "primary_alt": (0.416, 0.627, 1.0, 1),  # #6AA0FF
    "danger": (1.0, 0.353, 0.353, 1),  # #FF5A5A
    "secondary_fill": (0.141, 0.141, 0.141, 1),  # = surface_alt
    # Заголовок в хедерах должен выглядеть как кнопка (не "стекло")
    "title_bar": (0.141, 0.141, 0.141, 1.0),  # = surface_alt
    "spinner_option_down": (0.180, 0.220, 0.320, 1),
    "selection": (0.294, 0.545, 1.0, 0.25),
    "overlay": (0, 0, 0, 0.40),
}

# Сетка редактора и раскладки — как в оригинальных grid_widget / layout_widget (не зависят от переключателя темы).
_EDITOR_REDESIGN: Dict[str, Any] = {
    "bg_color": (0.12, 0.13, 0.13, 1),
    "wall_color": (0.94, 0.96, 0.98, 1),
    "point_color": (0.94, 0.96, 0.98, 1),
    "room_color": (0.32, 0.38, 0.42, 1),
    "closing_line_color": (0.79, 0.84, 0.87, 1),
}

_LAYOUT_REDESIGN: Dict[str, Any] = {
    "bg_color": (0.12, 0.13, 0.13, 1),
    "wall_color": (0.94, 0.96, 0.98, 1),
    "room_color": (0.32, 0.38, 0.42, 1),
    "grid_color": (0.79, 0.84, 0.87, 0.7),
    "full_tile_color": (0.9, 0.9, 0.9, 0.3),
    "cut_tile_color": (0.7, 0.7, 0.7, 0.3),
    "text_color": (0.94, 0.96, 0.98, 1),
}


def detect_system_prefers_dark() -> bool:
    pl = platform
    if pl == "android":
        try:
            from jnius import autoclass

            PythonActivity = autoclass("org.kivy.android.PythonActivity")
            Configuration = autoclass("android.content.res.Configuration")
            activity = PythonActivity.mActivity
            config = activity.getResources().getConfiguration()
            mask = Configuration.UI_MODE_NIGHT_MASK
            yes = Configuration.UI_MODE_NIGHT_YES
            return (config.uiMode & int(mask)) == int(yes)
        except Exception as e:
            Logger.warning("Theme: Android night mode detection failed: %s", e)
            return False

    if pl == "win":
        try:
            import winreg

            key = winreg.OpenKey(
                winreg.HKEY_CURRENT_USER,
                r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
            )
            try:
                val, _ = winreg.QueryValueEx(key, "AppsUseLightTheme")
            finally:
                winreg.CloseKey(key)
            return int(val) == 0
        except Exception as e:
            Logger.warning("Theme: Windows theme detection failed: %s", e)
            return False

    if pl == "linux":
        try:
            out = subprocess.run(
                ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
                capture_output=True,
                text=True,
                timeout=0.4,
            )
            if out.returncode == 0 and out.stdout:
                s = out.stdout.strip().strip("'")
                if "dark" in s.lower():
                    return True
        except Exception:
            pass
    return False


def resolve_effective_dark(theme_mode: str) -> bool:
    if theme_mode == THEME_DARK:
        return True
    if theme_mode == THEME_LIGHT:
        return False
    return detect_system_prefers_dark()


def palette_for(effective_dark: bool) -> Dict[str, Any]:
    return dict(_PALETTE_DARK if effective_dark else _PALETTE_LIGHT)


def editor_colors(effective_dark: bool) -> Dict[str, Any]:
    """Цвета холста редактора комнаты — эталон редизайна (тёмный фон сетки)."""
    return dict(_EDITOR_REDESIGN)


def layout_canvas_colors(effective_dark: bool) -> Dict[str, Any]:
    """Цвета виджета раскладки — как в layout_widget после редизайна."""
    return dict(_LAYOUT_REDESIGN)


def load_theme_mode(prefs_path: str) -> str:
    try:
        if os.path.isfile(prefs_path):
            with open(prefs_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            m = data.get("theme_mode", THEME_LIGHT)
            if m in (THEME_LIGHT, THEME_DARK):
                return m
    except Exception as e:
        Logger.warning("Theme: could not load prefs: %s", e)
    return THEME_LIGHT


def save_theme_mode(prefs_path: str, theme_mode: str) -> None:
    try:
        d = os.path.dirname(prefs_path)
        if d:
            os.makedirs(d, exist_ok=True)
        data = {}
        if os.path.isfile(prefs_path):
            try:
                with open(prefs_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
            except Exception:
                data = {}
        data["theme_mode"] = theme_mode
        with open(prefs_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        Logger.warning("Theme: could not save prefs: %s", e)


def load_pref_bool(prefs_path: str, key: str, default: bool) -> bool:
    try:
        if os.path.isfile(prefs_path):
            with open(prefs_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if key in data:
                return bool(data.get(key))
    except Exception as e:
        Logger.warning("Theme: could not load bool pref %s: %s", key, e)
    return bool(default)


def save_pref_bool(prefs_path: str, key: str, value: bool) -> None:
    try:
        d = os.path.dirname(prefs_path)
        if d:
            os.makedirs(d, exist_ok=True)
        data = {}
        if os.path.isfile(prefs_path):
            try:
                with open(prefs_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
            except Exception:
                data = {}
        data[key] = bool(value)
        with open(prefs_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        Logger.warning("Theme: could not save bool pref %s: %s", key, e)


def apply_palette_to_ui_style(effective_dark: bool) -> None:
    import ui_style

    ui_style.COLORS.clear()
    ui_style.COLORS.update(palette_for(effective_dark))


def refresh_widget_tree(widget, *, effective_dark: bool) -> None:
    """Обновить цвета уже созданных виджетов (после смены COLORS)."""
    from kivy.uix.label import Label
    from kivy.uix.textinput import TextInput
    from kivy.uix.spinner import Spinner

    from ui_style import COLORS, apply_btn_style, style_text_input
    from widgets.ui_components import RoundedButton, RoundedLabel, IconRoundedButton, StyledSpinnerOption
    from widgets.grid_widget import GridWidget
    from widgets.layout_widget import LayoutWidget

    ed = editor_colors(effective_dark)
    lc = layout_canvas_colors(effective_dark)

    for ch in getattr(widget, "children", tuple())[:]:
        refresh_widget_tree(ch, effective_dark=effective_dark)

    if hasattr(widget, "_theme_redraw"):
        try:
            widget._theme_redraw()
        except Exception:
            pass

    instr = getattr(widget, "_main_bg_color_instr", None)
    if instr is not None:
        instr.rgba = COLORS["bg"]
        # Доп. хук: если экран умеет обновлять видео-фон — дергаем
        try:
            fn = getattr(widget, "_apply_bg_video", None)
            if callable(fn):
                fn()
        except Exception:
            pass

    if isinstance(widget, GridWidget):
        for k, v in ed.items():
            setattr(widget, k, v)
        widget.draw_editor()

    if isinstance(widget, LayoutWidget):
        for k, v in lc.items():
            setattr(widget, k, v)
        widget.draw_layout()

    # RoundedLabel наследует Label — обрабатываем ДО ветки RoundedButton и отдельно от обычных Label.
    if isinstance(widget, RoundedLabel):
        widget.color = COLORS["text"]
        widget.bg_color = list(COLORS.get("title_bar", COLORS["surface"]))
        widget.texture_update()

    elif isinstance(widget, RoundedButton):
        role = getattr(widget, "_ui_btn_role", "secondary")
        apply_btn_style(widget, role=role)
        if isinstance(widget, IconRoundedButton):
            widget.icon_color = (
                list(COLORS["text"]) if role in ("secondary", "surface") else [1, 1, 1, 1]
            )

    elif isinstance(widget, Label):
        slot = getattr(widget, "_theme_slot", "text")
        if slot == "muted":
            widget.color = COLORS["muted"]
        else:
            widget.color = COLORS["text"]
        widget.texture_update()

    elif isinstance(widget, TextInput):
        style_text_input(widget)

    elif isinstance(widget, Spinner):
        widget.background_color = COLORS["surface"]
        widget.color = COLORS["text"]
        try:
            widget.texture_update()
        except Exception:
            pass

    elif isinstance(widget, StyledSpinnerOption):
        widget.color = COLORS["text"]
        widget._redraw()


def apply_theme_to_app(app, root) -> bool:
    """
    Применить тему к приложению. Возвращает effective_dark.
    """
    from kivy.core.window import Window
    from ui_style import COLORS

    mode = getattr(app, "theme_mode", THEME_SYSTEM)
    system_dark = detect_system_prefers_dark()
    effective = resolve_effective_dark(mode)
    apply_palette_to_ui_style(effective)
    Window.clearcolor = COLORS["bg"]

    Logger.info(
        "Theme: mode=%s system_dark=%s effective_dark=%s",
        mode,
        system_dark,
        effective,
    )
    refresh_widget_tree(root, effective_dark=effective)
    # ScreenManager держит неактивные экраны вне дерева виджетов.
    # Обновим их тоже, чтобы при входе не оставались "старые" цвета до первого тапа.
    try:
        screens = getattr(root, "screens", None)
        if screens:
            for s in screens:
                try:
                    refresh_widget_tree(s, effective_dark=effective)
                except Exception:
                    pass
    except Exception:
        pass
    _refresh_open_modals(effective_dark=effective)
    return effective


def _refresh_open_modals(*, effective_dark: bool) -> None:
    from kivy.core.window import Window
    from widgets.ui_modal import RoundedModal

    for w in Window.children:
        if isinstance(w, RoundedModal):
            w._redraw()
            refresh_widget_tree(w, effective_dark=effective_dark)
