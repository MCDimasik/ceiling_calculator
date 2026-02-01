# screens/layout_screen.py
from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.gridlayout import GridLayout
from kivy.metrics import dp
from kivy.uix.floatlayout import FloatLayout
from widgets.layout_widget import LayoutWidget
from models import CeilingLayout
from database import save_project  # Импортируем функцию сохранения


class LayoutScreen(Screen):
    """Экран раскладки потолка 60×60 см"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.snap_mode = 0
        self.control_mode = 'grid'  # 'grid' или 'pan_zoom'

        main_layout = BoxLayout(orientation='vertical', spacing=dp(2))
        self.selected_corner = None

        # Панель инструментов
        toolbar = self.create_toolbar()

        # Область с раскладкой
        self.layout_widget = LayoutWidget(size_hint=(1, 0.8))

        # Панель информации и управления
        control_panel = self.create_control_panel()

        # Панель статистики (обновленная)
        stats_panel = self.create_stats_panel()

        main_layout.add_widget(toolbar)
        main_layout.add_widget(self.layout_widget)
        main_layout.add_widget(control_panel)
        main_layout.add_widget(stats_panel)

        self.add_widget(main_layout)

    def toggle_dimensions(self, instance):
        """Переключает отображение размеров резаных плиток"""
        if not hasattr(self, 'layout_widget'):
            return

        # Инвертируем состояние
        self.layout_widget.show_dimensions = not self.layout_widget.show_dimensions

        # Меняем текст кнопки с переносом
        if self.layout_widget.show_dimensions:
            instance.text = 'Скрыть nразмеры'
            instance.background_color = (0.5, 0.5, 0.5, 1)
        else:
            instance.text = 'Показать nразмеры'
            instance.background_color = (0.3, 0.7, 0.3, 1)

        # Перерисовываем
        self.layout_widget.draw_layout()

    def on_pre_enter(self):
        """Загружаем комнату при входе"""
        from kivy.clock import Clock
        Clock.schedule_once(self.load_room_data, 0.1)

    def load_room_data(self, dt):
        """Загружает данные комнаты с задержкой для правильной инициализации"""
        if not hasattr(self.manager, 'current_room') or not self.manager.current_room:
            print("Ошибка: current_room не установлен")
            return
        current_room = self.manager.current_room
        if current_room:
            print(f"Загрузка комнаты: {current_room.name}")
            print(f"Стены: {len(current_room.walls)}")
            # Отладочная информация о стенах
            for i, wall in enumerate(current_room.walls):
                print(f"  Стена {i}: {wall}")

            # Устанавливаем стены в виджет
            self.layout_widget.set_room(current_room.walls)
            # Создаем расчет раскладки
            self.ceiling_layout = CeilingLayout(current_room)
            # ВАЖНО: Устанавливаем начальное смещение сетки в 0, а не берем из виджета
            self.ceiling_layout.grid_offset_x = 0
            self.ceiling_layout.grid_offset_y = 0
            # Рассчитываем раскладку
            self.ceiling_layout.calculate_layout()
            # Передаем layout в виджет
            self.layout_widget.layout = self.ceiling_layout
            # Устанавливаем callback для обновления статистики при движении сетки
            self.layout_widget.on_grid_move = self.on_grid_moved
            # Обновляем статистику
            self.update_stats()
            # Явно перерисовываем
            self.layout_widget.draw_layout()

    def on_grid_moved(self):
        """Callback, вызываемый при изменении положения сетки"""
        # Получаем ТОЧНЫЕ значения смещения без округления
        if hasattr(self.layout_widget, 'grid_offset_x') and hasattr(self.layout_widget, 'grid_offset_y'):
            # Берем точные значения для расчета
            exact_offset_x = self.layout_widget.grid_offset_x
            exact_offset_y = self.layout_widget.grid_offset_y

            # Обновляем расчет раскладки с точными значениями
            if hasattr(self, 'ceiling_layout'):
                self.ceiling_layout.grid_offset_x = exact_offset_x
                self.ceiling_layout.grid_offset_y = exact_offset_y
                self.ceiling_layout.calculate_layout()
                self.layout_widget.layout = self.ceiling_layout
                self.update_stats()  # Обновляем статистику при движении сетки

            # Округляем ТОЛЬКО для отображения в лейбле ПОСЛЕ расчета
            offset_x_display = int(round(exact_offset_x))
            offset_y_display = int(round(exact_offset_y))

            # Обновляем отображение СРАЗУ при любом изменении
            if hasattr(self, 'offset_label'):
                self.offset_label.text = f'Смещение: {offset_x_display}×{offset_y_display} см'

    def create_toolbar(self):
        """Создает панель инструментов с кнопкой режима"""
        toolbar = BoxLayout(
            size_hint=(1, 0.1),
            padding=dp(10),
            spacing=dp(10)
        )

        # Кнопка "Назад"
        btn_back = Button(
            text='Назад',
            font_size=dp(16),
            size_hint=(0.2, 1),
            background_color=(0.8, 0.8, 0.8, 1)
        )
        btn_back.bind(on_press=self.go_back)

        # Заголовок
        title = Label(
            text='Раскладка\n60×60 см',
            font_size=dp(14),
            size_hint=(0.3, 1),
            color=(0, 0, 0, 1),
            halign='center',
            valign='middle',
            max_lines=2,
            line_height=1.2
        )
        title.bind(size=title.setter('text_size'))

        # Кнопка режима управления
        self.mode_button = Button(
            text='Сетка',  # Иконка и текст
            font_size=dp(14),
            size_hint=(0.25, 1),
            background_color=(0.2, 0.6, 1, 1),
            color=(1, 1, 1, 1)
        )
        self.mode_button.bind(on_press=self.toggle_control_mode)

        # Кнопка "Сброс"
        btn_reset = Button(
            text='Сброс',
            font_size=dp(14),
            size_hint=(0.25, 1),
            background_color=(0.9, 0.6, 0.2, 1),
            color=(1, 1, 1, 1)
        )
        btn_reset.bind(on_press=self.reset_view)

        toolbar.add_widget(btn_back)
        toolbar.add_widget(title)
        toolbar.add_widget(self.mode_button)
        toolbar.add_widget(btn_reset)

        return toolbar

    def toggle_control_mode(self, instance):
        """Переключает режим управления"""
        if self.control_mode == 'grid':
            self.control_mode = 'pan_zoom'
            self.mode_button.text = '👆 Панорама'
            self.mode_button.background_color = (0.3, 0.7, 0.3, 1)
            # Отключаем перемещение сетки пальцем
            self.layout_widget.dragging_enabled = False
        else:
            self.control_mode = 'grid'
            self.mode_button.text = 'Сетка'
            self.mode_button.background_color = (0.2, 0.6, 1, 1)
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
        """Создает панель управления сеткой с одной строкой кнопок и строкой кнопки переключения размеров"""
        # Основной контейнер с вертикальной ориентацией (2 строки)
        control_panel = BoxLayout(
            orientation='vertical',
            size_hint=(1, 0.1),  # Увеличена высота до 10% экрана
            padding=dp(5),
            spacing=dp(5)
        )

        # === СТРОКА 1: кнопки смещения ===
        row1 = BoxLayout(
            size_hint=(1, 0.5),
            spacing=dp(5)
        )

        # Кнопки смещения сетки с шагом 1 см
        btn_left = Button(
            text='<-',
            font_size=dp(20),
            size_hint=(0.2, 1),
            background_color=(0.3, 0.3, 0.3, 1)
        )
        btn_left.bind(on_press=lambda x: self.move_grid(-1, 0))
        btn_up = Button(
            text='^',
            font_size=dp(20),
            size_hint=(0.2, 1),
            background_color=(0.3, 0.3, 0.3, 1)
        )
        btn_up.bind(on_press=lambda x: self.move_grid(0, 1))
        btn_down = Button(
            text='v',
            font_size=dp(20),
            size_hint=(0.2, 1),
            background_color=(0.3, 0.3, 0.3, 1)
        )
        btn_down.bind(on_press=lambda x: self.move_grid(0, -1))
        btn_right = Button(
            text='->',
            font_size=dp(20),
            size_hint=(0.2, 1),
            background_color=(0.3, 0.3, 0.3, 1)
        )
        btn_right.bind(on_press=lambda x: self.move_grid(1, 0))

        row1.add_widget(btn_left)
        row1.add_widget(btn_up)
        row1.add_widget(btn_down)
        row1.add_widget(btn_right)

        # === СТРОКА 2: кнопка переключения размеров ===
        row2 = BoxLayout(
            size_hint=(1, 0.5),
            padding=(dp(10), 0)
        )

        # Кнопка с переносом текста и увеличенной высотой
        self.toggle_dims_btn = Button(
            text='Скрыть размеры',  # Перенос через \
            font_size=dp(14),
            size_hint=(0.4, 1),
            background_color=(0.5, 0.5, 0.5, 1),
            color=(1, 1, 1, 1),
            halign='center',
            valign='middle'
        )
        # Настройка переноса текста
        self.toggle_dims_btn.bind(
            size=lambda instance, size: setattr(
                instance, 'text_size', (size[0] * 0.9, None))
        )
        self.toggle_dims_btn.bind(on_press=self.toggle_dimensions)
        row2.add_widget(self.toggle_dims_btn)

        # Собираем обе строки в панель
        control_panel.add_widget(row1)
        control_panel.add_widget(row2)
        return control_panel

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
            color=(0, 0, 0, 1)
        )
        stats_panel.add_widget(self.stats_label)
        return stats_panel

    def move_grid(self, dx, dy):
        """Смещает сетку на dx, dy сантиметров с немедленным отображением"""
        if hasattr(self.layout_widget, 'grid_offset_x'):
            # Устанавливаем ТОЧНОЕ смещение и округляем до целого
            self.layout_widget.grid_offset_x = round(
                self.layout_widget.grid_offset_x + dx)
            self.layout_widget.grid_offset_y = round(
                self.layout_widget.grid_offset_y + dy)

            # Немедленно обновляем расчет
            if hasattr(self, 'ceiling_layout'):
                self.ceiling_layout.grid_offset_x = self.layout_widget.grid_offset_x
                self.ceiling_layout.grid_offset_y = self.layout_widget.grid_offset_y
                self.ceiling_layout.calculate_layout()
                self.layout_widget.layout = self.ceiling_layout
            # КРИТИЧЕСКИ ВАЖНО: вызываем callback вручную для немедленного обновления
            self.on_grid_moved()
            # Перерисовываем
            self.layout_widget.draw_layout()

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
            self.stats_label.text = f'Целых: {stats.full_tiles} | Резаных: {stats.cut_tiles} | Площадь: {stats.room_area_sqm:.2f} м²'

    def go_back(self, instance):
        """Возврат в редактор"""
        # Сохраняем проект при выходе с экрана раскладки (если нужно)
        # save_project(self.manager.current_project)
        self.manager.current = 'room_editor'
