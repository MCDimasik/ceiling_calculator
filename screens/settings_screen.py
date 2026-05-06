# screens/settings_screen.py
from kivy.app import App
from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.image import Image
from kivy.uix.label import Label
from kivy.metrics import dp

from theme import THEME_LIGHT, THEME_DARK, save_theme_mode, save_pref_bool, load_pref_bool, apply_theme_to_app
from ui_style import COLORS, apply_btn_style, style_title, wrap_button_text
from widgets.ui_components import RoundedButton, RoundedLabel, ThemeToggleRow, SwitchRow


class SettingsScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        outer = FloatLayout()
        self._root = outer
        self.bg_photo = Image(source="assets/bg_light.png", allow_stretch=True, keep_ratio=True)
        self.bg_photo.size_hint = (None, None)
        self.bg_photo.pos = (0, 0)
        self.bg_photo.size = outer.size
        self.bg_photo.opacity = 1
        outer.add_widget(self.bg_photo)
        outer.bind(pos=lambda *_: self._layout_bg_cover(), size=lambda *_: self._layout_bg_cover())

        root = BoxLayout(orientation="vertical", padding=dp(16), spacing=dp(12), size_hint=(1, 1))

        toolbar = BoxLayout(size_hint=(1, None), height=dp(52), spacing=dp(8))
        btn_back = RoundedButton(text="Назад", size_hint=(0.35, 1))
        btn_back.corner_radius = dp(14)
        apply_btn_style(btn_back, role="secondary")
        wrap_button_text(btn_back)
        btn_back.bind(on_press=lambda *_: setattr(self.manager, "current", "main"))
        title = RoundedLabel(
            text="Настройки",
            font_size=dp(18),
            size_hint=(0.65, 1),
            color=COLORS["text"],
            halign="center",
            valign="middle",
        )
        title.corner_radius = dp(14)
        style_title(title)
        title.bind(size=title.setter("text_size"))
        toolbar.add_widget(btn_back)
        toolbar.add_widget(title)

        body = BoxLayout(orientation="vertical", spacing=dp(10), size_hint=(1, 1))
        body.add_widget(
            Label(
                text="Тема оформления",
                font_size=dp(16),
                color=COLORS["text"],
                size_hint=(1, None),
                height=dp(28),
                halign="left",
                valign="middle",
            )
        )
        self.theme_toggle = ThemeToggleRow(text="Тёмная тема", size_hint=(1, None), height=dp(40))
        self.theme_toggle.on_toggle = self._on_toggle_dark

        self.video_toggle = SwitchRow(text="Видео‑фон на главной", size_hint=(1, None), height=dp(40))
        self.video_toggle.on_toggle = self._on_toggle_video

        # Отладка: уводим в самый низ экрана (потом удалим)
        self.debug_label = Label(
            text="",
            font_size=dp(11),
            color=COLORS["muted"],
            size_hint=(1, None),
            height=dp(18),
            valign="middle",
            halign="left",
        )
        self.debug_label.bind(size=lambda inst, _: setattr(inst, "text_size", (inst.width, None)))
        self.debug_label._theme_slot = "muted"
        body.add_widget(self.theme_toggle)
        body.add_widget(self.video_toggle)
        body.add_widget(Label(text="", size_hint=(1, 1)))  # spacer
        body.add_widget(self.debug_label)

        root.add_widget(toolbar)
        root.add_widget(body)
        outer.add_widget(root)
        self.add_widget(outer)

    def on_pre_enter(self):
        self._apply_bg()
        app = App.get_running_app()
        mode = getattr(app, "theme_mode", THEME_LIGHT)
        self.theme_toggle.active = mode == THEME_DARK
        path = getattr(app, "theme_prefs_path", None)
        if path:
            self.video_toggle.active = load_pref_bool(path, "use_video_bg", True)
        self._refresh_debug()

    def _refresh_debug(self):
        app = App.get_running_app()
        mode = getattr(app, "theme_mode", THEME_LIGHT)
        self.debug_label.text = (
            f"Режим: {'тёмная' if mode == THEME_DARK else 'светлая'}"
        )

    def _apply_bg(self):
        app = App.get_running_app()
        mode = getattr(app, "theme_mode", THEME_LIGHT)
        tex = None
        try:
            tex = getattr(app, "bg_textures", {}).get(mode)
        except Exception:
            tex = None
        if tex is not None:
            self.bg_photo.texture = tex
        self.bg_photo.opacity = 1.0
        self._layout_bg_cover()

    def _layout_bg_cover(self):
        tex = getattr(self.bg_photo, "texture", None)
        if tex is None or tex.width <= 0 or tex.height <= 0:
            self.bg_photo.pos = self._root.pos
            self.bg_photo.size = self._root.size
            return
        cw, ch = self._root.size
        if cw <= 0 or ch <= 0:
            return
        vw, vh = float(tex.width), float(tex.height)
        scale = max(cw / vw, ch / vh)
        w = vw * scale
        h = vh * scale
        x = self._root.x + (cw - w) / 2.0
        y = self._root.y + (ch - h) / 2.0
        self.bg_photo.pos = (x, y)
        self.bg_photo.size = (w, h)

    def _on_toggle_dark(self, is_dark: bool):
        app = App.get_running_app()
        mode = THEME_DARK if is_dark else THEME_LIGHT
        if getattr(app, "theme_mode", None) == mode:
            self._refresh_debug()
            return
        app.theme_mode = mode
        path = getattr(app, "theme_prefs_path", None)
        if path:
            save_theme_mode(path, mode)
        apply_theme_to_app(app, app.root)
        self._apply_bg()
        self._refresh_debug()

    def _on_toggle_video(self, is_on: bool):
        app = App.get_running_app()
        app.use_video_bg = bool(is_on)
        path = getattr(app, "theme_prefs_path", None)
        if path:
            save_pref_bool(path, "use_video_bg", bool(is_on))
        # Обновим главный экран, если он активен/создан
        try:
            main = app.root.get_screen("main")
            if hasattr(main, "_apply_bg_video"):
                main._apply_bg_video()
        except Exception:
            pass
