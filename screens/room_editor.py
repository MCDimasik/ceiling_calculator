# screens/room_editor.py
from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.popup import Popup
from kivy.uix.textinput import TextInput
from kivy.metrics import dp
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.widget import Widget
from kivy.graphics import Color, Ellipse, Line
from kivy.core.window import Window
from kivy.utils import platform
from kivy.clock import Clock
from widgets.grid_widget import GridWidget
from database import save_project
from ui_style import apply_btn_style, wrap_button_text, fit_button_font, COLORS, style_text_input, style_popup_card, make_input_row, configure_modal_footer_buttons
from widgets.ui_components import RoundedButton, IconRoundedButton
from widgets.ui_modal import RoundedModal
import math


class AnalogJoystick(Widget):
    """Круглый джойстик: тянем ручку, на отпускании получаем направление."""

    def __init__(self, on_direction=None, **kwargs):
        super().__init__(**kwargs)
        self.on_direction = on_direction
        self.active = False
        self.knob_dx = 0.0
        self.knob_dy = 0.0
        self.bind(pos=self._redraw, size=self._redraw)
        self._redraw()

    def _geometry(self):
        cx = self.center_x
        cy = self.center_y
        base_r = min(self.width, self.height) * 0.5
        knob_r = base_r * 0.33
        move_r = base_r - knob_r
        return cx, cy, base_r, knob_r, move_r

    def _redraw(self, *args):
        cx, cy, base_r, knob_r, _ = self._geometry()
        knob_x = cx + self.knob_dx
        knob_y = cy + self.knob_dy
        self.canvas.clear()
        with self.canvas:
            Color(0.2, 0.6, 1.0, 0.95)
            Ellipse(pos=(knob_x - knob_r, knob_y - knob_r), size=(knob_r * 2, knob_r * 2))

    def _update_knob_from_touch(self, touch):
        cx, cy, _, _, move_r = self._geometry()
        dx = touch.x - cx
        dy = touch.y - cy
        dist = math.hypot(dx, dy)
        if dist > move_r and dist > 0:
            scale = move_r / dist
            dx *= scale
            dy *= scale
        self.knob_dx = dx
        self.knob_dy = dy
        self._redraw()

    def _resolve_direction(self):
        threshold = max(dp(16), min(self.width, self.height) * 0.12)
        if abs(self.knob_dx) < threshold and abs(self.knob_dy) < threshold:
            return None
        if abs(self.knob_dx) >= abs(self.knob_dy):
            return 'right' if self.knob_dx > 0 else 'left'
        return 'up' if self.knob_dy > 0 else 'down'

    def _reset_knob(self):
        self.knob_dx = 0.0
        self.knob_dy = 0.0
        self._redraw()

    def on_touch_down(self, touch):
        cx, cy, base_r, _, _ = self._geometry()
        if (touch.x - cx) ** 2 + (touch.y - cy) ** 2 > base_r ** 2:
            return super().on_touch_down(touch)
        touch.grab(self)
        self.active = True
        self._update_knob_from_touch(touch)
        return True

    def on_touch_move(self, touch):
        if touch.grab_current is not self:
            return super().on_touch_move(touch)
        self._update_knob_from_touch(touch)
        return True

    def on_touch_up(self, touch):
        if touch.grab_current is not self:
            return super().on_touch_up(touch)
        touch.ungrab(self)
        direction = self._resolve_direction()
        self.active = False
        self._reset_knob()
        if direction and self.on_direction:
            self.on_direction(direction)
        return True


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
        joystick_panel = self.create_joystick_panel()
        overlay = FloatLayout()
        overlay.add_widget(main_layout)
        overlay.add_widget(scale_panel)
        overlay.add_widget(joystick_panel)
        self.add_widget(overlay)
        self.update_info()

    def on_pre_enter(self):
        """← ИСПРАВЛЕНО: Очищаем undo stack при загрузке НОВОЙ комнаты"""
        # Делаем отложенный redraw джойстика после layout-прохода,
        # чтобы он сразу стоял в корректной позиции.
        if hasattr(self, 'joystick'):
            Clock.schedule_once(lambda dt: self.joystick._redraw(), 0)

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
        toolbar = BoxLayout(size_hint=(1, None), height=dp(72), spacing=dp(6), padding=(dp(12), dp(6)))

        btn_back = RoundedButton(text='Назад', font_size=dp(14), size_hint=(0.25, 1))
        btn_back.corner_radius = dp(12)
        apply_btn_style(btn_back, role="secondary")
        wrap_button_text(btn_back, horizontal_padding_dp=6)
        fit_button_font(btn_back, max_font_dp=16, min_font_dp=12, horizontal_padding_dp=6)
        btn_back.bind(on_press=self.exit_editor)

        self.btn_undo = RoundedButton(text='Отмена', font_size=dp(14), size_hint=(0.25, 1))
        self.btn_undo.corner_radius = dp(12)
        apply_btn_style(self.btn_undo, role="secondary")
        wrap_button_text(self.btn_undo, horizontal_padding_dp=6)
        fit_button_font(self.btn_undo, max_font_dp=16, min_font_dp=12, horizontal_padding_dp=6)
        self.btn_undo.bind(on_press=self.undo_action)

        self.btn_redo = RoundedButton(text='Повтор', font_size=dp(14), size_hint=(0.25, 1))
        self.btn_redo.corner_radius = dp(12)
        apply_btn_style(self.btn_redo, role="secondary")
        wrap_button_text(self.btn_redo, horizontal_padding_dp=6)
        fit_button_font(self.btn_redo, max_font_dp=16, min_font_dp=12, horizontal_padding_dp=6)
        self.btn_redo.bind(on_press=self.redo_action)

        btn_layout = RoundedButton(text='Раскладка', font_size=dp(14), size_hint=(0.25, 1))
        btn_layout.corner_radius = dp(12)
        apply_btn_style(btn_layout, role="secondary")
        wrap_button_text(btn_layout, horizontal_padding_dp=6)
        fit_button_font(btn_layout, max_font_dp=16, min_font_dp=12, horizontal_padding_dp=6)
        btn_layout.bind(on_press=self.show_layout)

        toolbar.add_widget(btn_back)
        toolbar.add_widget(self.btn_undo)
        toolbar.add_widget(self.btn_redo)
        toolbar.add_widget(btn_layout)
        return toolbar

    def create_joystick_panel(self):
        panel = FloatLayout(
            size_hint=(None, None),
            size=(dp(170), dp(170)),
            pos_hint={'center_x': 0.5, 'y': 0.08},
        )
        self.joystick = AnalogJoystick(
            on_direction=self.start_add_wall,
            size_hint=(1, 1),
            pos_hint={'x': 0, 'y': 0}
        )
        panel.add_widget(self.joystick)
        return panel

    def create_scale_panel(self):
        scale_panel = BoxLayout(orientation='vertical', size_hint=(None, None), size=(
            dp(60), dp(120)), pos_hint={'right': 1, 'top': 0.85}, spacing=dp(5), padding=dp(5))
        btn_zoom_in = RoundedButton(text='+', font_size=dp(24), size_hint=(1, 0.5))
        btn_zoom_in.corner_radius = dp(12)
        apply_btn_style(btn_zoom_in, role="secondary")
        wrap_button_text(btn_zoom_in)
        btn_zoom_in.bind(on_press=lambda inst: self._flash_press(inst, self.zoom_in))

        btn_zoom_out = RoundedButton(text='-', font_size=dp(24), size_hint=(1, 0.5))
        btn_zoom_out.corner_radius = dp(12)
        apply_btn_style(btn_zoom_out, role="secondary")
        wrap_button_text(btn_zoom_out)
        btn_zoom_out.bind(on_press=lambda inst: self._flash_press(inst, self.zoom_out))
        scale_panel.add_widget(btn_zoom_in)
        scale_panel.add_widget(btn_zoom_out)
        return scale_panel

    def _flash_press(self, button, callback):
        apply_btn_style(button, role="primary")
        Clock.schedule_once(lambda dt: callback(button), 0.01)
        Clock.schedule_once(lambda dt: apply_btn_style(button, role="secondary"), 0.14)

    def create_info_panel(self):
        info_panel = BoxLayout(size_hint=(1, 0.07), padding=dp(10))
        self.info_label = Label(
            text='Точка: (0, 0) см | Стены: 0 | Площадь: —',
            font_size=dp(12),
            color=COLORS["text"],
        )
        # Чтобы `theme.refresh_widget_tree()` мог переокрасить этот текст без хаков.
        self.info_label._theme_slot = "text"
        info_panel.add_widget(self.info_label)
        return info_panel

    def start_add_wall(self, direction):
        direction_map = {
            "up": "вверх",
            "down": "вниз",
            "left": "влево",
            "right": "вправо",
            "up_left": "вверх-влево",
            "up_right": "вверх-вправо",
            "down_left": "вниз-влево",
            "down_right": "вниз-вправо",
        }
        direction_text = direction_map.get(direction, direction)
        content = BoxLayout(orientation='vertical',
                            spacing=dp(10), padding=dp(10))
        style_popup_card(content, radius_dp=18)
        label = Label(text=f"Направление: {direction_text}", color=COLORS["text"])
        length_input = TextInput(
            multiline=False, input_filter='float', text='')
        style_text_input(length_input)
        input_row = make_input_row(length_input)
        btn_layout = BoxLayout(spacing=dp(10))
        btn_confirm = RoundedButton(text='Подтвердить')
        btn_confirm.corner_radius = dp(12)
        apply_btn_style(btn_confirm, role="primary")
        btn_cancel = RoundedButton(text='Отмена')
        btn_cancel.corner_radius = dp(12)
        apply_btn_style(btn_cancel, role="secondary")

        def confirm(instance):
            try:
                length = float(length_input.text)
                if length > 0:
                    length = round(length, 1)
                    self.grid_widget.add_wall(direction, length)
                    self.update_info()
                    modal.dismiss()
            except ValueError:
                pass
        btn_confirm.bind(on_press=confirm)
        btn_cancel.bind(on_press=lambda x: modal.dismiss())
        btn_layout.add_widget(btn_cancel)
        btn_layout.add_widget(btn_confirm)
        configure_modal_footer_buttons(btn_layout, btn_cancel, btn_confirm)
        content.add_widget(label)
        content.add_widget(input_row)
        content.add_widget(btn_layout)
        modal = RoundedModal(content=content, card_size_hint=(0.88, None), card_height_dp=260)

        def update_popup_position(*args):
            # На Android часть устройств перекрывает Popup клавиатурой.
            # Поднимаем окно ввода, если клавиатура открыта.
            if platform != 'android':
                return
            kb_height = getattr(Window, 'keyboard_height', 0) or 0
            if kb_height > 0 and length_input.focus:
                modal.card.pos_hint = {'center_x': 0.5, 'center_y': 0.72}
            else:
                modal.card.pos_hint = {'center_x': 0.5, 'center_y': 0.55}

        def on_focus(instance, focused):
            # Даем кадр на открытие/закрытие клавиатуры и пересчитываем позицию
            from kivy.clock import Clock
            Clock.schedule_once(lambda dt: update_popup_position(), 0.05)

        def on_popup_open(*args):
            Window.bind(keyboard_height=update_popup_position)
            update_popup_position()

        def on_popup_dismiss(*args):
            try:
                Window.unbind(keyboard_height=update_popup_position)
            except Exception:
                pass

        length_input.bind(focus=on_focus)
        modal.bind(on_open=on_popup_open, on_dismiss=on_popup_dismiss)
        modal.open()

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
