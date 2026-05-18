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
from database import load_all_projects, delete_project
from ui_style import COLORS, apply_btn_style, style_title, wrap_button_text, configure_modal_footer_buttons
from widgets.ui_components import RoundedButton, RoundedLabel
from widgets.ui_modal import RoundedModal
from widgets.tile_actions import LongPressTile
from project_transfer import share_project_by_id
from kivy.uix.label import Label
import theme


class MaterialsProjectsScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.projects = []
        self.title_label = None

        root = FloatLayout()
        self._root = root
        self.bg_photo = Image(source="assets/bg_light.png", allow_stretch=True, keep_ratio=True)
        self.bg_photo.size_hint = (None, None)
        self.bg_photo.pos = (0, 0)
        self.bg_photo.size = root.size
        self.bg_photo.opacity = 0
        root.add_widget(self.bg_photo)
        root.bind(pos=lambda *_: self._layout_bg_cover(), size=lambda *_: self._layout_bg_cover())

        main = BoxLayout(orientation='vertical', spacing=dp(2), size_hint=(1, 1))
        toolbar = BoxLayout(size_hint=(1, None), height=dp(72), padding=(dp(12), dp(6)), spacing=dp(10))
        btn_back = RoundedButton(text='Назад', font_size=dp(14), size_hint=(0.35, 1))
        btn_back.corner_radius = dp(14)
        apply_btn_style(btn_back, role="secondary")
        btn_back.bind(on_press=lambda *_: setattr(self.manager, "current", "main"))
        self.title_label = RoundedLabel(
            text='Проекты',
            font_size=dp(16),
            size_hint=(0.65, 1),
            color=COLORS["text"],
            halign='center',
            valign='middle',
        )
        self.title_label.corner_radius = dp(14)
        style_title(self.title_label)
        self.title_label.bind(size=self.title_label.setter('text_size'))
        wrap_button_text(btn_back)
        toolbar.add_widget(btn_back)
        toolbar.add_widget(self.title_label)

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
        Clock.schedule_once(lambda dt: self.load_projects(), 0)

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
            Clock.schedule_once(lambda dt: self.load_projects(), 0.05)

    def load_projects(self):
        self.projects = load_all_projects() or []
        self.container.clear_widgets()
        self.container.cols = 2
        if not self.projects:
            el = Label(text="Нет проектов", color=(0.4, 0.4, 0.4, 1), size_hint_y=None, height=dp(60))
            el._theme_slot = "muted"
            self.container.add_widget(el)
            return
        for project in self.projects:
            self.container.add_widget(self._create_project_tile(project))
        self.container.height = self.container.minimum_height

    def _create_project_tile(self, project):
        container_width = self.container.width if self.container.width > 0 else self.width
        tile_w = (container_width - dp(30)) / 2 if container_width > 0 else dp(150)
        pid = project.id
        return LongPressTile(
            tile_w,
            project.name,
            on_open=lambda p=project: self.open_project(p),
            on_share=lambda: share_project_by_id(pid),
            on_delete=lambda: self._confirm_delete_project(pid),
        )

    def _confirm_delete_project(self, project_id):
        content = BoxLayout(orientation="vertical", spacing=dp(10), padding=dp(10))
        content.add_widget(Label(text="Удалить проект?", font_size=dp(16), color=COLORS["text"]))
        btn_layout = BoxLayout(spacing=dp(10))
        modal = None

        def do_delete(*_):
            if delete_project(project_id):
                self.load_projects()
            if modal:
                modal.dismiss()

        btn_del = RoundedButton(text="Удалить")
        btn_del.corner_radius = dp(12)
        apply_btn_style(btn_del, role="danger")
        btn_cancel = RoundedButton(text="Отмена")
        btn_cancel.corner_radius = dp(12)
        apply_btn_style(btn_cancel, role="secondary")
        btn_del.bind(on_press=do_delete)
        btn_cancel.bind(on_press=lambda *_: modal.dismiss())
        btn_layout.add_widget(btn_cancel)
        btn_layout.add_widget(btn_del)
        configure_modal_footer_buttons(btn_layout, btn_cancel, btn_del)
        content.add_widget(btn_layout)
        modal = RoundedModal(content=content, card_size_hint=(0.84, None), card_height_dp=210)
        modal.open()

    def open_project(self, project):
        self.manager.current_project = project
        self.manager.current = "materials_rooms"
