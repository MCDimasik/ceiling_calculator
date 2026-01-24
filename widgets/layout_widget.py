from kivy.uix.widget import Widget
from kivy.graphics import Color, Line, Rectangle, Mesh
from kivy.properties import NumericProperty, ObjectProperty, BooleanProperty
from kivy.metrics import dp
from kivy.core.text import Label as CoreLabel
from kivy.graphics import StencilPush
from kivy.clock import Clock
from functools import partial
from kivy.graphics.stencil_instructions import StencilPush, StencilUse, StencilUnUse, StencilPop


class LayoutWidget(Widget):
    """Виджет для отображения раскладки 60×60 см"""

    scale = NumericProperty(0.3)
    offset_x = NumericProperty(0)
    offset_y = NumericProperty(0)
    grid_offset_x = NumericProperty(0)  # Смещение сетки (0-59 см)
    grid_offset_y = NumericProperty(0)
    on_grid_move = ObjectProperty(None)  # Callback для обновления статистики
    dragging_enabled = BooleanProperty(True)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Данные комнаты
        self.walls = []
        self.layout = None
        self.room_bounds = None  # Границы комнаты
        self.is_rotated = False  # Флаг поворота
        self.rotation_angle = 0  # Угол поворота
        self.redraw_scheduled = False
        self.last_redraw_time = 0
        self.dragging_enabled = True
        self.panning = False  # Для режима панорамирования
        self.last_pan_pos = None

        # Для перетаскивания
        self.dragging = False
        self.last_touch_pos = None

        # Цвета согласно редактору
        self.bg_color = (0.12, 0.13, 0.13, 1)      # #1e2022 - темный фон
        self.wall_color = (0.94, 0.96, 0.98, 1)    # #f0f5f9 - светлые стены
        # #52616b - серый для заполненной комнаты
        self.room_color = (0.32, 0.38, 0.42, 1)
        self.grid_color = (0.79, 0.84, 0.87, 0.7)  # #c9d6df - цвет сетки
        self.full_tile_color = (0.9, 0.9, 0.9, 0.3)  # Цвет целых плиток
        self.cut_tile_color = (0.7, 0.7, 0.7, 0.3)   # Цвет резаных плиток
        self.text_color = (0.94, 0.96, 0.98, 1)    # #f0f5f9 - цвет текста

        self.bind(size=self._update_canvas)

    def _update_canvas(self, *args):
        """Обновляет канвас при изменении размера виджета"""
        try:
            if hasattr(self, 'room_bounds') and self.room_bounds:
                # Пересчитываем позицию при изменении размера
                self.center_room()

            if hasattr(self, 'draw_layout'):
                self.draw_layout()
        except Exception as e:
            print(f"Ошибка при обновлении канваса: {e}")

    def set_room(self, walls):
        """Устанавливает стены комнаты и центрирует ее на экране"""
        self.walls = walls
        if not walls:
            return

        # Находим границы комнаты
        all_x = []
        all_y = []
        for wall in walls:
            x1, y1, x2, y2 = wall
            all_x.extend([x1, x2])
            all_y.extend([y1, y2])

        if not all_x or not all_y:
            return

        self.room_bounds = {
            'min_x': min(all_x), 'max_x': max(all_x),
            'min_y': min(all_y), 'max_y': max(all_y)
        }

        # Центрируем комнату
        self.center_room()

        # Сбрасываем смещение сетки в 0 для правильного начала
        self.grid_offset_x = 0
        self.grid_offset_y = 0

        self.draw_layout()

    def center_room(self):
        """Центрирует комнату в рабочей области с учетом тулбаров"""
        if not self.room_bounds:
            return

        min_x, max_x = self.room_bounds['min_x'], self.room_bounds['max_x']
        min_y, max_y = self.room_bounds['min_y'], self.room_bounds['max_y']

        room_width = max_x - min_x
        room_height = max_y - min_y

        # Защита от нулевых размеров
        if room_width <= 0:
            room_width = 10
        if room_height <= 0:
            room_height = 10

        # Вычисляем масштаб с учетом отступов
        # Учитываем, что верхний тулбар = 10%, нижние панели = 10% (итого 80% доступно)
        # 12% сверху (дополнительный отступ для верхнего тулбара)
        padding_top = 0.12
        padding_bottom = 0.12  # 8% снизу (меньше, чем сверху)
        padding_sides = 0.10  # 10% с каждой стороны

        available_height = self.height * (1 - padding_top - padding_bottom)
        available_width = self.width * (1 - 2 * padding_sides)

        scale_x = available_width / room_width if room_width > 0 else 0.3
        scale_y = available_height / room_height if room_height > 0 else 0.3

        # Используем минимальный масштаб для вписывания
        self.scale = min(scale_x, scale_y)

        # Ограничиваем масштаб
        self.scale = max(0.1, min(self.scale, 1.0))

        # Центрируем комнату с учетом отступов
        room_center_x = (min_x + max_x) / 2
        room_center_y = (min_y + max_y) / 2

        widget_center_x = self.width / 2
        widget_center_y = self.height / 2

        self.offset_x = widget_center_x - room_center_x * self.scale
        self.offset_y = widget_center_y - room_center_y * self.scale

        # Корректируем по Y, чтобы учесть разные отступы сверху и снизу
        bottom_bound = self.offset_y + min_y * self.scale
        top_bound = self.offset_y + max_y * self.scale

        # Устанавливаем минимальные отступы от границ
        min_top_padding = self.height * padding_top
        min_bottom_padding = self.height * padding_bottom

        # Если комната выходит за верхний отступ
        if top_bound > self.height - min_top_padding:
            self.offset_y -= (top_bound - (self.height - min_top_padding))

        # Если комната выходит за нижний отступ
        if bottom_bound < min_bottom_padding:
            self.offset_y += (min_bottom_padding - bottom_bound)

    def cm_to_px(self, cm_x, cm_y):
        """Конвертирует сантиметры в пиксели"""
        # БЕЗ ПОВОРОТА - просто масштабирование и смещение
        px_x = self.offset_x + cm_x * self.scale
        px_y = self.offset_y + cm_y * self.scale
        return px_x, px_y

    def draw_layout(self):
        self.canvas.clear()

        with self.canvas:
            # Темный фон
            Color(*self.bg_color)
            Rectangle(pos=self.pos, size=self.size)

            # 1. Рисуем заполнение комнаты
            self.draw_room_fill()

            # 2. Рисуем плитки сетки 60×60
            self.draw_grid_tiles()

            # 3. Рисуем стены комнаты поверх
            self.draw_walls()

            # 4. Рисуем цифры ПОСЛЕДНИМИ, поверх всего
            self.draw_all_cut_dimensions()

    def draw_all_cut_dimensions(self):
        """Рисует размеры для ВСЕХ резаных плиток, показывая только обрезанные стороны"""
        if not self.layout or not self.layout.tiles:
            return

        for tile in self.layout.tiles:
            if tile['type'] != 'cut':
                continue

            # Берем точные значения размеров
            remaining_x = tile.get('cut_x', 60.0)  # Полезный размер X
            remaining_y = tile.get('cut_y', 60.0)  # Полезный размер Y

            # Определяем, какие размеры нужно отображать (только обрезанные стороны)
            texts = []

            # Показываем размер по X, только если он обрезан (меньше 59.5 см с погрешностью)
            if remaining_x < 59.5:  # С небольшой погрешностью для учета округления
                texts.append(f"{int(round(remaining_x))}")

            # Показываем размер по Y, только если он обрезан
            if remaining_y < 59.5:
                texts.append(f"{int(round(remaining_y))}")

            # Если обе стороны целые (или почти целые), не показываем ничего
            if not texts:
                continue

            # Формируем текст: если обе стороны обрезаны - показываем оба размера
            if len(texts) == 2:
                text = f"{texts[0]}×{texts[1]}"
            else:
                text = texts[0]

            # Центр плитки для позиционирования текста
            x1, y1, x2, y2 = tile['x1'], tile['y1'], tile['x2'], tile['y2']
            center_x = (x1 + x2) / 2
            center_y = (y1 + y2) / 2
            px_center = self.cm_to_px(center_x, center_y)

            # Создаем текст с небольшим шрифтом
            label = CoreLabel(
                text=text,
                font_size=9,
                color=self.text_color,
                bold=True
            )
            label.refresh()

            # Центрируем текст в плитке
            pos_x = px_center[0] - label.texture.size[0] / 2
            pos_y = px_center[1] - label.texture.size[1] / 2

            # Рисуем полупрозрачный фон для читаемости
            Color(0, 0, 0, 0.3)  # Черный с 30% прозрачности
            Rectangle(
                pos=(pos_x - 2, pos_y - 1),
                size=(label.texture.size[0] + 4, label.texture.size[1] + 2)
            )

            # Рисуем текст
            Color(*self.text_color)
            Rectangle(
                texture=label.texture,
                pos=(pos_x, pos_y),
                size=label.texture.size
            )

    def draw_room_fill(self):
        """Правильная заливка внутренней области комнаты для сложных форм"""
        if len(self.walls) < 3:
            return

        # Собираем точки в правильном порядке
        points = []
        if self.walls:
            points.append((self.walls[0][0], self.walls[0][1]))
            for wall in self.walls:
                points.append((wall[2], wall[3]))
            if points[-1] != points[0]:
                points.append(points[0])

        if len(points) < 4:
            return

        # Преобразуем точки в экранные координаты
        screen_points = []
        for x, y in points:
            px = self.cm_to_px(x, y)
            screen_points.extend([px[0], px[1]])

        if len(screen_points) < 8:
            return

        with self.canvas:
            # Используем stencil для правильной заливки
            StencilPush()
            Color(1, 1, 1, 1)

            # Рисуем контур для stencil
            Line(points=screen_points, close=True, width=1)

            StencilUse()

            # Заливаем ВНУТРЬ контура
            Color(*self.room_color)
            # Используем больший прямоугольник для гарантии заполнения
            min_x = min(screen_points[i]
                        for i in range(0, len(screen_points), 2))
            max_x = max(screen_points[i]
                        for i in range(0, len(screen_points), 2))
            min_y = min(screen_points[i]
                        for i in range(1, len(screen_points), 2))
            max_y = max(screen_points[i]
                        for i in range(1, len(screen_points), 2))
            Rectangle(pos=(min_x, min_y), size=(max_x-min_x, max_y-min_y))

            StencilUnUse()
            StencilPop()

            # Рисуем контур поверх заливки
            Color(*self.wall_color)
            Line(points=screen_points, close=True, width=2)

    def draw_walls(self):
        """Рисует стены комнаты"""
        if not self.walls:
            return

        Color(*self.wall_color)
        for wall in self.walls:
            x1, y1, x2, y2 = wall
            px1 = self.cm_to_px(x1, y1)
            px2 = self.cm_to_px(x2, y2)

            Line(points=[px1[0], px1[1], px2[0], px2[1]], width=3)

    def draw_grid_tiles(self):
        """Рисует сетку 60×60 в виде плиток (только внутри комнаты)"""
        if not self.layout or not self.layout.tiles:
            return

        # Рисуем заливку плиток
        for tile in self.layout.tiles:
            # Пропускаем плитки полностью вне комнаты
            if tile['type'] == 'outside':
                continue

            # Дополнительная проверка для резаных плиток: пропускаем если оба размера меньше 1 см
            if tile['type'] == 'cut':
                cut_x = tile.get('cut_x', 0)
                cut_y = tile.get('cut_y', 0)
                if cut_x < 1.0 and cut_y < 1.0:
                    continue

            x1, y1, x2, y2 = tile['x1'], tile['y1'], tile['x2'], tile['y2']
            px1 = self.cm_to_px(x1, y1)
            px2 = self.cm_to_px(x2, y2)

            # Рисуем заливку плитки
            if tile['type'] == 'full':
                Color(*self.full_tile_color)
                Rectangle(pos=px1, size=(px2[0]-px1[0], px2[1]-px1[1]))
            else:  # cut
                Color(*self.cut_tile_color)
                Rectangle(pos=px1, size=(px2[0]-px1[0], px2[1]-px1[1]))

        # Рисуем контуры плиток
        Color(*self.grid_color)
        for tile in self.layout.tiles:
            if tile['type'] == 'outside':
                continue
            x1, y1, x2, y2 = tile['x1'], tile['y1'], tile['x2'], tile['y2']
            px1 = self.cm_to_px(x1, y1)
            px2 = self.cm_to_px(x2, y2)

            # Рисуем контур плитки
            Line(rectangle=(px1[0], px1[1], px2[0] -
                 px1[0], px2[1] - px1[1]), width=1)

    # Добавляем новый метод для расчета процента отходов:

    def schedule_redraw(self):
        """Планирует перерисовку с задержкой"""
        if not self.redraw_scheduled:
            self.redraw_scheduled = True
            Clock.schedule_once(self.redraw_now, 0.05)  # 20 FPS

    def redraw_now(self, dt):
        """Выполняет перерисовку"""
        self.redraw_scheduled = False
        self.draw_layout()

    def move_grid(self, dx_cm, dy_cm):
        """Смещает сетку на указанное количество см"""
        self.grid_offset_x = (self.grid_offset_x + dx_cm) % 60
        self.grid_offset_y = (self.grid_offset_y + dy_cm) % 60

        # Вызываем callback для обновления статистики
        if self.on_grid_move:
            self.on_grid_move(self.grid_offset_x, self.grid_offset_y)

        # Используем оптимизированную перерисовку
        self.schedule_redraw()

    def on_touch_move(self, touch):
        """Обработка движения мыши/пальца с немедленным обновлением позиции"""
        if not self.collide_point(*touch.pos):
            return False

        if hasattr(self, 'panning') and self.panning:
            # Панорамирование
            dx = touch.x - self.last_pan_pos[0]
            dy = touch.y - self.last_pan_pos[1]
            self.offset_x += dx
            self.offset_y += dy
            self.last_pan_pos = (touch.x, touch.y)
            self.draw_layout()
            return True

        if hasattr(self, 'dragging') and self.dragging and self.dragging_enabled:
            # Перетаскивание сетки - ИСПРАВЛЕНО: убираем округление и задержку
            dx_px = touch.x - self.last_touch_pos[0]
            dy_px = touch.y - self.last_touch_pos[1]

            # Конвертируем в сантиметры БЕЗ округления
            dx_cm = dx_px / self.scale
            dy_cm = dy_px / self.scale

            # Обновляем смещение сетки ТОЧНО на рассчитанное значение
            self.grid_offset_x += dx_cm
            self.grid_offset_y += dy_cm

            # Сохраняем новое положение
            self.last_touch_pos = (touch.x, touch.y)

            # Вызываем callback НЕМЕДЛЕННО для обновления внешнего отображения
            if hasattr(self, 'on_grid_move') and callable(self.on_grid_move):
                self.on_grid_move()

            # Перерисовываем немедленно
            self.draw_layout()

            return True

        return super().on_touch_move(touch)

    def zoom_at_center(self, zoom_in=True):
        """Масштабирует относительно центра виджета"""
        # Запоминаем центр виджета в мировых координатах
        center_world_x = (self.width / 2 - self.offset_x) / self.scale
        center_world_y = (self.height / 2 - self.offset_y) / self.scale

        # Изменяем масштаб
        if zoom_in:
            # Максимальный масштаб увеличен до 3.0x
            new_scale = min(3.0, self.scale + 0.05)
        else:
            new_scale = max(0.1, self.scale - 0.05)

        # Пересчитываем смещение, чтобы центр остался на месте
        new_offset_x = self.width / 2 - center_world_x * new_scale
        new_offset_y = self.height / 2 - center_world_y * new_scale

        # Применяем изменения
        self.scale = new_scale
        self.offset_x = new_offset_x
        self.offset_y = new_offset_y

        # Обновляем отображение
        self.apply_bounds_protection()
        self.canvas.clear()
        if hasattr(self, 'draw_editor'):
            self.draw_editor()
        else:
            self.draw_layout()

    def apply_bounds_protection(self):
        """Защищает от выхода комнаты за границы виджета"""
        if not self.room_bounds:
            return

        min_x = self.room_bounds['min_x']
        max_x = self.room_bounds['max_x']
        min_y = self.room_bounds['min_y']
        max_y = self.room_bounds['max_y']

        # Рассчитываем границы видимой области
        visible_min_x = (0 - self.offset_x) / self.scale
        visible_max_x = (self.width - self.offset_x) / self.scale
        visible_min_y = (0 - self.offset_y) / self.scale
        visible_max_y = (self.height - self.offset_y) / self.scale

        # Если комната выходит за левую границу
        if max_x < visible_min_x:
            self.offset_x += (visible_min_x - max_x) * self.scale
        # Если комната выходит за правую границу
        if min_x > visible_max_x:
            self.offset_x -= (min_x - visible_max_x) * self.scale
        # Если комната выходит за нижнюю границу
        if max_y < visible_min_y:
            self.offset_y += (visible_min_y - max_y) * self.scale
        # Если комната выходит за верхнюю границу
        if min_y > visible_max_y:
            self.offset_y -= (min_y - visible_max_y) * self.scale

    def on_touch_down(self, touch):
        if self.collide_point(*touch.pos):
            if touch.is_mouse_scrolling:
                # Масштабирование всегда работает
                if touch.button == 'scrolldown':
                    self.scale = max(0.1, self.scale - 0.05)
                elif touch.button == 'scrollup':
                    self.scale = min(1.0, self.scale + 0.05)
                self.draw_layout()
                return True

            # Обработка двойного тапа для сброса
            if touch.is_double_tap:
                self.center_room()
                self.draw_layout()
                return True

            # В режиме панорамирования - начинаем перетаскивание
            if not self.dragging_enabled:
                self.panning = True
                self.last_pan_pos = touch.pos
                return True

            # В режиме сетки - начинаем перетаскивание сетки
            elif self.dragging_enabled:
                self.dragging = True
                self.last_touch_pos = touch.pos

                # НОВОЕ: немедленно обрабатываем смещение при нажатии
                # Это решит проблему с шагом 5 см
                if hasattr(self, 'last_touch_time'):
                    current_time = Clock.get_time()
                    if current_time - self.last_touch_time < 0.2:  # двойной клик
                        self.center_room()
                        self.draw_layout()
                        return True
                self.last_touch_time = Clock.get_time()

                return True
            
        return super().on_touch_down(touch)

    def on_touch_up(self, touch):
        self.dragging = False
        self.panning = False
        self.last_touch_pos = None
        self.last_pan_pos = None
        return super().on_touch_up(touch)
