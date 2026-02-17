# screens/rooms_screen.py
from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.gridlayout import GridLayout
from kivy.uix.scrollview import ScrollView
from kivy.uix.popup import Popup
from kivy.uix.textinput import TextInput
from kivy.metrics import dp
from kivy.graphics import Color, Rectangle, Line
from kivy.clock import Clock
# Импортируем delete_room_from_project и load_project
from database import save_project, delete_room_from_project, load_project
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.relativelayout import RelativeLayout


class RoomsScreen(Screen):
    """Экран со списком комнат в проекте"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.title_label = None

        main_layout = BoxLayout(orientation='vertical', spacing=dp(2))

        # Панель инструментов
        toolbar = self.create_toolbar()

        # Основная область с комнатами
        content_area = self.create_content_area()

        main_layout.add_widget(toolbar)
        main_layout.add_widget(content_area)
        self.add_widget(main_layout)
        self.bind(size=self.on_size)

    def on_size(self, *args):
        """Обновляет размеры плиток при изменении размера окна"""
        if hasattr(self, 'rooms_container') and len(self.rooms_container.children) > 0:
            # Пересчитываем размеры плиток при изменении размера окна
            Clock.schedule_once(lambda dt: self.update_rooms_grid(), 0.1)

    def on_pre_enter(self):
        """Вызывается перед входом на экран - перезагружаем проект и обновляем сетку."""
        if hasattr(self.manager, 'current_project') and self.manager.current_project:
            project_id = self.manager.current_project.id
            if project_id:
                loaded_project = load_project(project_id)
                if loaded_project:
                    self.manager.current_project = loaded_project
        # Убираем отложенное обновление здесь, так как оно может создавать гонку состояний
        self.update_rooms_grid()  # <-- Вызываем напрямую, а не через Clock

    def create_toolbar(self):
        """Создает панель инструментов"""
        toolbar = BoxLayout(
            size_hint=(1, 0.15),
            padding=dp(10),
            spacing=dp(10)  # ← КРИТИЧНО: отступ между кнопками
        )

        # Кнопка "Назад" к проектам
        btn_back = Button(
            text='← Назад',
            font_size=dp(14),
            size_hint=(0.3, 1),
            background_color=(0.8, 0.8, 0.8, 1)
        )
        btn_back.bind(on_press=self.go_back)

        # Заголовок (будет обновляться)
        self.title_label = Label(
            text='Комнаты',
            font_size=dp(16),
            size_hint=(0.4, 1),
            color=(0, 0, 0, 1),
            halign='center',
            valign='middle'
        )
        self.title_label.bind(size=self.title_label.setter('text_size'))

        # Кнопка "Добавить комнату" с переносом текста
        btn_add = Button(
            text='+ Новая\nкомната',
            font_size=dp(12),
            size_hint=(0.3, 1),
            background_color=(0.2, 0.6, 1, 1),
            color=(1, 1, 1, 1),
            halign='center',
            valign='middle'
        )
        btn_add.bind(on_press=self.show_add_room_dialog)

        # Настраиваем перенос текста для кнопки
        def update_btn_text(instance, size):
            instance.text_size = (size[0] - dp(10), None)
        btn_add.bind(size=update_btn_text)

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
                        total_area += temp_layout.room_area_sqm if hasattr(
                            temp_layout, 'room_area_sqm') else 0.0
                except Exception as e:
                    print(f"Ошибка расчета площади: {e}")
                    continue

            # ← КРИТИЧНО: правильное форматирование заголовка (3 строки)
            if total_area > 0:
                self.title_label.text = f'Комнаты:\n{project.name}\n{total_area:.1f} м²'
            else:
                self.title_label.text = f'Комнаты:\n{project.name}'

            self.title_label.font_size = dp(14)
            self.title_label.halign = 'center'
            self.title_label.valign = 'middle'
            self.title_label.max_lines = 3
            self.title_label.text_size = (
                self.title_label.width, self.title_label.height * 3)

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
                    text='Нет комнат\nНажмите "+ Новая комната"',
                    font_size=dp(16),
                    color=(0.5, 0.5, 0.5, 1),
                    halign='center',
                    valign='middle',
                    size_hint_y=None
                )
                empty_label.bind(size=empty_label.setter('text_size'))
                empty_label.height = self.height * 0.3
                self.rooms_container.add_widget(empty_label)
                self.rooms_container.height = self.rooms_container.minimum_height

    def create_room_tile(self, room):
        """Создает плитку для комнаты с кнопкой удаления"""
        container_width = self.rooms_container.width if self.rooms_container.width > 0 else self.width
        tile_width = (container_width - dp(30)) / \
            2 if container_width > 0 else dp(150)

        tile_layout = RelativeLayout(
            size_hint=(None, None),
            size=(tile_width, tile_width)
        )

        # ← КРИТИЧНО: безопасный расчет площади комнаты
        from models import CeilingLayout
        room_area = 0.0
        if room.walls and len(room.walls) >= 3:
            try:
                temp_layout = CeilingLayout(room)
                # ← КРИТИЧНО: Вызываем calculate_layout() для расчета площади!
                temp_layout.calculate_layout()
                room_area = temp_layout.room_area_sqm if hasattr(
                    temp_layout, 'room_area_sqm') else 0.0
            except Exception as e:
                print(f"Ошибка расчета площади: {e}")
                room_area = 0.0

        # ← КРИТИЧНО: правильное форматирование текста (2 строки)
        if room_area > 0:
            button_text = f"{room.name}\n{room_area:.1f} м²"
        else:
            button_text = room.name

        tile_button = Button(
            background_color=(0.95, 0.95, 0.95, 1),
            background_normal='',
            text=button_text,
            font_size=dp(16),
            color=(0, 0, 0, 1),
            halign='center',
            valign='middle',
            text_size=(tile_width - dp(20), tile_width - dp(20)),
            shorten=False,
            max_lines=2
        )

        # ← КРИТИЧНО: Привязка для обновления text_size
        tile_button.bind(
            size=lambda inst, size: setattr(
                inst, 'text_size', (size[0] - dp(20), size[1] - dp(20)))
        )

        tile_button.bind(on_press=lambda instance,
                         r=room: self.open_room_editor(r))

        # Кнопка удаления
        delete_container = BoxLayout(
            size_hint=(None, None),
            size=(dp(25), dp(25)),
            pos_hint={'right': 1, 'top': 1}
        )
        delete_button = Button(
            text='X',
            font_size=dp(12),
            size_hint=(1, 1),
            background_color=(0.8, 0.2, 0.2, 1),
            color=(1, 1, 1, 1),
            halign='center',
            valign='middle'
        )
        delete_button.bind(on_press=lambda instance,
                           r_id=room.id: self.confirm_delete_room(r_id))
        delete_container.add_widget(delete_button)

        tile_layout.add_widget(tile_button)
        tile_layout.add_widget(delete_container)
        return tile_layout

    def open_room_editor(self, room):
        """Открывает редактор комнаты"""
        self.manager.current_room = room
        # ← КРИТИЧНО: если комната уже имеет стены (3+), пропускаем редактор
        if room.walls and len(room.walls) >= 3:
            self.manager.current = 'layout'
        else:
            self.manager.current = 'room_editor'

    def confirm_delete_room(self, room_id):
        """Показывает диалог подтверждения удаления комнаты."""
        content = BoxLayout(orientation='vertical',
                            spacing=dp(10), padding=dp(10))
        message = Label(text='Вы точно хотите удалить?', font_size=dp(16))

        btn_layout = BoxLayout(spacing=dp(10), size_hint=(1, 0.3))

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
                popup.dismiss()  # <-- ВАЖНО: добавлено закрытие popup
            else:
                print(
                    f"Комната с ID {room_id} не найдена в локальном списке проекта для удаления.")
                popup.dismiss()  # <-- ВАЖНО: добавлено закрытие popup

        def cancel_delete(dt):
            popup.dismiss()

        btn_delete = Button(text='Удалить', background_color=(
            0.8, 0.2, 0.2, 1), color=(1, 1, 1, 1))
        btn_cancel = Button(text='Отмена')

        btn_delete.bind(on_press=do_delete)
        btn_cancel.bind(on_press=cancel_delete)

        btn_layout.add_widget(btn_cancel)
        btn_layout.add_widget(btn_delete)

        content.add_widget(message)
        content.add_widget(btn_layout)

        popup = Popup(title='Подтверждение удаления',
                      content=content,
                      size_hint=(0.6, 0.4))
        popup.open()

    def show_add_room_dialog(self, instance):
        """Показывает диалог добавления комнаты"""
        content = BoxLayout(orientation='vertical',
                            spacing=dp(10), padding=dp(20))

        label = Label(text='Название комнаты:', font_size=dp(16))
        name_input = TextInput(
            multiline=False,
            font_size=dp(18),
            size_hint=(1, 0.4)
        )

        btn_layout = BoxLayout(spacing=dp(10), size_hint=(1, 0.4))

        btn_confirm = Button(
            text='Создать',
            background_color=(0.2, 0.6, 1, 1),
            color=(1, 1, 1, 1)
        )
        btn_cancel = Button(text='Отмена')

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
                popup.dismiss()

        btn_confirm.bind(on_press=create_room)
        btn_cancel.bind(on_press=lambda x: popup.dismiss())

        btn_layout.add_widget(btn_cancel)
        btn_layout.add_widget(btn_confirm)

        content.add_widget(label)
        content.add_widget(name_input)
        content.add_widget(btn_layout)

        popup = Popup(
            title='Новая комната',
            content=content,
            size_hint=(0.8, 0.4)
        )
        popup.open()

    def go_back(self, instance):
        """Возврат к проектам"""
        # Сохраняем проект при выходе с экрана комнат (если нужно)
        # save_project(self.manager.current_project)
        self.manager.current = 'projects'
