# screens/rooms_screen.py
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
from kivy.graphics import Color, Rectangle, Line
from kivy.clock import Clock
from kivy.core.window import Window
from kivy.utils import platform
from kivy.app import App
# Импортируем delete_room_from_project и load_project
from database import save_project, delete_room_from_project, load_project
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.relativelayout import RelativeLayout
from ui_style import COLORS, apply_btn_style, style_title, wrap_button_text, style_text_input, configure_modal_footer_buttons, make_input_row
from widgets.ui_components import RoundedButton, RoundedLabel
from widgets.ui_modal import RoundedModal
from widgets.tile_actions import LongPressTile
from project_transfer import share_room
import theme


class RoomsScreen(Screen):
    """Экран со списком комнат в проекте"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
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

        main_layout = BoxLayout(orientation='vertical', spacing=dp(2), size_hint=(1, 1))

        # Панель инструментов
        toolbar = self.create_toolbar()

        # Основная область с комнатами
        content_area = self.create_content_area()

        main_layout.add_widget(toolbar)
        main_layout.add_widget(content_area)
        root.add_widget(main_layout)
        self.add_widget(root)
        self.bind(size=self.on_size)

    def on_size(self, *args):
        """Обновляет размеры плиток при изменении размера окна"""
        if hasattr(self, 'rooms_container') and len(self.rooms_container.children) > 0:
            # Пересчитываем размеры плиток при изменении размера окна
            Clock.schedule_once(lambda dt: self.update_rooms_grid(), 0.1)

    def on_pre_enter(self):
        """Перед входом: только фон. Тяжелую загрузку переносим на on_enter, чтобы не фризило SlideTransition."""
        self._apply_bg()

    def on_enter(self):
        # После завершения slide-перехода можно делать тяжелую загрузку/перестройку сетки
        if hasattr(self.manager, 'current_project') and self.manager.current_project:
            project_id = self.manager.current_project.id
            if project_id:
                from database import load_project
                loaded_project = load_project(project_id)
                if loaded_project:
                    self.manager.current_project = loaded_project
                    # ← КРИТИЧНО: Очищаем кэш площадей в проектах
                    if hasattr(self.manager, 'current_project') and self.manager.current_project:
                        for project in getattr(self.manager, '_all_projects', []):
                            if hasattr(project, '_cached_area'):
                                delattr(project, '_cached_area')
                    self.update_rooms_grid()

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

    def create_toolbar(self):
        """Создает панель инструментов"""
        toolbar = BoxLayout(
            size_hint=(1, None),
            height=dp(72),
            padding=(dp(12), dp(6)),
            spacing=dp(10)  # ← отступ между кнопками
        )

        # Кнопка "Назад" к проектам
        btn_back = RoundedButton(
            text='Назад',
            font_size=dp(14),
            size_hint=(0.35, 1)
        )
        btn_back.corner_radius = dp(14)
        apply_btn_style(btn_back, role="secondary")
        wrap_button_text(btn_back)
        btn_back.bind(on_press=self.go_back)

        # Заголовок (будет обновляться)
        self.title_label = RoundedLabel(
            text='Комнаты',
            font_size=dp(16),
            size_hint=(0.30, 1),
            color=COLORS["text"],
            halign='center',
            valign='middle'
        )
        self.title_label.corner_radius = dp(14)
        style_title(self.title_label)
        self.title_label.bind(size=self.title_label.setter('text_size'))

        # Кнопка "Добавить комнату" с переносом текста
        btn_add = RoundedButton(
            text='Новая\nкомната',
            font_size=dp(14),
            size_hint=(0.35, 1),
            halign='center',
            valign='middle'
        )
        btn_add.corner_radius = dp(14)
        apply_btn_style(btn_add, role="surface")
        btn_add.bind(on_press=self.show_add_room_dialog)

        wrap_button_text(btn_add)

        toolbar.add_widget(btn_back)
        toolbar.add_widget(self.title_label)
        toolbar.add_widget(btn_add)

        return toolbar

    def create_content_area(self):
        """Создает область с плитками комнат"""
        # Контейнер для сетки комнат
        self.rooms_container = GridLayout(
            cols=2,
            spacing=dp(10),
            padding=dp(10),
            size_hint_y=None
        )
        self.rooms_container.bind(
            minimum_height=self.rooms_container.setter('height'))

        # Скролл для контейнера
        scroll = ScrollView()
        scroll.add_widget(self.rooms_container)

        return scroll

    def update_rooms_grid(self):
        """Обновляет сетку комнат"""
        self.rooms_container.clear_widgets()
        project = self.manager.current_project
        
        if project:
            # ← КРИТИЧНО: Расчет общей площади для тулбара
            from models import CeilingLayout
            total_area = 0.0
            for room in project.rooms:
                try:
                    if room.walls and len(room.walls) >= 3:
                        temp_layout = CeilingLayout(room)
                        # ← КРИТИЧНО: Вызываем calculate_layout() для расчета площади!
                        temp_layout.calculate_layout()
                        total_area += temp_layout.room_area_sqm if hasattr(temp_layout, 'room_area_sqm') else 0.0
                except Exception as e:
                    print(f"Ошибка расчета площади: {e}")
                    continue
            
            # ← КРИТИЧНО: правильное форматирование заголовка
            if total_area > 0:
                self.title_label.text = f'Комнаты:\n{project.name}\n{total_area:.1f} м²'
            else:
                self.title_label.text = f'Комнаты:\n{project.name}'
            
            self.title_label.font_size = dp(14)
            self.title_label.halign = 'center'
            self.title_label.valign = 'middle'
            self.title_label.max_lines = 3
            self.title_label.text_size = (self.title_label.width, self.title_label.height * 3)
            
            # Параметры сетки
            self.rooms_container.cols = 2
            self.rooms_container.spacing = dp(10)
            self.rooms_container.padding = dp(10)
            
            # Добавляем плитки комнат
            for room in project.rooms:
                room_tile = self.create_room_tile(room)
                self.rooms_container.add_widget(room_tile)
            
            self.rooms_container.height = self.rooms_container.minimum_height
            
            # Если комнат нет
            if not project.rooms:
                empty_label = Label(
                    text='Нет комнат\nНажмите "Новая комната"',
                    font_size=dp(16),
                    color=(0.5, 0.5, 0.5, 1),
                    halign='center',
                    valign='middle',
                    size_hint_y=None
                )
                empty_label._theme_slot = "muted"
                empty_label.bind(size=empty_label.setter('text_size'))
                empty_label.height = self.height * 0.3
                self.rooms_container.add_widget(empty_label)
                self.rooms_container.height = self.rooms_container.minimum_height

    def create_room_tile(self, room):
        """Плитка комнаты: тап — открыть, долгое нажатие — поделиться / удалить."""
        container_width = self.rooms_container.width if self.rooms_container.width > 0 else self.width
        tile_width = (container_width - dp(30)) / 2 if container_width > 0 else dp(150)

        from models import CeilingLayout
        room_area = 0.0
        if room.walls and len(room.walls) >= 3:
            try:
                temp_layout = CeilingLayout(room)
                temp_layout.calculate_layout()
                room_area = temp_layout.room_area_sqm if hasattr(temp_layout, "room_area_sqm") else 0.0
            except Exception as e:
                print(f"Ошибка расчета площади: {e}")

        button_text = f"{room.name}\n{room_area:.1f} м²" if room_area > 0 else room.name
        project_id = self.manager.current_project.id if self.manager.current_project else None
        rid = room.id

        return LongPressTile(
            tile_width,
            button_text,
            on_open=lambda r=room: self.open_room_editor(r),
            on_share=lambda r=room: share_room(project_id, r),
            on_delete=lambda: self.confirm_delete_room(rid),
        )

    def open_room_editor(self, room):
        """Открывает редактор комнаты"""
        self.manager.current_room = room
        # ← КРИТИЧНО: если комната уже имеет стены, пропускаем редактор
        if room.walls and len(room.walls) >= 3:
            self.manager.current = 'layout'
        else:
            self.manager.current = 'room_editor'

    def confirm_delete_room(self, room_id):
        """Показывает диалог подтверждения удаления комнаты."""
        content = BoxLayout(orientation='vertical',
                            spacing=dp(10), padding=dp(10))
        from ui_style import style_popup_card
        style_popup_card(content, radius_dp=18)
        message = Label(text='Вы точно хотите удалить?', font_size=dp(16), color=COLORS["text"])

        btn_layout = BoxLayout(spacing=dp(10))

        modal = None

        def do_delete(dt):
            # Найдем комнату в списке объектов и удалим её
            room_to_remove = None
            for r in self.manager.current_project.rooms:
                if r.id == room_id:
                    room_to_remove = r
                    break
            if room_to_remove:
                self.manager.current_project.rooms.remove(room_to_remove)
                # Сохраняем проект (это удалит комнату из БД)
                save_project(self.manager.current_project)

                # КРИТИЧЕСКОЕ ИЗМЕНЕНИЕ: перезагружаем проект из БД для актуализации данных
                if self.manager.current_project.id:
                    updated_project = load_project(
                        self.manager.current_project.id)
                    if updated_project:
                        self.manager.current_project = updated_project

                print(
                    f"Комната с ID {room_id} удалена из проекта и сохранена в БД.")
                # Обновляем сетку
                self.update_rooms_grid()
                if modal:
                    modal.dismiss()
            else:
                print(
                    f"Комната с ID {room_id} не найдена в локальном списке проекта для удаления.")
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

    def show_add_room_dialog(self, instance):
        """Показывает диалог добавления комнаты"""
        content = BoxLayout(orientation='vertical',
                            spacing=dp(10), padding=dp(20))

        label = Label(text='Название комнаты:', font_size=dp(16), color=COLORS["text"])
        name_input = TextInput(
            multiline=False,
            font_size=dp(18),
        )
        style_text_input(name_input)
        input_row = make_input_row(name_input)

        btn_layout = BoxLayout(spacing=dp(10))

        btn_confirm = RoundedButton(
            text='Создать',
            color=(1, 1, 1, 1)
        )
        btn_confirm.corner_radius = dp(12)
        apply_btn_style(btn_confirm, role="primary")
        btn_cancel = RoundedButton(text='Отмена')
        btn_cancel.corner_radius = dp(12)
        apply_btn_style(btn_cancel, role="secondary")

        modal = None

        def create_room(inst):
            name = name_input.text.strip()
            if name:
                from models import Room
                room = Room(name)
                # Добавляем комнату в текущий проект
                self.manager.current_project.rooms.append(room)
                # Сохраняем проект в БД после добавления комнаты
                save_project(self.manager.current_project)

                # КРИТИЧЕСКОЕ ИЗМЕНЕНИЕ: перезагружаем проект из БД, чтобы получить актуальные ID комнат
                if self.manager.current_project.id:
                    updated_project = load_project(
                        self.manager.current_project.id)
                    if updated_project:
                        self.manager.current_project = updated_project

                # Обновляем сетку
                self.update_rooms_grid()
                if modal:
                    modal.dismiss()

        btn_confirm.bind(on_press=create_room)
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

    def go_back(self, instance):
        """Возврат к проектам"""
        # Сохраняем проект при выходе с экрана комнат (если нужно)
        # save_project(self.manager.current_project)
        self.manager.current = 'projects'
