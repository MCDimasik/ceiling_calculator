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
from database import save_project


class RoomEditorScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        main_layout = BoxLayout(orientation='vertical', spacing=dp(2))
        toolbar = self.create_toolbar()
        self.grid_widget = GridWidget(size_hint=(1, 1))
        self.grid_widget.scale = 0.5
        # Обновляем инфо-панель при ЛЮБОМ изменении геометрии комнаты
        self.grid_widget.on_change = self.update_info
        info_panel = self.create_info_panel()
        main_layout.add_widget(toolbar)
        main_layout.add_widget(self.grid_widget)
        main_layout.add_widget(info_panel)
        scale_panel = self.create_scale_panel()
        overlay = FloatLayout()
        overlay.add_widget(main_layout)
        overlay.add_widget(scale_panel)
        self.add_widget(overlay)
        self.update_info()

    def on_pre_enter(self):
        """← ИСПРАВЛЕНО: Очищаем undo stack при загрузке НОВОЙ комнаты"""
        current_room = self.manager.current_room
        if current_room:
            self.grid_widget.walls = current_room.walls.copy()
            if current_room.walls:
                last_wall = current_room.walls[-1]
                self.grid_widget.current_pos_cm = [last_wall[2], last_wall[3]]
            if hasattr(current_room, 'last_position') and current_room.last_position:
                self.grid_widget.current_pos_cm = current_room.last_position
            else:
                self.grid_widget.current_pos_cm = [0, 0]
            # ← КРИТИЧНО: Правильно определяем, закрыта ли комната
            # Комната закрыта только если первая и последняя точки совпадают
            self.grid_widget.room_closed = self.grid_widget.is_room_closed() if hasattr(self.grid_widget, 'is_room_closed') else len(current_room.walls) >= 3
            self.grid_widget.clear_undo_stack()  # ← Теперь создает ОДНО состояние
            self.grid_widget.canvas.clear()
            self.grid_widget.draw_editor()
            self.update_info()

    def create_toolbar(self):
        toolbar = BoxLayout(size_hint=(1, 0.14), spacing=dp(2), padding=dp(2))
        self.arrows_container = BoxLayout(
            size_hint=(0.35, 1), spacing=dp(3), padding=dp(3))
        self.create_arrow_buttons()
        undo_redo_container = BoxLayout(
            orientation='vertical', size_hint=(0.2, 1), spacing=dp(3), padding=dp(2))
        self.btn_undo = Button(text='Назад', font_size=dp(
            12), size_hint=(1, 0.5), background_color=(0.8, 0.8, 0.8, 1))
        self.btn_undo.bind(on_press=self.undo_action)
        self.btn_redo = Button(text='Вперед', font_size=dp(
            12), size_hint=(1, 0.5), background_color=(0.8, 0.8, 0.8, 1))
        self.btn_redo.bind(on_press=self.redo_action)
        undo_redo_container.add_widget(self.btn_undo)
        undo_redo_container.add_widget(self.btn_redo)
        actions_container = BoxLayout(orientation='vertical', size_hint=(
            0.35, 1), spacing=dp(3), padding=dp(2))
        btn_layout = Button(
            text='Раскладка', font_size=dp(12), size_hint=(1, 0.5))
        btn_layout.bind(on_press=self.show_layout)
        btn_exit = Button(text='Выход', font_size=dp(12), size_hint=(1, 0.5))
        btn_exit.bind(on_press=self.exit_editor)
        actions_container.add_widget(btn_layout)
        actions_container.add_widget(btn_exit)
        toolbar.add_widget(self.arrows_container)
        toolbar.add_widget(undo_redo_container)
        toolbar.add_widget(actions_container)
        return toolbar

    def create_scale_panel(self):
        scale_panel = BoxLayout(orientation='vertical', size_hint=(None, None), size=(
            dp(60), dp(120)), pos_hint={'right': 1, 'top': 0.85}, spacing=dp(5), padding=dp(5))
        btn_zoom_in = Button(text='+', font_size=dp(24), size_hint=(1, 0.5))
        btn_zoom_in.bind(on_press=self.zoom_in)
        btn_zoom_out = Button(text='-', font_size=dp(24), size_hint=(1, 0.5))
        btn_zoom_out.bind(on_press=self.zoom_out)
        scale_panel.add_widget(btn_zoom_in)
        scale_panel.add_widget(btn_zoom_out)
        return scale_panel

    def create_info_panel(self):
        info_panel = BoxLayout(size_hint=(1, 0.07), padding=dp(10))
        self.info_label = Label(
            text='Точка: (0, 0) см | Стены: 0 | Площадь: —', font_size=dp(12), color=(0, 0, 0, 1))
        info_panel.add_widget(self.info_label)
        return info_panel

    def create_arrow_buttons(self):
        grid = GridLayout(cols=3, rows=3, spacing=dp(2))
        arrows = [
            ('↖', 'up_left'), ('^', 'up'), ('↗', 'up_right'),
            ('<-', 'left'), ('•', 'center'), ('->', 'right'),
            ('↙', 'down_left'), ('v', 'down'), ('↘', 'down_right')
        ]
        for symbol, direction in arrows:
            if direction == 'center':
                btn = Button(text=symbol, font_size=dp(
                    20), background_color=(0.8, 0.8, 0.8, 1), disabled=True)
            else:
                btn = Button(text=symbol, font_size=dp(
                    20), on_press=lambda instance, d=direction: self.start_add_wall(d))
            grid.add_widget(btn)
        self.arrows_container.clear_widgets()
        self.arrows_container.add_widget(grid)

    def start_add_wall(self, direction):
        content = BoxLayout(orientation='vertical',
                            spacing=dp(10), padding=dp(10))
        label = Label(text=f"Длина стены (см) в направлении {direction}:")
        length_input = TextInput(
            multiline=False, input_filter='float', text='')
        btn_layout = BoxLayout(spacing=dp(10))
        btn_confirm = Button(text='Подтвердить')
        btn_cancel = Button(text='Отмена')

        def confirm(instance):
            try:
                length = float(length_input.text)
                if length > 0:
                    length = round(length, 1)
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
        popup = Popup(title='Ввод длины стены',
                      content=content, size_hint=(0.8, 0.3))
        popup.open()

    def update_info(self):
        x, y = self.grid_widget.current_pos_cm
        walls_count = len(self.grid_widget.walls)
        room_area = 0.0
        if walls_count >= 3:
            try:
                from models import CeilingLayout, Room
                temp_room = Room("temp")
                temp_room.walls = self.grid_widget.walls.copy()
                temp_layout = CeilingLayout(temp_room)
                temp_layout.calculate_layout()
                room_area = temp_layout.room_area_sqm if hasattr(
                    temp_layout, 'room_area_sqm') else 0.0
            except Exception as e:
                print(f"Ошибка расчета площади: {e}")
                room_area = 0.0
        if room_area > 0:
            self.info_label.text = f'Точка: ({x:.1f}, {y:.1f}) см | Стены: {walls_count} | Площадь: {room_area:.1f} м²'
        else:
            self.info_label.text = f'Точка: ({x:.1f}, {y:.1f}) см | Стены: {walls_count} | Площадь: —'

    def undo_action(self, instance):
        if self.grid_widget.undo():
            self.update_info()
            if self.grid_widget.redo_stack:
                self.btn_redo.disabled = False
                self.btn_redo.background_color = (0.2, 0.6, 1, 1)
            else:
                self.btn_redo.disabled = True
                self.btn_redo.background_color = (0.8, 0.8, 0.8, 1)

    def redo_action(self, instance):
        if self.grid_widget.redo():
            self.update_info()
            if not self.grid_widget.redo_stack:
                self.btn_redo.disabled = True
                self.btn_redo.background_color = (0.8, 0.8, 0.8, 1)

    def zoom_in(self, instance):
        self.grid_widget.scale = min(1.0, self.grid_widget.scale + 0.1)
        self.grid_widget.canvas.clear()
        self.grid_widget.draw_editor()
        self.update_info()

    def zoom_out(self, instance):
        self.grid_widget.scale = max(0.1, self.grid_widget.scale - 0.1)
        self.grid_widget.canvas.clear()
        self.grid_widget.draw_editor()
        self.update_info()

    def show_layout(self, instance):
        current_room = self.manager.current_room
        if current_room:
            current_room.walls = self.grid_widget.walls.copy()
            current_room.last_position = self.grid_widget.current_pos_cm.copy()
            save_project(self.manager.current_project)
            self.manager.current = 'layout'

    def exit_editor(self, instance):
        current_room = self.manager.current_room
        if current_room:
            current_room.walls = self.grid_widget.walls.copy()
            current_room.last_position = self.grid_widget.current_pos_cm.copy()
            save_project(self.manager.current_project)
            self.manager.current = 'rooms'
