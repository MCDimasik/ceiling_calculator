from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.video import Video
from kivy.uix.image import Image
from kivy.metrics import dp
from ui_style import COLORS, apply_btn_style, style_title
from widgets.ui_components import RoundedButton
import theme
from kivy.clock import Clock
from kivy.resources import resource_find
from kivy.logger import Logger
import os


class MainScreen(Screen):
    """Главный экран с выбором калькулятора"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        root = FloatLayout()
        self._root = root

        # Фолбэк-фон (на случай если видео-провайдер недоступен)
        from kivy.graphics import Color, Rectangle
        with root.canvas.before:
            self._main_bg_color_instr = Color(*COLORS["bg"])
            self._main_bg_rect = Rectangle(pos=root.pos, size=root.size)
        root.bind(pos=lambda inst, val: setattr(self._main_bg_rect, "pos", val))
        root.bind(size=lambda inst, val: setattr(self._main_bg_rect, "size", val))

        # Фото-фон (только для светлой темы)
        self.bg_photo = Image(source="assets/bg_light.png", allow_stretch=True, keep_ratio=True)
        self.bg_photo.size_hint = (None, None)
        self.bg_photo.pos = (0, 0)
        self.bg_photo.size = root.size
        self.bg_photo.opacity = 1
        root.add_widget(self.bg_photo)
        root.bind(pos=lambda *_: self._layout_photo_cover(), size=lambda *_: self._layout_photo_cover())

        # Фоновое видео (под контентом)
        self.bg_video = Video(
            source="",
            state="stop",
            options={"eos": "loop"},
            allow_stretch=True,
            keep_ratio=True,
        )
        # cover layout: size/pos считаем вручную, чтобы видео закрывало весь экран без искажений
        self.bg_video.size_hint = (None, None)
        self.bg_video.pos = (0, 0)
        self.bg_video.size = root.size
        # Показываем видео только когда оно реально загрузилось
        self.bg_video.opacity = 0
        root.add_widget(self.bg_video)
        root.bind(pos=lambda *_: self._layout_video_cover(), size=lambda *_: self._layout_video_cover())

        # Основной вертикальный контейнер (поверх видео)
        main_layout = BoxLayout(
            orientation="vertical",
            padding=dp(20),
            spacing=dp(16),
            size_hint=(1, 1),
        )
        root.add_widget(main_layout)

        # Контейнер для кнопок
        buttons_layout = BoxLayout(
            orientation='vertical',
            spacing=dp(12),
            size_hint=(1, None),
            height=dp(192),
        )

        # Кнопка 1: Расчет раскладки потолка
        self.btn_calc1 = RoundedButton(
            text='Расчет раскладки потолка',
            font_size=dp(16),
            size_hint=(1, None),
            height=dp(54),
        )
        self.btn_calc1.corner_radius = dp(18)
        apply_btn_style(self.btn_calc1, role="surface")
        # Изменено: теперь идем в проекты
        self.btn_calc1.bind(on_press=self.go_to_projects)

        # Кнопка 2: Расчет материалов
        self.btn_calc2 = RoundedButton(
            text='Расчет материалов',
            font_size=dp(16),
            size_hint=(1, None),
            height=dp(54),
        )
        self.btn_calc2.corner_radius = dp(18)
        apply_btn_style(self.btn_calc2, role="surface")
        self.btn_calc2.bind(on_press=self.go_to_materials)

        self.btn_settings = RoundedButton(
            text='Настройки',
            font_size=dp(16),
            size_hint=(1, None),
            height=dp(54),
        )
        self.btn_settings.corner_radius = dp(18)
        apply_btn_style(self.btn_settings, role="surface")
        self.btn_settings.bind(on_press=self.go_to_settings)

        # Собираем интерфейс
        buttons_layout.add_widget(self.btn_calc1)
        buttons_layout.add_widget(self.btn_calc2)
        buttons_layout.add_widget(self.btn_settings)

        # Без логотипа: больше воздуха под кнопки
        main_layout.add_widget(Label(size_hint=(1, 1)))  # spacer
        main_layout.add_widget(buttons_layout)
        main_layout.add_widget(Label(size_hint=(1, 1)))  # spacer

        self.add_widget(root)

    def on_pre_enter(self):
        # На всякий случай синхронизируем стили кнопок с текущей темой
        for b in (getattr(self, "btn_calc1", None), getattr(self, "btn_calc2", None), getattr(self, "btn_settings", None)):
            if b is not None:
                role = getattr(b, "_ui_btn_role", "surface")
                apply_btn_style(b, role=role)

    def on_enter(self, *args):
        # На Android видео часто не стартует, если дергать его до первого кадра экрана.
        Clock.schedule_once(lambda *_: self._apply_bg_video(), 0)

    def on_leave(self, *args):
        # Не держим декодер активным между экранами
        try:
            if getattr(self, "_video_load_poll_ev", None) is not None:
                self._video_load_poll_ev.cancel()
                self._video_load_poll_ev = None
        except Exception:
            pass
        try:
            self.bg_video.state = "stop"
        except Exception:
            pass

    def _apply_bg_video(self):
        from kivy.app import App

        app = App.get_running_app()
        mode = getattr(app, "theme_mode", theme.THEME_LIGHT)
        use_video = bool(getattr(app, "use_video_bg", True))

        # Фото-фон по теме (если видео выключено — это основной фон)
        tex = None
        try:
            tex = getattr(app, "bg_textures", {}).get(mode)
        except Exception:
            tex = None
        if tex is not None:
            self.bg_photo.texture = tex
        self._layout_photo_cover()

        if not use_video:
            self.bg_video.opacity = 0
            try:
                self.bg_video.state = "stop"
            except Exception:
                pass
            return

        rel = "assets/dark_theme.mp4" if mode == theme.THEME_DARK else "assets/white_theme.mp4"
        path = self._resolve_media_path(rel)
        if not path or not os.path.exists(path):
            Logger.warning("MainScreen: bg video not found: rel=%r resolved=%r", rel, path)
            self.bg_video.opacity = 0
            return
        # Video.source ожидает путь к файлу, не file:// URI
        self.bg_video.source = path
        try:
            self.bg_video.state = "stop"
        except Exception:
            pass
        # Чуть позже запускаем play (иначе на части устройств первый старт игнорируется)
        Clock.schedule_once(self._start_video_playback, 0.10)
        # На слабых/перегруженных устройствах texture может появляться заметно позже 1с.
        self.bg_video.opacity = 0
        try:
            if getattr(self, "_video_load_poll_ev", None) is not None:
                self._video_load_poll_ev.cancel()
        except Exception:
            pass
        self._video_load_poll_ev_tries = 0
        self._video_load_poll_ev = Clock.schedule_interval(self._poll_video_loaded, 0.25)

    def _resolve_media_path(self, rel: str) -> str:
        """
        На Android `resource_find("assets/..")` иногда не срабатывает, если assets уже добавлен как resource path.
        Пробуем несколько вариантов и возвращаем существующий путь.
        """
        candidates = []
        p1 = resource_find(rel)
        if p1:
            candidates.append(p1)
        base = os.path.basename(rel)
        p2 = resource_find(base)
        if p2:
            candidates.append(p2)
        candidates.append(rel)
        for p in candidates:
            try:
                if p and os.path.exists(p):
                    return p
            except Exception:
                continue
        return candidates[0] if candidates else rel

    def _start_video_playback(self, *_):
        try:
            self.bg_video.state = "play"
        except Exception:
            pass

    def _poll_video_loaded(self, *_):
        # Если видео не загрузилось (нет texture), остаёмся на фолбэк-фоне
        self._video_load_poll_ev_tries = getattr(self, "_video_load_poll_ev_tries", 0) + 1
        tex = getattr(self.bg_video, "texture", None)
        if tex is not None:
            self._layout_video_cover()
            self.bg_video.opacity = 1
            try:
                if getattr(self, "_video_load_poll_ev", None) is not None:
                    self._video_load_poll_ev.cancel()
                    self._video_load_poll_ev = None
            except Exception:
                pass
            return False
        # ~6 секунд (0.25 * 24) ждём, дальше сдаёмся и оставляем фолбэк
        if self._video_load_poll_ev_tries >= 24:
            try:
                if getattr(self, "_video_load_poll_ev", None) is not None:
                    self._video_load_poll_ev.cancel()
                    self._video_load_poll_ev = None
            except Exception:
                pass
            return False
        return True

    def _layout_video_cover(self):
        """
        Cover (как CSS background-size: cover):
        - сохраняем пропорции
        - заполняем весь экран
        - лишнее обрезается по краям
        """
        tex = getattr(self.bg_video, "texture", None)
        if tex is None or tex.width <= 0 or tex.height <= 0:
            # пока нет texture — хотя бы заполняем контейнер
            self.bg_video.pos = self._root.pos
            self.bg_video.size = self._root.size
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
        self.bg_video.pos = (x, y)
        self.bg_video.size = (w, h)

    def _layout_photo_cover(self):
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

    def go_to_projects(self, instance):  # Переименован метод
        """Переход к экрану проектов"""
        print("Переход к экрану проектов")
        self.manager.current = 'projects'

    def go_to_materials(self, instance):
        """Переход к расчету материалов"""
        self.manager.current = 'materials_projects'

    def go_to_settings(self, instance):
        self.manager.current = "settings"
