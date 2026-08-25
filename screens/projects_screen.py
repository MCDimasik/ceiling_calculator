# screens/projects_screen.py

from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.image import Image
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.gridlayout import GridLayout
from kivy.uix.scrollview import ScrollView
from kivy.uix.popup import Popup
from kivy.uix.textinput import TextInput
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.core.window import Window
from kivy.utils import platform
from kivy.app import App
from database import load_all_projects, save_project, delete_project, load_project
from app_bootstrap import ensure_app_storage_ready
from kivy.uix.relativelayout import RelativeLayout
from ui_style import COLORS, apply_btn_style, style_title, wrap_button_text, style_text_input, configure_modal_footer_buttons, make_input_row
from widgets.ui_components import RoundedButton, RoundedLabel
from widgets.ui_modal import RoundedModal
from widgets.tile_actions import LongPressTile
from project_transfer import share_project_by_id
import theme


class ProjectsScreen(Screen):
    """Экран со списком проектов (плиточный интерфейс)"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        root = FloatLayout()
        self._root = root

        self.bg_photo = Image(source="assets/bg_light.png", allow_stretch=True, keep_ratio=True)
        self.bg_photo.size_hint = (None, None)
        self.bg_photo.pos = (0, 0)
        self.bg_photo.size = root.size
        self.bg_photo.opacity = 0
        root.add_widget(self.bg_photo)
        root.bind(pos=lambda *_: self._layout_bg_cover(), size=lambda *_: self._layout_bg_cover())

        main_layout = BoxLayout(orientation='vertical', spacing=dp(2), size_hint=(1, 1))

        # Заголовок
        toolbar = self.create_toolbar()

        # Основная область с проектами
        content_area = self.create_content_area()

        main_layout.add_widget(toolbar)
        main_layout.add_widget(content_area)
        root.add_widget(main_layout)
        self.add_widget(root)

        self.bind(size=self.on_size)

        # ← КРИТИЧНО: Инициализируем пустым списком
        self.projects = []

        # ← КРИТИЧНО: Убираем загрузку из __init__ - будем грузить только в on_pre_enter
        # Clock.schedule_once(lambda dt: self.load_projects(), 0.1)  # УДАЛИТЬ ЭТУ СТРОКУ

    def on_pre_enter(self):
        """← КРИТИЧНО: Загружаем проекты КАЖДЫЙ раз при входе на экран"""
        ensure_app_storage_ready()
        self._apply_bg()
        # Грузим сразу, иначе во время FadeTransition плитки "прыгают" и появляются рывком.
        self.load_projects()

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
        """Обновляет размеры плиток при изменении размера окна"""
        if hasattr(self, 'projects_container'):
            # ← КРИТИЧНО: Отменяем предыдущие вызовы чтобы избежать множественных обновлений
            Clock.unschedule(lambda dt: self.update_projects_grid())
            Clock.schedule_once(lambda dt: self.update_projects_grid(), 0.1)

    def create_toolbar(self):
        """Создает панель инструментов"""
        # Важно: при фиксированной высоте большой padding "съедает" вертикаль и кнопки выглядят низкими.
        # Делаем вертикальный padding небольшим, а горизонтальный оставляем.
        toolbar = BoxLayout(
            size_hint=(1, None),
            height=dp(72),
            padding=(dp(12), dp(6)),
            spacing=dp(10)
        )

        # Кнопка "Назад" на главный экран
        btn_back = RoundedButton(
            text='Назад',
            font_size=dp(14),
            size_hint=(0.35, 1)
        )
        btn_back.corner_radius = dp(14)
        apply_btn_style(btn_back, role="secondary")
        wrap_button_text(btn_back)
        btn_back.bind(on_press=self.go_back)

        # Заголовок
        title = RoundedLabel(
            text='Мои проекты',
            font_size=dp(16),
            size_hint=(0.30, 1),
            color=COLORS["text"],
            halign='center',
            valign='middle'
        )
        title.corner_radius = dp(14)
        style_title(title)
        title.bind(size=title.setter('text_size'))

        # Кнопка "Добавить проект" с переносом текста
        btn_add = RoundedButton(
            text='Новый\nпроект',
            font_size=dp(14),
            size_hint=(0.35, 1),
            halign='center',
            valign='middle'
        )
        btn_add.corner_radius = dp(14)
        apply_btn_style(btn_add, role="surface")
        btn_add.bind(on_press=self.show_add_project_dialog)

        wrap_button_text(btn_add)

        toolbar.add_widget(btn_back)
        toolbar.add_widget(title)
        toolbar.add_widget(btn_add)

        return toolbar

    def create_content_area(self):
        """Создает область с плитками проектов"""
        self.projects_container = GridLayout(
            cols=2,
            spacing=dp(10),
            padding=dp(10),
            size_hint_y=None
        )
        self.projects_container.bind(
            minimum_height=self.projects_container.setter('height'))

        scroll = ScrollView()
        scroll.add_widget(self.projects_container)

        return scroll

    def load_projects(self):
        """Загружает проекты из базы данных"""
        # ← КРИТИЧНО: Очищаем список перед загрузкой
        self.projects = []

        db_projects = load_all_projects()
        if db_projects:
            self.projects = db_projects

        # ← КРИТИЧНО: Обновляем сетку
        self.update_projects_grid()

    def update_projects_grid(self):
        """Обновляет сетку проектов"""
        # ← КРИТИЧНО: Очищаем контейнер ПЕРЕД добавлением новых виджетов
        if hasattr(self, 'projects_container'):
            self.projects_container.clear_widgets()

        # Устанавливаем параметры сетки
        if hasattr(self, 'projects_container'):
            self.projects_container.cols = 2
            self.projects_container.spacing = dp(10)
            self.projects_container.padding = dp(10)

        # Добавляем плитки проектов
        for project in self.projects:
            project_tile = self.create_project_tile(project)
            if hasattr(self, 'projects_container'):
                self.projects_container.add_widget(project_tile)

        # Автоматически устанавливаем высоту контейнера
        if hasattr(self, 'projects_container'):
            self.projects_container.height = self.projects_container.minimum_height

        # Если проектов нет
        if not self.projects and hasattr(self, 'projects_container'):
            empty_label = Label(
                text='Нет проектов\nНажмите "Новый проект"',
                font_size=dp(16),
                color=(0.5, 0.5, 0.5, 1),
                halign='center',
                valign='middle',
                size_hint_y=None
            )
            empty_label._theme_slot = "muted"
            empty_label.bind(size=empty_label.setter('text_size'))
            empty_label.height = self.height * 0.3
            self.projects_container.add_widget(empty_label)
            self.projects_container.height = self.projects_container.minimum_height

    def create_project_tile(self, project):
        """Плитка проекта: тап — открыть, долгое нажатие — поделиться / удалить."""
        container_width = self.projects_container.width if self.projects_container.width > 0 else self.width
        tile_width = (container_width - dp(30)) / 2 if container_width > 0 else dp(150)

        from models import CeilingLayout
        total_area = 0.0
        full_project = load_project(project.id) if project.id else None
        if full_project:
            for room in full_project.rooms:
                try:
                    if room.walls and len(room.walls) >= 3:
                        temp_layout = CeilingLayout(room)
                        temp_layout.calculate_layout()
                        total_area += temp_layout.room_area_sqm if hasattr(
                            temp_layout, "room_area_sqm") else 0.0
                except Exception as e:
                    print(f"Ошибка расчета площади: {e}")

        button_text = f"{project.name}\n{total_area:.1f} м²" if total_area > 0 else project.name
        pid = project.id

        return LongPressTile(
            tile_width,
            button_text,
            on_open=lambda p=project: self.open_project(p),
            on_share=lambda: share_project_by_id(pid),
            on_delete=lambda: self.confirm_delete_project(pid),
        )

    def confirm_delete_project(self, project_id):
        """Показывает диалог подтверждения удаления проекта."""
        content = BoxLayout(orientation='vertical',
                            spacing=dp(10), padding=dp(10))
        from ui_style import style_popup_card
        style_popup_card(content, radius_dp=18)
        message = Label(text='Вы точно хотите удалить?', font_size=dp(16), color=COLORS["text"])
        btn_layout = BoxLayout(spacing=dp(10))

        modal = None

        def do_delete(dt):
            success = delete_project(project_id)
            if success:
                self.load_projects()  # ← Перезагружаем список
                if modal:
                    modal.dismiss()

        def cancel_delete(dt):
            if modal:
                modal.dismiss()

        btn_delete = RoundedButton(text='Удалить', color=(1, 1, 1, 1))
        btn_delete.corner_radius = dp(12)
        apply_btn_style(btn_delete, role="danger")
        btn_cancel = RoundedButton(text='Отмена')
        btn_cancel.corner_radius = dp(12)
        apply_btn_style(btn_cancel, role="secondary")

        btn_delete.bind(on_press=do_delete)
        btn_cancel.bind(on_press=cancel_delete)

        btn_layout.add_widget(btn_cancel)
        btn_layout.add_widget(btn_delete)
        configure_modal_footer_buttons(btn_layout, btn_cancel, btn_delete)
        content.add_widget(message)
        content.add_widget(btn_layout)

        modal = RoundedModal(content=content, card_size_hint=(0.84, None), card_height_dp=210)
        modal.open()

    def show_add_project_dialog(self, instance):
        """Показывает диалог добавления проекта"""
        content = BoxLayout(orientation='vertical',
                            spacing=dp(10), padding=dp(20))
        label = Label(text='Название проекта:', font_size=dp(16), color=COLORS["text"])
        name_input = TextInput(multiline=False, font_size=dp(18))
        style_text_input(name_input)
        input_row = make_input_row(name_input)
        btn_layout = BoxLayout(spacing=dp(10))

        btn_confirm = RoundedButton(text='Создать', color=(1, 1, 1, 1))
        btn_confirm.corner_radius = dp(12)
        apply_btn_style(btn_confirm, role="primary")
        btn_cancel = RoundedButton(text='Отмена')
        btn_cancel.corner_radius = dp(12)
        apply_btn_style(btn_cancel, role="secondary")

        modal = None

        def create_project(inst):
            name = name_input.text.strip()
            if name:
                from models import Project
                project = Project(name)
                save_project(project)
                self.load_projects()  # ← Перезагружаем список
                if modal:
                    modal.dismiss()

        btn_confirm.bind(on_press=create_project)
        btn_cancel.bind(on_press=lambda x: modal.dismiss() if modal else None)

        btn_layout.add_widget(btn_cancel)
        btn_layout.add_widget(btn_confirm)
        configure_modal_footer_buttons(btn_layout, btn_cancel, btn_confirm)
        content.add_widget(label)
        content.add_widget(input_row)
        content.add_widget(btn_layout)

        modal = RoundedModal(content=content, card_size_hint=(0.88, None), card_height_dp=260)

        def update_popup_position(*args):
            if platform != 'android':
                return
            kb_height = getattr(Window, 'keyboard_height', 0) or 0
            if kb_height > 0 and name_input.focus:
                modal.card.pos_hint = {'center_x': 0.5, 'center_y': 0.72}
            else:
                modal.card.pos_hint = {'center_x': 0.5, 'center_y': 0.55}

        def on_focus(instance, focused):
            Clock.schedule_once(lambda dt: update_popup_position(), 0.05)

        def on_popup_open(*args):
            Window.bind(keyboard_height=update_popup_position)
            update_popup_position()

        def on_popup_dismiss(*args):
            try:
                Window.unbind(keyboard_height=update_popup_position)
            except Exception:
                pass

        name_input.bind(focus=on_focus)
        modal.bind(on_open=on_popup_open, on_dismiss=on_popup_dismiss)
        modal.open()

    def open_project(self, project):
        """Открывает проект (переход к экрану комнат)"""
        self.manager.current_project = project
        self.manager.current = 'rooms'

    def go_back(self, instance):
        """Возврат на главный экран"""
        self.manager.current = 'main'
