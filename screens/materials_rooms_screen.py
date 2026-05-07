from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.image import Image
from kivy.uix.gridlayout import GridLayout
from kivy.uix.scrollview import ScrollView
from kivy.uix.relativelayout import RelativeLayout
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.app import App
from database import load_project
from ui_style import COLORS, apply_btn_style, style_title, wrap_button_text
from widgets.ui_components import RoundedButton, RoundedLabel
import theme


class MaterialsRoomsScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.title = None

        root = FloatLayout()
        self._root = root
        self.bg_photo = Image(source="assets/bg_light.png", allow_stretch=True, keep_ratio=True)
        self.bg_photo.size_hint = (None, None)
        self.bg_photo.pos = (0, 0)
        self.bg_photo.size = root.size
        self.bg_photo.opacity = 0
        root.add_widget(self.bg_photo)
        root.bind(pos=lambda *_: self._layout_bg_cover(), size=lambda *_: self._layout_bg_cover())

        main = BoxLayout(orientation="vertical", spacing=dp(2), size_hint=(1, 1))
        toolbar = BoxLayout(size_hint=(1, None), height=dp(72), padding=(dp(12), dp(6)), spacing=dp(10))
        btn_back = RoundedButton(text="Назад", font_size=dp(14), size_hint=(0.30, 1))
        btn_back.corner_radius = dp(14)
        apply_btn_style(btn_back, role="secondary")
        btn_back.bind(on_press=lambda *_: setattr(self.manager, "current", "materials_projects"))
        self.title = RoundedLabel(
            text="Комнаты",
            font_size=dp(16),
            size_hint=(0.40, 1),
            color=COLORS["text"],
            halign='center',
            valign='middle',
        )
        self.title.corner_radius = dp(14)
        style_title(self.title)
        self.title.bind(size=self.title.setter('text_size'))
        wrap_button_text(btn_back)

        btn_calc = RoundedButton(text="Полный\nРасчет", font_size=dp(14), size_hint=(0.30, 1))
        btn_calc.corner_radius = dp(14)
        apply_btn_style(btn_calc, role="secondary")
        wrap_button_text(btn_calc)
        btn_calc.bind(on_press=lambda *_: setattr(self.manager, "current", "materials_project_result"))

        toolbar.add_widget(btn_back)
        toolbar.add_widget(self.title)
        toolbar.add_widget(btn_calc)

        self.container = GridLayout(cols=2, spacing=dp(10), padding=dp(10), size_hint_y=None)
        self.container.bind(minimum_height=self.container.setter("height"))
        scroll = ScrollView()
        scroll.add_widget(self.container)

        main.add_widget(toolbar)
        main.add_widget(scroll)
        root.add_widget(main)
        self.add_widget(root)
        self.bind(size=self.on_size)

    def on_pre_enter(self):
        self._apply_bg()
        project = getattr(self.manager, "current_project", None)
        if not project:
            self.manager.current = "materials_projects"
            return
        full = load_project(project.id) if project.id else project
        self.manager.current_project = full
        self.title.text = f"{full.name}"
        self.container.clear_widgets()
        self.container.cols = 2
        if not full.rooms:
            el = Label(text="Нет комнат", color=(0.4, 0.4, 0.4, 1), size_hint_y=None, height=dp(60))
            el._theme_slot = "muted"
            self.container.add_widget(el)
            return
        for room in full.rooms:
            self.container.add_widget(self._create_room_tile(room))
        self.container.height = self.container.minimum_height

    def _apply_bg(self):
        app = App.get_running_app()
        mode = getattr(app, "theme_mode", theme.THEME_LIGHT)
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

    def on_size(self, *args):
        if hasattr(self, 'container'):
            Clock.schedule_once(lambda dt: self.on_pre_enter(), 0.05)

    def _create_room_tile(self, room):
        container_width = self.container.width if self.container.width > 0 else self.width
        tile_w = (container_width - dp(30)) / 2 if container_width > 0 else dp(150)
        tile = RelativeLayout(size_hint=(None, None), size=(tile_w, tile_w))
        btn = RoundedButton(
            text=room.name,
            size_hint=(1, 1),
            background_normal='',
            color=COLORS["text"],
            halign='center',
            valign='middle',
            text_size=(tile_w - dp(20), tile_w - dp(20)),
            shorten=False,
            max_lines=2,
        )
        btn.corner_radius = dp(18)
        apply_btn_style(btn, role="surface")
        btn.bind(on_press=lambda _, r=room: self.open_room(r))
        tile.add_widget(btn)
        return tile

    def open_room(self, room):
        self.manager.current_room = room
        self.manager.current = "materials_result"
