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
from database import save_project # Импортируем функцию сохранения

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

            # Обновляем отображение смещения
            self.update_offset_label()

            # Явно перерисовываем
            self.layout_widget.draw_layout()

    def on_grid_moved(self):
        """Callback, вызываемый при изменении положения сетки"""
        # Получаем ТОЧНЫЕ значения смещения без округления
        if hasattr(self.layout_widget, 'grid_offset_x') and hasattr(self.layout_widget, 'grid_offset_y'):
            # Берем точные значения и округляем только для отображения
            offset_x = round(self.layout_widget.grid_offset_x,
                             1)  # Округляем до 0.1 см
            offset_y = round(self.layout_widget.grid_offset_y, 1)

            # Обновляем отображение СРАЗУ при любом изменении
            if hasattr(self, 'offset_label'):
                self.offset_label.text = f'Смещение: {int(round(offset_x))}×{int(round(offset_y))} см'

            # Обновляем расчет раскладки
            if hasattr(self, 'ceiling_layout'):
                self.ceiling_layout.grid_offset_x = offset_x
                self.ceiling_layout.grid_offset_y = offset_y
                self.ceiling_layout.calculate_layout()
                self.layout_widget.layout = self.ceiling_layout
                self.update_stats() # Обновляем статистику при движении сетки

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
            font_size=dp(16),
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
                self.update_offset_label()
                self.layout_widget.draw_layout()

    def create_control_panel(self):
        """Создает панель управления сеткой"""
        control_panel = BoxLayout(
            size_hint=(1, 0.05),
            padding=dp(5),
            spacing=dp(5)
        )

        # Кнопки смещения сетки с шагом 1 см
        btn_left = Button(
            text='<-',
            font_size=dp(20),
            size_hint=(0.15, 1)
        )
        btn_left.bind(on_press=lambda x: self.move_grid(-1, 0))
        btn_up = Button(
            text='^',
            font_size=dp(20),
            size_hint=(0.15, 1)
        )
        btn_up.bind(on_press=lambda x: self.move_grid(0, 1))
        btn_down = Button(
            text='v',
            font_size=dp(20),
            size_hint=(0.15, 1)
        )
        btn_down.bind(on_press=lambda x: self.move_grid(0, -1))
        btn_right = Button(
            text='->',
            font_size=dp(20),
            size_hint=(0.15, 1)
        )
        btn_right.bind(on_press=lambda x: self.move_grid(1, 0))

        # Индикатор смещения
        self.offset_label = Label(
            text='Смещение: 0×0 см',
            font_size=dp(14),
            size_hint=(0.4, 1),
            color=(0, 0, 0, 1)
        )

        control_panel.add_widget(btn_left)
        control_panel.add_widget(btn_up)
        control_panel.add_widget(btn_down)
        control_panel.add_widget(btn_right)
        control_panel.add_widget(self.offset_label)

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
            # Устанавливаем ТОЧНОЕ смещение
            self.layout_widget.grid_offset_x += dx
            self.layout_widget.grid_offset_y += dy

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

    def update_offset_label(self):
        """Обновляет отображение смещения сетки"""
        ox = self.layout_widget.grid_offset_x
        oy = self.layout_widget.grid_offset_y
        self.offset_label.text = f'Смещение: {int(ox)}×{int(oy)} см'

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
            self.update_offset_label()
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
