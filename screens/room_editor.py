# screens/room_editor.py
from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.gridlayout import GridLayout
from kivy.uix.popup import Popup
from kivy.uix.textinput import TextInput
from kivy.metrics import dp
from kivy.uix.floatlayout import FloatLayout
from widgets.grid_widget import GridWidget
from kivy.uix.stencilview import StencilView
from database import save_project # Импортируем функцию сохранения

class RoomEditorScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        main_layout = BoxLayout(orientation='vertical', spacing=dp(2))

        # Панель инструментов
        toolbar = self.create_toolbar()

        # Область рисования
        self.grid_widget = GridWidget(size_hint=(1, 0.85))
        self.grid_widget.scale = 0.5  # Увеличиваем начальный масштаб
        # Привязываем изменение масштаба к обновлению информации
        self.grid_widget.bind(scale=lambda instance, value: self.update_info())

        # Панель информации
        info_panel = self.create_info_panel()

        # Панель масштаба
        scale_panel = self.create_scale_panel()

        # Собираем интерфейс
        main_layout.add_widget(toolbar)
        main_layout.add_widget(self.grid_widget)
        main_layout.add_widget(info_panel)
        # Добавляем панель масштаба поверх всего
        overlay = FloatLayout()
        overlay.add_widget(main_layout)
        overlay.add_widget(scale_panel)
        self.add_widget(overlay)

        # Обновляем информацию при изменении
        self.update_info()


    def on_pre_enter(self):
        """Вызывается перед входом на экран - загружаем комнату"""
        current_room = self.manager.current_room
        if current_room:
            # Загружаем стены комнаты в редактор
            self.grid_widget.walls = current_room.walls.copy()
            # Находим последнюю точку (конец последней стены) для установки позиции
            if current_room.walls:
                last_wall = current_room.walls[-1]
                # Берем координаты конца последней стены
                self.grid_widget.current_pos_cm = [last_wall[2], last_wall[3]]
                # Если у комнаты есть last_position, используем её
                if hasattr(current_room, 'last_position') and current_room.last_position:
                    self.grid_widget.current_pos_cm = current_room.last_position
            else:
                # Если стен нет, ставим в начальную позицию
                self.grid_widget.current_pos_cm = [0, 0]

            # Перерисовываем
            self.grid_widget.canvas.clear()
            self.grid_widget.draw_editor()  # ИЗМЕНИТЬ draw_grid на draw_editor
            self.update_info()

    def create_toolbar(self):
        toolbar = BoxLayout(
            size_hint=(1, 0.1),
            spacing=dp(5),
            padding=dp(5)
        )

        # Стрелки
        self.arrows_container = BoxLayout(size_hint=(0.4, 1))
        self.create_arrow_buttons()

        # Назад/Вперед
        undo_redo_container = BoxLayout(
            orientation='vertical',
            size_hint=(0.2, 1),
            spacing=dp(2)
        )
        self.btn_undo = Button(
            text='Назад',
            font_size=dp(14),
            size_hint=(1, 0.5),
            background_color=(0.8, 0.8, 0.8, 1)
        )
        self.btn_undo.bind(on_press=self.undo_action)
        self.btn_redo = Button(
            text='Вперед',
            font_size=dp(14),
            size_hint=(1, 0.5),
            background_color=(0.8, 0.8, 0.8, 1)
        )
        self.btn_redo.bind(on_press=self.redo_action)
        undo_redo_container.add_widget(self.btn_undo)
        undo_redo_container.add_widget(self.btn_redo)

        # Действия
        actions_container = BoxLayout(
            orientation='vertical',
            size_hint=(0.4, 1),
            spacing=dp(2)
        )
        btn_layout = Button(
            text='Раскладка',
            font_size=dp(14),
            size_hint=(1, 0.5)
        )
        btn_layout.bind(on_press=self.show_layout)
        btn_exit = Button(
            text='Выход',
            font_size=dp(14),
            size_hint=(1, 0.5)
        )
        btn_exit.bind(on_press=self.exit_editor)
        actions_container.add_widget(btn_layout)
        actions_container.add_widget(btn_exit)

        toolbar.add_widget(self.arrows_container)
        toolbar.add_widget(undo_redo_container)
        toolbar.add_widget(actions_container)

        return toolbar

    def create_scale_panel(self):
        """Панель масштабирования"""
        scale_panel = BoxLayout(
            orientation='vertical',
            size_hint=(None, None),
            size=(dp(60), dp(120)),
            pos_hint={'right': 1, 'top': 0.8},
            spacing=dp(5),
            padding=dp(5)
        )
        btn_zoom_in = Button(
            text='+',
            font_size=dp(24),
            size_hint=(1, 0.5)
        )
        btn_zoom_in.bind(on_press=self.zoom_in)
        btn_zoom_out = Button(
            text='-',
            font_size=dp(24),
            size_hint=(1, 0.5)
        )
        btn_zoom_out.bind(on_press=self.zoom_out)

        scale_panel.add_widget(btn_zoom_in)
        scale_panel.add_widget(btn_zoom_out)

        return scale_panel

    def create_info_panel(self):
        info_panel = BoxLayout(
            size_hint=(1, 0.05),
            padding=dp(10)
        )
        self.info_label = Label(
            text='Точка: (0, 0) см | Стены: 0 | Масштаб: 0.2x',
            font_size=dp(12),
            color=(0, 0, 0, 1)  # Черный цвет текста
        )
        info_panel.add_widget(self.info_label)
        return info_panel

    def create_arrow_buttons(self):
        """Создает 8 кнопок-стрелок"""
        grid = GridLayout(cols=3, rows=3, spacing=dp(2))
        arrows = [
            ('↖', 'up_left'), ('^', 'up'), ('↗', 'up_right'),
            ('<-', 'left'), ('•', 'center'), ('->', 'right'),
            ('↙', 'down_left'), ('v', 'down'), ('↘', 'down_right')
        ]
        for symbol, direction in arrows:
            if direction == 'center':
                btn = Button(
                    text=symbol,
                    font_size=dp(20),
                    background_color=(0.8, 0.8, 0.8, 1),
                    disabled=True
                )
            else:
                btn = Button(
                    text=symbol,
                    font_size=dp(20),
                    on_press=lambda instance, d=direction: self.start_add_wall(
                        d)
                )
            grid.add_widget(btn)

        self.arrows_container.clear_widgets()
        self.arrows_container.add_widget(grid)

    def start_add_wall(self, direction):
        """Запрашивает длину стены"""
        content = BoxLayout(orientation='vertical',
                            spacing=dp(10), padding=dp(10))

        label = Label(text=f"Длина стены (см) в направлении {direction}:")
        length_input = TextInput(
            multiline=False,
            input_filter='int',
            text='100'
        )

        btn_layout = BoxLayout(spacing=dp(10))

        btn_confirm = Button(text='Подтвердить')
        btn_cancel = Button(text='Отмена')

        def confirm(instance):
            try:
                length = int(length_input.text)
                if length > 0:
                    self.grid_widget.add_wall(direction, length)
                    self.update_info()
                    popup.dismiss()
            except ValueError:
                pass
        btn_confirm.bind(on_press=confirm)
        btn_cancel.bind(on_press=lambda x: popup.dismiss())

        btn_layout.add_widget(btn_cancel)
        btn_layout.add_widget(btn_confirm)

        content.add_widget(label)
        content.add_widget(length_input)
        content.add_widget(btn_layout)

        popup = Popup(
            title='Ввод длины стены',
            content=content,
            size_hint=(0.8, 0.3)
        )
        popup.open()

    def update_info(self):
        """Обновляет информационную панель"""
        x, y = self.grid_widget.current_pos_cm
        walls_count = len(self.grid_widget.walls)
        scale = self.grid_widget.scale
        self.info_label.text = f'Точка: ({int(x)}, {int(y)}) см | Стены: {walls_count} | Масштаб: {scale:.1f}x'

    def undo_action(self, instance):
        if self.grid_widget.undo():
            self.update_info()
            # Активируем кнопку "Вперед"
            self.btn_redo.disabled = False
            self.btn_redo.background_color = (0.2, 0.6, 1, 1)

    def redo_action(self, instance):
        if self.grid_widget.redo():
            self.update_info()

    def zoom_in(self, instance):
        """Увеличивает масштаб"""
        self.grid_widget.scale = min(1.0, self.grid_widget.scale + 0.1)
        self.grid_widget.canvas.clear()
        self.grid_widget.draw_editor()
        self.update_info()

    def zoom_out(self, instance):
        """Уменьшает масштаб"""
        self.grid_widget.scale = max(0.1, self.grid_widget.scale - 0.1)
        self.grid_widget.canvas.clear()
        self.grid_widget.draw_editor()
        self.update_info()

    def show_layout(self, instance):
        """Переход к раскладке 60×60 см с сохранением комнаты"""
        # Сохраняем стены и текущую позицию в текущую комнату перед переходом
        current_room = self.manager.current_room
        if current_room:
            current_room.walls = self.grid_widget.walls.copy()
            current_room.last_position = self.grid_widget.current_pos_cm.copy() # Сохраняем позицию
            # Сохраняем проект в БД
            save_project(self.manager.current_project)

        # Переходим к раскладке
        self.manager.current = 'layout'

    def exit_editor(self, instance):
        """Выход из редактора с сохранением"""
        current_room = self.manager.current_room
        if current_room:
            current_room.walls = self.grid_widget.walls.copy()
            current_room.last_position = self.grid_widget.current_pos_cm.copy()
            # Сохраняем проект в БД
            save_project(self.manager.current_project)

        self.manager.current = 'rooms'
