# screens/layout_screen.py
from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.gridlayout import GridLayout
from kivy.metrics import dp
from kivy.uix.floatlayout import FloatLayout
from widgets.layout_widget import LayoutWidget
from widgets.ui_components import RoundedButton, IconRoundedButton
from ui_style import apply_btn_style, wrap_button_text
from models import CeilingLayout
from materials_calculator import effective_tile_counts_after_lights
from database import save_project  # Импортируем функцию сохранения
from kivy.clock import Clock  # ← ДОБАВИТЬ импорт
from kivy.resources import resource_find


class LayoutScreen(Screen):
    """Экран раскладки потолка 60×60 см"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.snap_mode = 0
        self.control_mode = 'grid'
        self.lights_mode = False

        # ← КРИТИЧНО: Переменные для авто-повтора кнопок
        self.repeat_event = None
        self.repeat_dx = 0
        self.repeat_dy = 0
        # Throttle для тяжелого пересчета раскладки
        self.layout_update_event = None
        self.layout_update_interval = 0.06  # ~16 FPS пересчета при drag

        main_layout = BoxLayout(orientation='vertical', spacing=dp(2))
        self.selected_corner = None

        # Панель инструментов
        toolbar = self.create_toolbar()

        # Область с раскладкой
        self.layout_widget = LayoutWidget(size_hint=(1, 1))

        # Панель управления
        control_panel = self.create_control_panel()

        # Панель статистики
        stats_panel = self.create_stats_panel()

        # Собираем в правильный порядок
        main_layout.add_widget(toolbar)
        main_layout.add_widget(self.layout_widget)
        main_layout.add_widget(control_panel)
        main_layout.add_widget(stats_panel)

        overlay = FloatLayout()
        overlay.add_widget(main_layout)
        self.light_panel = self.create_light_button_panel()
        overlay.add_widget(self.light_panel)
        self.add_widget(overlay)

    def toggle_dimensions(self, instance):
        """Переключает отображение размеров резаных плиток"""
        if not hasattr(self, 'layout_widget'):
            return

        # Инвертируем состояние
        self.layout_widget.show_dimensions = not self.layout_widget.show_dimensions

        # Меняем текст кнопки
        if self.layout_widget.show_dimensions:
            instance.text = 'Скрыть размеры плит'
            apply_btn_style(instance, role="primary")
        else:
            instance.text = 'Показать размеры плит'
            apply_btn_style(instance, role="secondary")

        # Перерисовываем
        self.layout_widget.draw_layout()

    def toggle_wall_dimensions(self, instance):
        """← НОВОЕ: Переключает отображение размеров стен"""
        if not hasattr(self, 'layout_widget'):
            return

        # Инвертируем состояние
        self.layout_widget.show_wall_dimensions = not self.layout_widget.show_wall_dimensions

        # Меняем текст кнопки
        if self.layout_widget.show_wall_dimensions:
            instance.text = 'Скрыть размеры стен'
            apply_btn_style(instance, role="primary")
        else:
            instance.text = 'Показать размеры стен'
            apply_btn_style(instance, role="secondary")

        # Перерисовываем
        self.layout_widget.draw_layout()

    def on_pre_enter(self):
        """Загружаем комнату при входе"""
        from kivy.clock import Clock
        # Гасим "призрачные" клики при слайд-переходе, чтобы кнопки не вспыхивали.
        for b in (getattr(self, "btn_back", None), getattr(self, "mode_button", None)):
            if b is not None:
                b.disabled = True
        Clock.schedule_once(lambda *_: self._enable_toolbar_buttons(), 0.25)
        Clock.schedule_once(self.load_room_data, 0.1)

    def _enable_toolbar_buttons(self):
        for b in (getattr(self, "btn_back", None), getattr(self, "mode_button", None)):
            if b is not None:
                b.disabled = False

    def load_room_data(self, dt):
        """Загружает данные комнаты с задержкой для правильной инициализации"""
        if not hasattr(self.manager, 'current_room') or not self.manager.current_room:
            print("Ошибка: current_room не установлен")
            return
        current_room = self.manager.current_room
        if current_room:
            if self.lights_mode:
                self.lights_mode = False
                self.layout_widget.light_placement_mode = False
                apply_btn_style(self.btn_light, role="secondary")
                self.control_mode = 'grid'
                self.layout_widget.dragging_enabled = True
                self.mode_button.text = 'Сетка'
            print(f"Загрузка комнаты: {current_room.name}")
            print(f"Стены: {len(current_room.walls)}")

            # Устанавливаем стены в виджет
            self.layout_widget.set_room(current_room.walls)

            # Создаем расчет раскладки
            self.ceiling_layout = CeilingLayout(current_room)
            # На всякий случай стартуем с чистым кэшем для новой комнаты
            if hasattr(self.ceiling_layout, '_layout_cache'):
                self.ceiling_layout._layout_cache.clear()

            # ← КРИТИЧНО: загружаем сохранённое смещение из комнаты
            self.ceiling_layout.grid_offset_x = getattr(
                current_room, 'grid_offset_x', 0)
            self.ceiling_layout.grid_offset_y = getattr(
                current_room, 'grid_offset_y', 0)
            self.layout_widget.grid_offset_x = self.ceiling_layout.grid_offset_x
            self.layout_widget.grid_offset_y = self.ceiling_layout.grid_offset_y
            self.layout_widget.set_light_fixtures(
                getattr(current_room, 'light_fixtures', []) or []
            )

            # Рассчитываем раскладку
            self.ceiling_layout.calculate_layout()

            # Передаем layout в виджет
            self.layout_widget.layout = self.ceiling_layout
            self.layout_widget.prune_outside_light_fixtures()

            # Устанавливаем callback для обновления статистики при движении сетки
            self.layout_widget.on_grid_move = self.on_grid_moved
            self.layout_widget.on_lights_changed = self.update_stats

            # Обновляем статистику
            self.update_stats()

            # Явно перерисовываем
            self.layout_widget.draw_layout()

    def on_grid_moved(self):
        """Callback при изменении смещения сетки (throttled пересчет)."""
        if not (hasattr(self.layout_widget, 'grid_offset_x') and hasattr(self.layout_widget, 'grid_offset_y')):
            return

        exact_offset_x = self.layout_widget.grid_offset_x
        exact_offset_y = self.layout_widget.grid_offset_y

        # Лейбл смещения обновляем сразу (дешево)
        if hasattr(self, 'offset_label'):
            offset_x_display = int(round(exact_offset_x))
            offset_y_display = int(round(exact_offset_y))
            self.offset_label.text = f'Смещение: {offset_x_display}×{offset_y_display} см'

        # Тяжелый расчет выполняем с throttle
        self._schedule_layout_update()

    def _schedule_layout_update(self, immediate=False):
        if immediate:
            if self.layout_update_event is not None:
                self.layout_update_event.cancel()
                self.layout_update_event = None
            self._apply_layout_update(0)
            return

        if self.layout_update_event is not None:
            return
        self.layout_update_event = Clock.schedule_once(
            self._apply_layout_update, self.layout_update_interval
        )

    def _apply_layout_update(self, dt):
        self.layout_update_event = None
        if not hasattr(self, 'ceiling_layout'):
            return
        self.ceiling_layout.grid_offset_x = self.layout_widget.grid_offset_x
        self.ceiling_layout.grid_offset_y = self.layout_widget.grid_offset_y
        self.ceiling_layout.calculate_layout()
        self.layout_widget.layout = self.ceiling_layout
        self.layout_widget.prune_outside_light_fixtures()
        self.update_stats()
        self.layout_widget.draw_layout()

    def create_toolbar(self):
        """Создает единый хедер с 4 равными кнопками."""
        toolbar = BoxLayout(
            size_hint=(1, None),
            height=dp(72),
            padding=(dp(12), dp(6)),
            spacing=dp(6)
        )

        font_path = resource_find("data/fonts/Roboto-Regular.ttf")

        btn_back = RoundedButton(
            text='Назад',
            font_size=dp(14),
            size_hint=(0.25, 1),
        )
        if font_path:
            btn_back.font_name = font_path
        self.btn_back = btn_back
        btn_back.corner_radius = dp(12)
        apply_btn_style(btn_back, role="secondary")
        wrap_button_text(btn_back, horizontal_padding_dp=6)
        btn_back.bind(on_press=lambda inst: self._flash_toolbar_button(inst, self.go_back))

        self.mode_button = RoundedButton(
            text='Сетка',
            font_size=dp(14),
            size_hint=(0.25, 1),
        )
        if font_path:
            self.mode_button.font_name = font_path
        self.mode_button.corner_radius = dp(12)
        apply_btn_style(self.mode_button, role="secondary")
        wrap_button_text(self.mode_button, horizontal_padding_dp=6)
        self.mode_button.bind(on_press=lambda inst: self._flash_toolbar_button(inst, self.toggle_control_mode))

        btn_reset = RoundedButton(
            text='Сброс',
            font_size=dp(14),
            size_hint=(0.25, 1),
        )
        if font_path:
            btn_reset.font_name = font_path
        # На некоторых рендерах шрифта (особенно в кириллице) кернинг может давать "слипание" букв.
        # Отключаем кернинг/лигатуры, если свойства поддерживаются текущей версией Kivy.
        for prop, val in (("font_kerning", False), ("kerning", 0), ("font_features", "")):
            try:
                if hasattr(btn_reset, prop):
                    setattr(btn_reset, prop, val)
            except Exception:
                pass
        btn_reset.corner_radius = dp(12)
        apply_btn_style(btn_reset, role="secondary")
        wrap_button_text(btn_reset, horizontal_padding_dp=6)
        btn_reset.bind(on_press=lambda inst: self._flash_toolbar_button(inst, self.reset_view))

        btn_materials = RoundedButton(
            text='Материал',
            font_size=dp(14),
            size_hint=(0.25, 1),
        )
        if font_path:
            btn_materials.font_name = font_path
        btn_materials.corner_radius = dp(12)
        apply_btn_style(btn_materials, role="secondary")
        wrap_button_text(btn_materials, horizontal_padding_dp=6)
        btn_materials.bind(on_press=lambda inst: self._flash_toolbar_button(inst, self.go_to_materials))

        toolbar.add_widget(btn_back)
        toolbar.add_widget(self.mode_button)
        toolbar.add_widget(btn_reset)
        toolbar.add_widget(btn_materials)

        return toolbar

    def _flash_toolbar_button(self, button, callback):
        apply_btn_style(button, role="primary")

        def run_action(dt):
            callback(button)

        def restore(dt):
            if button is self.mode_button:
                apply_btn_style(self.mode_button, role="secondary")
            else:
                apply_btn_style(button, role="secondary")

        Clock.schedule_once(run_action, 0.02)
        Clock.schedule_once(restore, 0.18)

    def go_to_materials(self, instance):
        """Быстрый переход к расчету материалов для текущей комнаты."""
        self._persist_room_layout_state()
        if hasattr(self, 'ceiling_layout'):
            self._schedule_layout_update(immediate=True)
        self.manager.current = 'materials_result'

    def create_light_button_panel(self):
        panel = BoxLayout(
            orientation='vertical',
            size_hint=(None, None),
            size=(dp(60), dp(54)),
            pos_hint={'right': 1, 'top': 0.88},
            spacing=dp(5),
            padding=dp(5),
        )
        self.btn_light = RoundedButton(text='Свет', font_size=dp(14), size_hint=(1, 1))
        self.btn_light.corner_radius = dp(12)
        apply_btn_style(self.btn_light, role="secondary")
        wrap_button_text(self.btn_light, horizontal_padding_dp=4)
        self.btn_light.bind(on_press=self.toggle_lights_mode)
        panel.add_widget(self.btn_light)
        return panel

    def toggle_lights_mode(self, instance):
        if self.lights_mode:
            self.lights_mode = False
            self.layout_widget.light_placement_mode = False
            apply_btn_style(self.btn_light, role="secondary")
            prev = getattr(self, '_prev_control_mode', 'grid')
            self.control_mode = prev
            self.layout_widget.dragging_enabled = prev == 'grid'
            if prev == 'pan_zoom':
                self.mode_button.text = 'Панорама'
            else:
                self.mode_button.text = 'Сетка'
        else:
            self._prev_control_mode = self.control_mode
            self.lights_mode = True
            self.control_mode = 'lights'
            self.layout_widget.light_placement_mode = True
            self.layout_widget.dragging_enabled = False
            apply_btn_style(self.btn_light, role="primary")
            self.mode_button.text = 'Сетка'

    def toggle_control_mode(self, instance):
        """Переключает режим управления"""
        if self.lights_mode:
            self.toggle_lights_mode(self.btn_light)
        if self.control_mode == 'grid':
            self.control_mode = 'pan_zoom'
            self.mode_button.text = 'Панорама'
            # Отключаем перемещение сетки пальцем
            self.layout_widget.dragging_enabled = False
        else:
            self.control_mode = 'grid'
            self.mode_button.text = 'Сетка'
            # Включаем перемещение сетки пальцем
            self.layout_widget.dragging_enabled = True

    def reset_view(self, instance):
        """Сбрасывает вид к первоначальному состоянию"""
        if self.control_mode == 'pan_zoom':
            # Центрируем комнату
            self.layout_widget.center_room()
        else:
            # Сбрасываем сетку
            self.layout_widget.grid_offset_x = 0
            self.layout_widget.grid_offset_y = 0
            if hasattr(self, 'ceiling_layout'):
                self.ceiling_layout.grid_offset_x = 0
                self.ceiling_layout.grid_offset_y = 0
                self.ceiling_layout.calculate_layout()
                self.layout_widget.layout = self.ceiling_layout
                self.update_stats()
                self.layout_widget.draw_layout()

    def create_control_panel(self):
        """Создает панель управления сеткой (2 строки: стрелки + 2 кнопки)"""
        # Основной контейнер с вертикальной ориентацией (2 строки)
        control_panel = BoxLayout(
            orientation='vertical',
            size_hint=(1, 0.1),
            padding=dp(5),
            spacing=dp(5)
        )

        # === СТРОКА 1: кнопки смещения (с авто-повтором) ===
        row1 = BoxLayout(
            size_hint=(1, 0.5),
            spacing=dp(5)
        )

        # ← КРИТИЧНО: Кнопки с привязкой on_press и on_release для авто-повтора
        btn_left = IconRoundedButton(icon_type='left', size_hint=(0.2, 1))
        btn_left.corner_radius = dp(10)
        apply_btn_style(btn_left, role="secondary")
        btn_left.bind(
            on_press=lambda x: (apply_btn_style(btn_left, role="primary"), self.start_repeat_move(-1, 0)),
            on_release=lambda x: (apply_btn_style(btn_left, role="secondary"), self.stop_repeat_move())
        )

        btn_up = IconRoundedButton(icon_type='up', size_hint=(0.2, 1))
        btn_up.corner_radius = dp(10)
        apply_btn_style(btn_up, role="secondary")
        btn_up.bind(
            on_press=lambda x: (apply_btn_style(btn_up, role="primary"), self.start_repeat_move(0, 1)),
            on_release=lambda x: (apply_btn_style(btn_up, role="secondary"), self.stop_repeat_move())
        )

        btn_down = IconRoundedButton(icon_type='down', size_hint=(0.2, 1))
        btn_down.corner_radius = dp(10)
        apply_btn_style(btn_down, role="secondary")
        btn_down.bind(
            on_press=lambda x: (apply_btn_style(btn_down, role="primary"), self.start_repeat_move(0, -1)),
            on_release=lambda x: (apply_btn_style(btn_down, role="secondary"), self.stop_repeat_move())
        )

        btn_right = IconRoundedButton(icon_type='right', size_hint=(0.2, 1))
        btn_right.corner_radius = dp(10)
        apply_btn_style(btn_right, role="secondary")
        btn_right.bind(
            on_press=lambda x: (apply_btn_style(btn_right, role="primary"), self.start_repeat_move(1, 0)),
            on_release=lambda x: (apply_btn_style(btn_right, role="secondary"), self.stop_repeat_move())
        )

        row1.add_widget(btn_left)
        row1.add_widget(btn_up)
        row1.add_widget(btn_down)
        row1.add_widget(btn_right)

        # === СТРОКА 2: ДВЕ кнопки переключения размеров (убрали "Сброс") ===
        row2 = BoxLayout(
            size_hint=(1, 0.6),
            spacing=dp(5),  # ← Отступ между кнопками
        )

        # Кнопка 1: Размеры плиток
        self.toggle_dims_btn = RoundedButton(
            text='Скрыть размеры плит',
            font_size=dp(12),
            size_hint=(0.5, 1),
        )
        self.toggle_dims_btn.corner_radius = dp(12)
        apply_btn_style(self.toggle_dims_btn, role="secondary")
        wrap_button_text(self.toggle_dims_btn)
        self.toggle_dims_btn.bind(on_press=self.toggle_dimensions)

        # ← Кнопка 2: Размеры стен
        self.toggle_wall_dims_btn = RoundedButton(
            text='Скрыть размеры стен',
            font_size=dp(12),
            size_hint=(0.5, 1),
        )
        self.toggle_wall_dims_btn.corner_radius = dp(12)
        apply_btn_style(self.toggle_wall_dims_btn, role="secondary")
        wrap_button_text(self.toggle_wall_dims_btn)
        self.toggle_wall_dims_btn.bind(on_press=self.toggle_wall_dimensions)

        row2.add_widget(self.toggle_dims_btn)
        row2.add_widget(self.toggle_wall_dims_btn)

        # Собираем обе строки в панель
        control_panel.add_widget(row1)
        control_panel.add_widget(row2)

        return control_panel

    # ← КРИТИЧНО: НОВЫЕ МЕТОДЫ для авто-повтора
    def start_repeat_move(self, dx, dy):
        """Запускает авто-повтор смещения сетки"""
        # Сначала делаем один сдвиг сразу
        self.move_grid(dx, dy)

        # Сохраняем направление
        self.repeat_dx = dx
        self.repeat_dy = dy

        # Параметры скорости
        initial_delay = 0.3  # 300мс перед первым повтором
        repeat_interval = 0.1  # 100мс между повторами

        # Планируем первый повтор через задержку
        from kivy.clock import Clock
        self.repeat_event = Clock.schedule_once(
            lambda dt: self._repeat_move_loop(repeat_interval),
            initial_delay
        )

    def _repeat_move_loop(self, interval):
        """Цикл авто-повтора"""
        # Делаем сдвиг
        self.move_grid(self.repeat_dx, self.repeat_dy)

        # Планируем следующий повтор
        from kivy.clock import Clock
        self.repeat_event = Clock.schedule_once(
            lambda dt: self._repeat_move_loop(interval),
            interval
        )

    def stop_repeat_move(self):
        """Останавливает авто-повтор"""
        if self.repeat_event:
            from kivy.clock import Clock
            Clock.unschedule(self.repeat_event)
            self.repeat_event = None
        self.repeat_dx = 0
        self.repeat_dy = 0
        # Финальный точный пересчет после отпускания кнопки
        self._schedule_layout_update(immediate=True)

    def move_grid(self, dx, dy):
        """Смещает сетку на dx, dy сантиметров с немедленным отображением"""
        if hasattr(self.layout_widget, 'grid_offset_x'):
            # Устанавливаем ТОЧНОЕ смещение и округляем до целого
            self.layout_widget.grid_offset_x = round(
                self.layout_widget.grid_offset_x + dx)
            self.layout_widget.grid_offset_y = round(
                self.layout_widget.grid_offset_y + dy)

            # Вызываем callback (он сделает throttle-пересчет)
            self.on_grid_moved()
            # Легкая визуальная перерисовка сразу (сетка/позиция)
            self.layout_widget.draw_layout()

    def create_stats_panel(self):
        """Создает панель статистики"""
        stats_panel = BoxLayout(
            size_hint=(1, 0.05),
            padding=dp(10)
        )
        # Изменяем текст на площадь
        self.stats_label = Label(
            text='Целых: 0 | Резаных: 0 | Площадь: 0.0 м²',
            font_size=dp(14),
            color=(1, 1, 1, 1)
        )
        self.stats_label._theme_slot = "text"
        stats_panel.add_widget(self.stats_label)
        return stats_panel

    def reset_grid(self, instance):
        """Сбрасывает смещение сетки к (0, 0)"""
        self.layout_widget.grid_offset_x = 0
        self.layout_widget.grid_offset_y = 0
        if self.ceiling_layout:
            self.ceiling_layout.grid_offset_x = 0
            self.ceiling_layout.grid_offset_y = 0
            self.ceiling_layout.calculate_layout()
            self.layout_widget.layout = self.ceiling_layout
        self.update_stats()
        self.layout_widget.draw_layout()

    def update_stats(self):
        """Обновляет статистику раскладки"""
        if self.ceiling_layout:
            stats = self.ceiling_layout
            # Обновляем текст: вместо отходов показываем площадь
            lights = len(getattr(self.layout_widget, 'light_fixtures', set()))
            full, cut = effective_tile_counts_after_lights(
                stats.full_tiles, stats.cut_tiles, lights
            )
            self.stats_label.text = (
                f'Целых: {full} | Резаных: {cut} | '
                f'Свет: {lights} | Площадь: {stats.room_area_sqm:.2f} м²'
            )

    def _persist_room_layout_state(self):
        if not (hasattr(self, 'ceiling_layout') and self.manager.current_room):
            return
        current_room = self.manager.current_room
        old_offset_x = getattr(current_room, 'grid_offset_x', 0)
        old_offset_y = getattr(current_room, 'grid_offset_y', 0)
        new_offset_x = self.ceiling_layout.grid_offset_x
        new_offset_y = self.ceiling_layout.grid_offset_y
        old_lights = getattr(current_room, 'light_fixtures', []) or []
        new_lights = self.layout_widget.light_fixtures_list()
        if (
            old_offset_x != new_offset_x
            or old_offset_y != new_offset_y
            or old_lights != new_lights
        ):
            current_room.grid_offset_x = new_offset_x
            current_room.grid_offset_y = new_offset_y
            current_room.light_fixtures = new_lights
            save_project(self.manager.current_project)

    def go_back(self, instance):
        """Возврат в редактор"""
        self._schedule_layout_update(immediate=True)
        self._persist_room_layout_state()
        self.manager.current = 'rooms'
