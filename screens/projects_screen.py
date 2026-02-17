# screens/projects_screen.py
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
from database import init_db, load_all_projects, save_project, delete_project, load_project
# Добавим BoxLayout для компоновки кнопки X
from kivy.uix.boxlayout import BoxLayout
# Используем AnchorLayout для позиционирования X
from kivy.uix.relativelayout import RelativeLayout


class ProjectsScreen(Screen):
    """Экран со списком проектов (плиточный интерфейс)"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        # Инициализируем БД при запуске приложения
        init_db()

        main_layout = BoxLayout(orientation='vertical', spacing=dp(2))

        # Заголовок
        toolbar = self.create_toolbar()

        # Основная область с проектами
        content_area = self.create_content_area()

        main_layout.add_widget(toolbar)
        main_layout.add_widget(content_area)
        self.add_widget(main_layout)
        self.bind(size=self.on_size)

        # Тестовые данные больше не нужны
        self.projects = []
        # Отложенная загрузка проектов из БД
        Clock.schedule_once(lambda dt: self.load_projects(), 0.1)

    def on_size(self, *args):
        """Обновляет размеры плиток при изменении размера окна"""
        if hasattr(self, 'projects_container'):
            Clock.schedule_once(lambda dt: self.update_projects_grid(), 0.1)

    def create_toolbar(self):
        """Создает панель инструментов"""
        toolbar = BoxLayout(
            size_hint=(1, 0.15),
            padding=dp(10),
            spacing=dp(10)  # ← КРИТИЧНО: отступ между кнопками
        )
        
        # Кнопка "Назад" на главный экран
        btn_back = Button(
            text='← Назад',
            font_size=dp(14),
            size_hint=(0.3, 1),
            background_color=(0.8, 0.8, 0.8, 1)
        )
        btn_back.bind(on_press=self.go_back)

        # Заголовок
        title = Label(
            text='Мои проекты',
            font_size=dp(18),
            size_hint=(0.4, 1),
            color=(0, 0, 0, 1),
            halign='center',
            valign='middle'
        )
        title.bind(size=title.setter('text_size'))

        # Кнопка "Добавить проект" с переносом текста
        btn_add = Button(
            text='+ Новый\nпроект',
            font_size=dp(12),
            size_hint=(0.3, 1),
            background_color=(0.2, 0.6, 1, 1),
            color=(1, 1, 1, 1),
            halign='center',
            valign='middle'
        )
        btn_add.bind(on_press=self.show_add_project_dialog)

        # Настраиваем перенос текста для кнопки
        def update_btn_text(instance, size):
            instance.text_size = (size[0] - dp(10), None)
        btn_add.bind(size=update_btn_text)

        toolbar.add_widget(btn_back)
        toolbar.add_widget(title)
        toolbar.add_widget(btn_add)

        return toolbar

    def create_content_area(self):
        """Создает область с плитками проектов"""
        # Контейнер для сетки проектов
        self.projects_container = GridLayout(
            cols=2,
            spacing=dp(10),
            padding=dp(10),
            size_hint_y=None
        )
        self.projects_container.bind(
            minimum_height=self.projects_container.setter('height'))

        # Скролл для контейнера
        scroll = ScrollView()
        scroll.add_widget(self.projects_container)

        return scroll

    def load_projects(self):
        """Загружает проекты из базы данных"""
        self.projects = []
        db_projects = load_all_projects()
        if db_projects:
            self.projects = db_projects
        self.update_projects_grid()  # <-- Вызываем напрямую для немедленного обновления

    def update_projects_grid(self):
        """Обновляет сетку проектов"""
        self.projects_container.clear_widgets()

        # Устанавливаем параметры сетки
        self.projects_container.cols = 2
        self.projects_container.spacing = dp(10)
        self.projects_container.padding = dp(10)

        # Добавляем плитки проектов
        for project in self.projects:
            project_tile = self.create_project_tile(project)
            self.projects_container.add_widget(project_tile)

        # Автоматически устанавливаем высоту контейнера на основе содержимого
        self.projects_container.height = self.projects_container.minimum_height

        # Если проектов нет
        if not self.projects:
            empty_label = Label(
                text='Нет проектов\nНажмите "+ Новый проект"',
                font_size=dp(16),
                color=(0.5, 0.5, 0.5, 1),
                halign='center',
                valign='middle',
                size_hint_y=None
            )
            empty_label.bind(size=empty_label.setter('text_size'))
            empty_label.height = self.height * 0.3
            self.projects_container.add_widget(empty_label)
            self.projects_container.height = self.projects_container.minimum_height

    def create_project_tile(self, project):
        """Создает плитку для проекта с кнопкой удаления"""
        container_width = self.projects_container.width if self.projects_container.width > 0 else self.width
        tile_width = (container_width - dp(30)) / \
            2 if container_width > 0 else dp(150)

        tile_layout = RelativeLayout(
            size_hint=(None, None),
            size=(tile_width, tile_width)
        )

        # ← КРИТИЧНО: Загружаем проект с комнатами для расчета площади
        from database import load_project
        from models import CeilingLayout
        total_area = 0.0

        # Загружаем полный проект с комнатами
        full_project = load_project(project.id) if project.id else None
        if full_project and full_project.rooms:
            for room in full_project.rooms:
                try:
                    # ← КРИТИЧНО: Проверяем что стены есть
                    if room.walls and len(room.walls) >= 3:
                        temp_layout = CeilingLayout(room)
                        # ← КРИТИЧНО: Вызываем calculate_layout() для расчета площади!
                        temp_layout.calculate_layout()
                        total_area += temp_layout.room_area_sqm if hasattr(
                            temp_layout, 'room_area_sqm') else 0.0
                except Exception as e:
                    print(
                        f"Ошибка расчета площади для комнаты {room.name}: {e}")
                    continue

        # ← КРИТИЧНО: правильное форматирование текста (2 строки)
        if total_area > 0:
            button_text = f"{project.name}\n{total_area:.1f} м²"
        else:
            button_text = project.name

        tile_button = Button(
            background_color=(0.95, 0.95, 0.95, 1),
            background_normal='',
            text=button_text,
            font_size=dp(16),
            color=(0, 0, 0, 1),
            halign='center',
            valign='middle',
            text_size=(tile_width - dp(20), tile_width -
                       dp(20)),  # ← Оба размера!
            shorten=False,
            max_lines=2
        )

        # ← КРИТИЧНО: Привязка для обновления text_size при изменении размера кнопки
        tile_button.bind(
            size=lambda inst, size: setattr(
                inst, 'text_size', (size[0] - dp(20), size[1] - dp(20)))
        )

        tile_button.bind(on_press=lambda instance,
                         p=project: self.open_project(p))

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
                           p_id=project.id: self.confirm_delete_project(p_id))
        delete_container.add_widget(delete_button)

        tile_layout.add_widget(tile_button)
        tile_layout.add_widget(delete_container)
        return tile_layout

    def confirm_delete_project(self, project_id):
        """Показывает диалог подтверждения удаления проекта."""
        content = BoxLayout(orientation='vertical',
                            spacing=dp(10), padding=dp(10))
        message = Label(text='Вы точно хотите удалить?', font_size=dp(16))

        btn_layout = BoxLayout(spacing=dp(10), size_hint=(1, 0.3))

        def do_delete(dt):
            success = delete_project(project_id)
            if success:
                # Перезагрузить список проектов
                self.load_projects()
            popup.dismiss()

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

    def show_add_project_dialog(self, instance):
        """Показывает диалог добавления проекта"""
        content = BoxLayout(orientation='vertical',
                            spacing=dp(10), padding=dp(20))

        label = Label(text='Название проекта:', font_size=dp(16))
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

        def create_project(inst):
            name = name_input.text.strip()
            if name:
                from models import Project
                project = Project(name)
                # Сохраняем проект в БД
                save_project(project)
                # Перезагружаем проекты из БД для получения актуальных данных
                self.projects = load_all_projects()
                # Обновляем сетку
                self.update_projects_grid()
                popup.dismiss()

        btn_confirm.bind(on_press=create_project)
        btn_cancel.bind(on_press=lambda x: popup.dismiss())

        btn_layout.add_widget(btn_cancel)
        btn_layout.add_widget(btn_confirm)

        content.add_widget(label)
        content.add_widget(name_input)
        content.add_widget(btn_layout)

        popup = Popup(
            title='Новый проект',
            content=content,
            size_hint=(0.8, 0.4)
        )
        popup.open()

    def open_project(self, project):
        """Открывает проект (переход к экрану комнат)"""
        # Сохраняем текущий проект в менеджере экранов
        self.manager.current_project = project
        # Переходим к экрану комнат
        self.manager.current = 'rooms'

    def go_back(self, instance):
        """Возврат на главный экран"""
        self.manager.current = 'main'
