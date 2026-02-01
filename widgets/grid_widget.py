from kivy.uix.widget import Widget
from kivy.graphics import Color, Line, Rectangle, Ellipse, Mesh
from kivy.properties import NumericProperty, ListProperty
from kivy.metrics import dp
import math
from kivy.graphics.stencil_instructions import StencilPush, StencilUse, StencilUnUse, StencilPop


class GridWidget(Widget):
    """Виджет для отображения масштабируемой сетки"""

    scale = NumericProperty(0.2)
    offset_x = NumericProperty(0)
    offset_y = NumericProperty(0)

    # Добавляем свойство для хранения точек комнаты
    room_points = ListProperty([])

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Текущая позиция (в сантиметрах)
        self.current_pos_cm = [0, 0]

        # Список стен
        self.walls = []

        # История для отмены
        self.undo_stack = []
        self.redo_stack = []

        # Для перетаскивания (panning)
        self.dragging = False
        self.last_touch_pos = None

        self.touches = {}  # Словарь для отслеживания касаний: {touch.id: touch}
        self.pinch_start_distance = None
        self.pinch_start_scale = None
        self.pinch_center = None

        # Для обработки клика на линию-доводчик
        self.closing_line_start = None
        self.closing_line_end = None
        self.closing_line_points = []

        # Цвета согласно ТЗ
        self.bg_color = (0.12, 0.13, 0.13, 1)      # #1e2022 - темный фон
        self.wall_color = (0.94, 0.96, 0.98, 1)    # #f0f5f9 - светлые стены
        self.point_color = (0.94, 0.96, 0.98, 1)   # #f0f5f9 - светлая точка
        # #52616b - серый для заполненной комнаты
        self.room_color = (0.32, 0.38, 0.42, 1)
        # #c9d6df - цвет линии соединения
        self.closing_line_color = (0.79, 0.84, 0.87, 1)

        # Центрируем камеру на точке (0,0)
        self.center_camera()

        # Сначала рисуем
        self.draw_editor()

        # Привязываем обновление при изменении размера
        self.bind(size=self._update_canvas)

    def center_camera(self):
        """Центрирует камеру на точке (0,0)"""
        if self.width > 0 and self.height > 0:
            self.offset_x = self.width / 2
            self.offset_y = self.height / 2

    def _update_canvas(self, *args):
        # Центрируем камеру при первом изменении размера
        if self.offset_x == 0 and self.offset_y == 0:
            self.center_camera()
        self.canvas.clear()
        self.draw_editor()

    def cm_to_px(self, cm_x, cm_y):
        """Конвертирует сантиметры в пиксели"""
        px_x = self.offset_x + cm_x * self.scale
        px_y = self.offset_y + cm_y * self.scale
        return px_x, px_y

    def draw_editor(self):
        """Рисует редактор комнаты"""
        with self.canvas:
            # Темный фон
            Color(*self.bg_color)
            Rectangle(pos=self.pos, size=self.size)

            # Рисуем заполненную область комнаты (если есть стены)
            if len(self.walls) >= 3:
                self.draw_room_fill()

            # Рисуем стены
            self.draw_walls()

            # Рисуем текущую точку
            self.draw_current_point()

            # Рисуем линию, соединяющую первую и последнюю точку (если есть 3+ стены)
            if len(self.walls) >= 3:
                self.draw_closing_line()

    def draw_closing_line(self):
        """Рисует линию, соединяющую первую и последнюю точку"""
        if len(self.walls) < 3:
            return

        # Берем первую точку первой стены и последнюю точку последней стены
        first_wall = self.walls[0]
        last_wall = self.walls[-1]

        # Первая точка: начало первой стены
        x1, y1 = first_wall[0], first_wall[1]
        # Последняя точка: конец последней стены
        x2, y2 = last_wall[2], last_wall[3]

        # Проверяем, не совпадают ли точки (если комната уже замкнута)
        if abs(x1 - x2) < 0.1 and abs(y1 - y2) < 0.1:
            return

        # Сохраняем координаты линии-доводчика для обработки кликов
        self.closing_line_start = (x1, y1)
        self.closing_line_end = (x2, y2)

        # Преобразуем в пиксели для отрисовки
        px1 = self.cm_to_px(x1, y1)
        px2 = self.cm_to_px(x2, y2)

        # Сохраняем точки линии в пикселях
        self.closing_line_points = [px1[0], px1[1], px2[0], px2[1]]

        # Цвет для линии соединения
        Color(*self.closing_line_color)

        # Рисуем пунктирную линию
        Line(points=self.closing_line_points,
             width=2, dash_length=10, dash_offset=5)

    def point_to_line_distance(self, px, py, x1, y1, x2, y2):
        """Вычисляет расстояние от точки до линии"""
        # Если линия вырождена в точку
        if x1 == x2 and y1 == y2:
            return math.sqrt((px - x1)**2 + (py - y1)**2)

        # Вектор линии
        line_vec_x = x2 - x1
        line_vec_y = y2 - y1

        # Вектор от начала линии до точки
        point_vec_x = px - x1
        point_vec_y = py - y1

        # Длина линии
        line_len = math.sqrt(line_vec_x**2 + line_vec_y**2)

        # Единичный вектор линии
        if line_len > 0:
            line_vec_x /= line_len
            line_vec_y /= line_len

        # Проекция вектора точки на линию
        projection_length = point_vec_x * line_vec_x + point_vec_y * line_vec_y

        # Ограничиваем проекцию длиной линии
        projection_length = max(0, min(line_len, projection_length))

        # Ближайшая точка на линии
        closest_x = x1 + projection_length * line_vec_x
        closest_y = y1 + projection_length * line_vec_y

        # Расстояние от точки до ближайшей точки на линии
        return math.sqrt((px - closest_x)**2 + (py - closest_y)**2)

    def draw_room_fill(self):
        """Правильная заливка внутренней области комнаты"""
        if len(self.walls) < 3:
            return

        # Собираем точки в правильном порядке для контура
        points = []
        if self.walls:
            # Первая точка первой стены
            points.append((self.walls[0][0], self.walls[0][1]))
            # Конечные точки всех стен
            for wall in self.walls:
                points.append((wall[2], wall[3]))
            # Если комната не замкнута, замыкаем полигон
            if points[-1] != points[0]:
                points.append(points[0])

        # Проверяем, достаточно ли точек для заливки
        if len(points) < 4:
            return

        # Преобразуем точки в экранные координаты
        screen_points = []
        for x, y in points:
            px = self.cm_to_px(x, y)
            screen_points.extend([px[0], px[1]])

        if len(screen_points) < 8:  # Минимум 4 точки для полигона
            return

        with self.canvas:
            # Заливаем полигон цветом комнаты
            Color(*self.room_color)

            # Создаем Mesh для заливки сложных форм
            vertices = []
            indices = []

            # Используем триангуляцию "веером" от центра масс
            center_x = sum(screen_points[i] for i in range(
                0, len(screen_points), 2)) / (len(screen_points) // 2)
            center_y = sum(screen_points[i] for i in range(
                1, len(screen_points), 2)) / (len(screen_points) // 2)

            # Создаем треугольники от центра к каждой паре соседних точек
            for i in range(0, len(screen_points) - 2, 2):
                # Центр
                vertices.extend([center_x, center_y, 0, 0])
                # Текущая точка
                vertices.extend([screen_points[i], screen_points[i+1], 0, 0])
                # Следующая точка
                vertices.extend([screen_points[i+2], screen_points[i+3], 0, 0])

            # Создаем индексы для треугольников
            indices = list(range(len(vertices) // 4))

            if vertices:
                Mesh(vertices=vertices, indices=indices, mode='triangles')

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

    def draw_current_point(self):
        """Рисует текущую точку"""
        x, y = self.current_pos_cm
        px_x, px_y = self.cm_to_px(x, y)

        Color(*self.point_color)
        Ellipse(pos=(px_x - 6, px_y - 6), size=(12, 12))

    def save_state(self):
        """Сохраняет текущее состояние для отмены"""
        state = {
            'walls': [w[:] for w in self.walls],  # Копируем стены
            'current_pos': self.current_pos_cm[:]  # Копируем позицию
        }
        self.undo_stack.append(state)
        # При новом действии очищаем стек повторения
        self.redo_stack = []

    def restore_state(self, index):
        """Восстанавливает состояние из истории"""
        if 0 <= index < len(self.history):
            state = self.history[index]
            self.walls = [w[:] for w in state['walls']]
            self.current_pos_cm = state['current_pos'][:]
            self.canvas.clear()
            self.draw_editor()
            return True
        return False

    def undo(self):
        """Отменяет последнее действие"""
        if len(self.undo_stack) > 1:
            # Сохраняем текущее состояние для возможного redo
            current_state = self.undo_stack.pop()
            self.redo_stack.append(current_state)

            # Восстанавливаем предыдущее состояние
            prev_state = self.undo_stack[-1]
            self.walls = [w[:] for w in prev_state['walls']]
            self.current_pos_cm = prev_state['current_pos'][:]

            # Перерисовываем
            self.canvas.clear()
            self.draw_editor()
            return True
        return False

    def redo(self):
        """Повторяет отмененное действие"""
        if self.redo_stack:
            # Берем состояние для повтора
            state = self.redo_stack.pop()
            self.undo_stack.append(state)

            # Восстанавливаем состояние
            self.walls = [w[:] for w in state['walls']]
            self.current_pos_cm = state['current_pos'][:]

            # Перерисовываем
            self.canvas.clear()
            self.draw_editor()
            return True
        return False

    def add_wall(self, direction, length_cm):
        """Добавляет стену в указанном направлении"""
        # Сохраняем текущее состояние перед изменением
        self.save_state()

        # Очищаем линию-доводчик при добавлении новой стены
        self.closing_line_start = None
        self.closing_line_end = None
        self.closing_line_points = []

        x1, y1 = self.current_pos_cm

        # Для диагональных направлений корректируем длину
        if direction in ['up_left', 'up_right', 'down_left', 'down_right']:
            # Делим длину на sqrt(2) для сохранения заданной длины диагонали
            component_length = length_cm / math.sqrt(2)
        else:
            component_length = length_cm

        if direction == 'up':
            x2, y2 = x1, y1 + component_length
        elif direction == 'down':
            x2, y2 = x1, y1 - component_length
        elif direction == 'left':
            x2, y2 = x1 - component_length, y1
        elif direction == 'right':
            x2, y2 = x1 + component_length, y1
        elif direction == 'up_left':
            x2, y2 = x1 - component_length, y1 + component_length
        elif direction == 'up_right':
            x2, y2 = x1 + component_length, y1 + component_length
        elif direction == 'down_left':
            x2, y2 = x1 - component_length, y1 - component_length
        elif direction == 'down_right':
            x2, y2 = x1 + component_length, y1 - component_length
        else:
            self.undo_stack.pop()  # Отменяем сохранение состояния
            return

        self.walls.append([x1, y1, x2, y2])
        self.current_pos_cm = [x2, y2]
        self.canvas.clear()
        self.draw_editor()
        return (x2, y2)

    def reset(self):
        """Сбрасывает редактор"""
        self.current_pos_cm = [0, 0]
        self.walls = []
        self.history = []
        self.history_index = -1
        self.saved_for_redo = []
        self.save_state()
        self.canvas.clear()
        self.draw_editor()

    def add_closing_wall(self):
        """Добавляет стену, замыкающую комнату (при нажатии на линию-доводчик)"""
        if len(self.walls) < 3 or not self.closing_line_start or not self.closing_line_end:
            return

        # Сохраняем текущее состояние перед изменением
        self.save_state()

        # Добавляем стену от последней точки к первой
        x1, y1 = self.closing_line_end  # Конец последней стены
        x2, y2 = self.closing_line_start  # Начало первой стены

        self.walls.append([x1, y1, x2, y2])
        self.current_pos_cm = [x2, y2]

        # Очищаем линию-доводчик
        self.closing_line_start = None
        self.closing_line_end = None
        self.closing_line_points = []

        # Перерисовываем
        self.canvas.clear()
        self.draw_editor()

    def get_distance(self, touch1, touch2):
        """Расстояние между двумя точками касания"""
        return ((touch1.x - touch2.x) ** 2 + (touch1.y - touch2.y) ** 2) ** 0.5

    def get_center(self, touch1, touch2):
        """Центр между двумя точками касания"""
        return ((touch1.x + touch2.x) / 2, (touch1.y + touch2.y) / 2)

    def on_touch_down(self, touch):
        if self.collide_point(*touch.pos):
            if self.is_touch_on_closing_line(touch):
                self.add_closing_wall()
                return True # Обработка завершена            
        
            # Колесо мыши (оставляем для десктопа)
            if touch.is_mouse_scrolling:
                if touch.button == 'scrolldown':
                    self.scale = max(0.1, self.scale - 0.05)
                elif touch.button == 'scrollup':
                    self.scale = min(3.0, self.scale + 0.05)  # Увеличен макс. масштаб до 3.0
                self.canvas.clear()
                self.draw_editor()
                return True

            # Начало пинч-жеста (2 пальца)
            self.touches[touch.id] = touch
            if len(self.touches) == 2:
                touches = list(self.touches.values())
                self.pinch_start_distance = self.get_distance(touches[0], touches[1])
                self.pinch_start_scale = self.scale
                self.pinch_center = self.get_center(touches[0], touches[1])
                return True

            # Одиночное касание — панорамирование
            self.dragging = True
            self.last_touch_pos = (touch.x, touch.y)
            return True
        return super().on_touch_down(touch)

    def is_touch_on_closing_line(self, touch, tolerance=dp(10)):
        """Проверяет, находится ли касание рядом с линией-доводчиком."""
        if not self.closing_line_points or len(self.closing_line_points) != 4:
            return False

        x1, y1, x2, y2 = self.closing_line_points
        px, py = touch.pos

        # Вычисляем расстояние от точки до линии
        dist = self.point_to_line_distance(px, py, x1, y1, x2, y2)
        return dist < tolerance

    def on_touch_move(self, touch):
        if touch.id in self.touches and len(self.touches) == 2:
            # Пинч-масштабирование
            touches = list(self.touches.values())
            current_distance = self.get_distance(touches[0], touches[1])
            
            if self.pinch_start_distance:
                scale_factor = current_distance / self.pinch_start_distance
                new_scale = self.pinch_start_scale * scale_factor
                new_scale = max(0.1, min(3.0, new_scale))  # Ограничение масштаба
                
                # Пересчитываем смещение относительно центра жеста
                if self.pinch_center:
                    old_center_x = (self.pinch_center[0] - self.offset_x) / self.scale
                    old_center_y = (self.pinch_center[1] - self.offset_y) / self.scale
                    
                    self.scale = new_scale
                    self.offset_x = self.pinch_center[0] - old_center_x * self.scale
                    self.offset_y = self.pinch_center[1] - old_center_y * self.scale
                
                self.canvas.clear()
                self.draw_editor()
                return True
        
        # Обработка панорамирования (один палец)
        if self.dragging and self.last_touch_pos:
            dx = touch.x - self.last_touch_pos[0]
            dy = touch.y - self.last_touch_pos[1]
            self.offset_x += dx
            self.offset_y += dy
            self.last_touch_pos = (touch.x, touch.y)
            self.canvas.clear()
            self.draw_editor()
            return True
        
        return super().on_touch_move(touch)

    def on_touch_up(self, touch):
        self.touches.pop(touch.id, None)
        self.pinch_start_distance = None
        self.pinch_center = None
        self.dragging = False
        self.last_touch_pos = None
        return super().on_touch_up(touch)
