from kivy.uix.widget import Widget
from kivy.graphics import Color, Line, Rectangle, Ellipse, Mesh
from kivy.properties import NumericProperty, ListProperty, BooleanProperty
from kivy.metrics import dp
import math
from kivy.clock import Clock

class GridWidget(Widget):
    """Виджет для отображения масштабируемой сетки"""
    scale = NumericProperty(0.2)
    offset_x = NumericProperty(0)
    offset_y = NumericProperty(0)
    room_points = ListProperty([])
    room_closed = BooleanProperty(False)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.on_change = None  # callback: fn() when geometry changes
        self.current_pos_cm = [0, 0]
        self.walls = []
        self.undo_stack = []
        self.redo_stack = []
        self._saving_state = False
        self.dragging = False
        self.last_touch_pos = None
        self.touches = {}
        self.pinch_start_distance = None
        self.pinch_start_scale = None
        self.pinch_center = None
        self.closing_line_start = None
        self.closing_line_end = None
        self.closing_line_points = []
        self.bg_color = (0.12, 0.13, 0.13, 1)
        self.wall_color = (0.94, 0.96, 0.98, 1)
        self.point_color = (0.94, 0.96, 0.98, 1)
        self.room_color = (0.32, 0.38, 0.42, 1)
        self.closing_line_color = (0.79, 0.84, 0.87, 1)
        self.center_camera()
        self.draw_editor()
        self.bind(size=self._update_canvas)
        # ← УБРАЛИ save_state() отсюда! Только в clear_undo_stack()

    def _notify_change(self):
        cb = getattr(self, "on_change", None)
        if not cb:
            return
        # defer to next frame to avoid re-entrancy during touch handlers
        Clock.schedule_once(lambda dt: cb(), 0)

    def _snapshot(self):
        return {
            "walls": [w[:] for w in self.walls],
            "current_pos": self.current_pos_cm[:],
            "room_closed": self.room_closed,
        }

    def _apply_state(self, state):
        self.walls = [w[:] for w in state.get("walls", [])]
        self.current_pos_cm = state.get("current_pos", [0, 0])[:]
        self.room_closed = bool(state.get("room_closed", False))
        if not self.room_closed:
            self.closing_line_start = None
            self.closing_line_end = None
            self.closing_line_points = []

    def center_camera(self):
        if self.width > 0 and self.height > 0:
            self.offset_x = self.width / 2
            self.offset_y = self.height / 2

    def _update_canvas(self, *args):
        if self.offset_x == 0 and self.offset_y == 0:
            self.center_camera()
        self.canvas.clear()
        self.draw_editor()

    def cm_to_px(self, cm_x, cm_y):
        px_x = self.offset_x + cm_x * self.scale
        px_y = self.offset_y + cm_y * self.scale
        return px_x, px_y

    def draw_editor(self):
        from kivy.graphics import StencilPush, StencilUse, StencilUnUse, StencilPop

        self.canvas.clear()
        with self.canvas:
            # Ограничиваем всё рисование рамкой виджета,
            # чтобы не залезать на тулбары и другие элементы
            StencilPush()
            Rectangle(pos=self.pos, size=self.size)
            StencilUse()

            Color(*self.bg_color)
            Rectangle(pos=self.pos, size=self.size)

            if len(self.walls) >= 3 and self.room_closed:
                self.draw_room_fill()

            self.draw_walls()
            self.draw_wall_dimensions()
            self.draw_current_point()

            if len(self.walls) >= 3 and not self.room_closed:
                self.draw_closing_line()

            StencilUnUse()
            Rectangle(pos=self.pos, size=self.size)
            StencilPop()

    def draw_closing_line(self):
        if len(self.walls) < 3:
            return
        first_wall = self.walls[0]
        last_wall = self.walls[-1]
        x1, y1 = first_wall[0], first_wall[1]
        x2, y2 = last_wall[2], last_wall[3]
        if abs(x1 - x2) < 0.1 and abs(y1 - y2) < 0.1:
            return
        self.closing_line_start = (x1, y1)
        self.closing_line_end = (x2, y2)
        px1 = self.cm_to_px(x1, y1)
        px2 = self.cm_to_px(x2, y2)
        self.closing_line_points = [px1[0], px1[1], px2[0], px2[1]]
        Color(*self.closing_line_color)
        Line(points=self.closing_line_points,
             width=2, dash_length=10, dash_offset=5)

    def is_room_closed(self):
        """← НОВОЕ: Проверяет, действительно ли комната замкнута"""
        if len(self.walls) < 3:
            return False
        # Получаем первую точку первой стены
        first_wall = self.walls[0]
        first_point = (first_wall[0], first_wall[1])
        # Получаем последнюю точку последней стены
        last_wall = self.walls[-1]
        last_point = (last_wall[2], last_wall[3])
        # Проверяем, совпадают ли точки (с небольшой погрешностью)
        distance = math.sqrt((first_point[0] - last_point[0])**2 + (first_point[1] - last_point[1])**2)
        return distance < 0.1  # Если точки очень близки, комната замкнута

    def point_to_line_distance(self, px, py, x1, y1, x2, y2):
        if x1 == x2 and y1 == y2:
            return math.sqrt((px - x1)**2 + (py - y1)**2)
        line_vec_x = x2 - x1
        line_vec_y = y2 - y1
        point_vec_x = px - x1
        point_vec_y = py - y1
        line_len = math.sqrt(line_vec_x**2 + line_vec_y**2)
        if line_len > 0:
            line_vec_x /= line_len
            line_vec_y /= line_len
            projection_length = point_vec_x * line_vec_x + point_vec_y * line_vec_y
            projection_length = max(0, min(line_len, projection_length))
            closest_x = x1 + projection_length * line_vec_x
            closest_y = y1 + projection_length * line_vec_y
            return math.sqrt((px - closest_x)**2 + (py - closest_y)**2)
        return 0

    def _polygon_signed_area(self, pts):
        area = 0.0
        n = len(pts)
        for i in range(n):
            x1, y1 = pts[i]
            x2, y2 = pts[(i + 1) % n]
            area += x1 * y2 - x2 * y1
        return area / 2.0

    def _is_ccw(self, pts):
        return self._polygon_signed_area(pts) > 0

    def _point_in_triangle(self, p, a, b, c):
        # barycentric technique
        px, py = p
        ax, ay = a
        bx, by = b
        cx, cy = c
        v0x, v0y = cx - ax, cy - ay
        v1x, v1y = bx - ax, by - ay
        v2x, v2y = px - ax, py - ay
        dot00 = v0x * v0x + v0y * v0y
        dot01 = v0x * v1x + v0y * v1y
        dot02 = v0x * v2x + v0y * v2y
        dot11 = v1x * v1x + v1y * v1y
        dot12 = v1x * v2x + v1y * v2y
        denom = dot00 * dot11 - dot01 * dot01
        if abs(denom) < 1e-9:
            return False
        inv = 1.0 / denom
        u = (dot11 * dot02 - dot01 * dot12) * inv
        v = (dot00 * dot12 - dot01 * dot02) * inv
        return (u >= 0) and (v >= 0) and (u + v <= 1)

    def _earclip_triangulate(self, pts):
        # pts: list[(x,y)] without duplicate closing point; simple polygon
        if len(pts) < 3:
            return []
        idxs = list(range(len(pts)))
        if not self._is_ccw(pts):
            idxs.reverse()

        def is_convex(i0, i1, i2):
            ax, ay = pts[i0]
            bx, by = pts[i1]
            cx, cy = pts[i2]
            return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) > 0

        triangles = []
        guard = 0
        while len(idxs) > 3 and guard < 10000:
            guard += 1
            ear_found = False
            for k in range(len(idxs)):
                i_prev = idxs[(k - 1) % len(idxs)]
                i_curr = idxs[k]
                i_next = idxs[(k + 1) % len(idxs)]
                if not is_convex(i_prev, i_curr, i_next):
                    continue
                a = pts[i_prev]
                b = pts[i_curr]
                c = pts[i_next]
                any_inside = False
                for j in idxs:
                    if j in (i_prev, i_curr, i_next):
                        continue
                    if self._point_in_triangle(pts[j], a, b, c):
                        any_inside = True
                        break
                if any_inside:
                    continue
                triangles.append((i_prev, i_curr, i_next))
                idxs.pop(k)
                ear_found = True
                break
            if not ear_found:
                # polygon may be self-intersecting; abort
                return []
        if len(idxs) == 3:
            triangles.append((idxs[0], idxs[1], idxs[2]))
        return triangles

    def draw_room_fill(self):
        """Заливка внутренней области комнаты (впуклые тоже)"""
        if len(self.walls) < 3 or not self.room_closed:
            return

        # Собираем точки в порядке обхода
        # Стены идут последовательно: конец одной стены = начало следующей
        points = []
        if not self.walls:
            return
        
        # Добавляем начальную точку первой стены
        first_wall = self.walls[0]
        points.append((first_wall[0], first_wall[1]))
        
        # Добавляем конечные точки всех стен
        for wall in self.walls:
            points.append((wall[2], wall[3]))

        # Удаляем дубликаты подряд
        unique_points = []
        for i, point in enumerate(points):
            if i == 0 or point != points[i-1]:
                unique_points.append(point)

        # ← КРИТИЧНО: Убеждаемся, что полигон замкнут
        if len(unique_points) < 3:
            return
        
        # Если первая и последняя точки не совпадают, замыкаем полигон
        if unique_points[0] != unique_points[-1]:
            unique_points.append(unique_points[0])

        if len(unique_points) < 4:  # Минимум 3 точки + замыкающая
            return

        poly_pts = unique_points[:-1]  # без замыкающей точки
        if len(poly_pts) < 3:
            return

        screen_pts = []
        for x, y in poly_pts:
            px, py = self.cm_to_px(x, y)
            screen_pts.append((px, py))

        tris = self._earclip_triangulate(screen_pts)
        if not tris:
            return

        vertices = []
        for x, y in screen_pts:
            vertices.extend([x, y, 0, 0])
        indices = []
        for a, b, c in tris:
            indices.extend([a, b, c])

        with self.canvas:
            Color(*self.room_color)
            Mesh(vertices=vertices, indices=indices, mode="triangles")

    def draw_walls(self):
        if not self.walls:
            return
        Color(*self.wall_color)
        for wall in self.walls:
            x1, y1, x2, y2 = wall
            px1 = self.cm_to_px(x1, y1)
            px2 = self.cm_to_px(x2, y2)
            Line(points=[px1[0], px1[1], px2[0], px2[1]], width=3)

    def draw_current_point(self):
        x, y = self.current_pos_cm
        px_x, px_y = self.cm_to_px(x, y)
        Color(*self.point_color)
        Ellipse(pos=(px_x - 6, px_y - 6), size=(12, 12))

    def save_state(self):
        # undo_stack хранит СНИМКИ ТЕКУЩЕГО состояния (после действий)
        if self._saving_state:
            return
        self._saving_state = True
        self.undo_stack.append(self._snapshot())
        self.redo_stack = []
        self._saving_state = False

    def undo(self):
        if len(self.undo_stack) <= 1:
            return False
        current = self.undo_stack.pop()
        self.redo_stack.append(current)
        prev = self.undo_stack[-1]
        self._apply_state(prev)
        self.room_closed = self.is_room_closed()
        self.canvas.clear()
        self.draw_editor()
        self._notify_change()
        return True

    def redo(self):
        if not self.redo_stack:
            return False
        state = self.redo_stack.pop()
        self.undo_stack.append(state)
        self._apply_state(state)
        self.room_closed = self.is_room_closed()
        self.canvas.clear()
        self.draw_editor()
        self._notify_change()
        return True

    def add_wall(self, direction, length_cm):
        # ← КРИТИЧНО: При добавлении новой стены комната становится незамкнутой
        self.room_closed = False
        self.closing_line_start = None
        self.closing_line_end = None
        self.closing_line_points = []
        x1, y1 = self.current_pos_cm
        if direction in ['up_left', 'up_right', 'down_left', 'down_right']:
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
            return
        self.walls.append([x1, y1, x2, y2])
        self.current_pos_cm = [x2, y2]
        # ← КРИТИЧНО: После добавления стены проверяем, не замкнулась ли комната автоматически
        if len(self.walls) >= 3:
            self.room_closed = self.is_room_closed()
        self.canvas.clear()
        self.draw_editor()
        self.save_state()
        self._notify_change()
        return (x2, y2)

    def reset(self):
        self.current_pos_cm = [0, 0]
        self.walls = []
        self.undo_stack = []
        self.redo_stack = []
        self.room_closed = False
        self.closing_line_start = None
        self.closing_line_end = None
        self.closing_line_points = []
        self.save_state()
        self.canvas.clear()
        self.draw_editor()
        self._notify_change()

    def add_closing_wall(self):
        """← ИСПРАВЛЕНО: Добавляет замыкающую стену и сохраняет состояние"""
        if len(self.walls) < 3 or not self.closing_line_start or not self.closing_line_end:
            return False
        
        # Получаем координаты замыкающей линии
        x1, y1 = self.closing_line_end
        x2, y2 = self.closing_line_start
        
        # ← КРИТИЧНО: Добавляем стену как обычную стену
        # Формат стены: [x1, y1, x2, y2]
        closing_wall = [x1, y1, x2, y2]
        self.walls.append(closing_wall)
        
        # Обновляем текущую позицию
        self.current_pos_cm = [x2, y2]
        
        # ← КРИТИЧНО: Проверяем закрытость после добавления стены
        self.room_closed = self.is_room_closed()
        
        # Очищаем данные замыкающей линии
        self.closing_line_start = None
        self.closing_line_end = None
        self.closing_line_points = []
        
        # Перерисовываем
        self.canvas.clear()
        self.draw_editor()
        self.save_state()
        self._notify_change()
        return True  # ← Возвращаем True для обновления info

    def get_distance(self, touch1, touch2):
        return ((touch1.x - touch2.x) ** 2 + (touch1.y - touch2.y) ** 2) ** 0.5

    def get_center(self, touch1, touch2):
        return ((touch1.x + touch2.x) / 2, (touch1.y + touch2.y) / 2)

    def on_touch_down(self, touch):
        if self.collide_point(*touch.pos):
            if self.is_touch_on_closing_line(touch):
                if self.add_closing_wall():
                    pass
                return True
            if touch.is_mouse_scrolling:
                if touch.button == 'scrolldown':
                    self.scale = max(0.1, self.scale - 0.05)
                elif touch.button == 'scrollup':
                    self.scale = min(3.0, self.scale + 0.05)
                self.canvas.clear()
                self.draw_editor()
                return True
            self.touches[touch.id] = touch
            if len(self.touches) == 2:
                touches = list(self.touches.values())
                self.pinch_start_distance = self.get_distance(
                    touches[0], touches[1])
                self.pinch_start_scale = self.scale
                self.pinch_center = self.get_center(touches[0], touches[1])
                return True
            self.dragging = True
            self.last_touch_pos = (touch.x, touch.y)
            return True
        return super().on_touch_down(touch)

    def is_touch_on_closing_line(self, touch, tolerance=dp(10)):
        if not self.closing_line_points or len(self.closing_line_points) != 4:
            return False
        x1, y1, x2, y2 = self.closing_line_points
        px, py = touch.pos
        dist = self.point_to_line_distance(px, py, x1, y1, x2, y2)
        return dist < tolerance

    def on_touch_move(self, touch):
        if touch.id in self.touches and len(self.touches) == 2:
            touches = list(self.touches.values())
            current_distance = self.get_distance(touches[0], touches[1])
            if self.pinch_start_distance:
                scale_factor = current_distance / self.pinch_start_distance
                new_scale = self.pinch_start_scale * scale_factor
                new_scale = max(0.1, min(3.0, new_scale))
                if self.pinch_center:
                    old_center_x = (
                        self.pinch_center[0] - self.offset_x) / self.scale
                    old_center_y = (
                        self.pinch_center[1] - self.offset_y) / self.scale
                    self.scale = new_scale
                    self.offset_x = self.pinch_center[0] - \
                        old_center_x * self.scale
                    self.offset_y = self.pinch_center[1] - \
                        old_center_y * self.scale
                    self.canvas.clear()
                    self.draw_editor()
                    return True
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

    def format_dimension(self, length_cm):
        if length_cm == int(length_cm):
            return f"{int(length_cm):,}".replace(",", " ")
        else:
            return f"{length_cm:.1f}".replace(".", ",")

    def draw_wall_dimensions(self):
        if not self.walls:
            return
        from kivy.core.text import Label as CoreLabel
        from kivy.graphics import Color, Rectangle
        import math
        for wall in self.walls:
            x1, y1, x2, y2 = wall
            length = math.sqrt((x2 - x1)**2 + (y2 - y1)**2)
            mid_x = (x1 + x2) / 2
            mid_y = (y1 + y2) / 2
            dx = x2 - x1
            dy = y2 - y1
            length_wall = math.sqrt(dx**2 + dy**2)
            if length_wall > 0:
                nx = -dy / length_wall
                ny = dx / length_wall
                offset = 10
                text_x = mid_x + nx * offset
                text_y = mid_y + ny * offset
                px_x, px_y = self.cm_to_px(text_x, text_y)
                text = self.format_dimension(length) + " см"
                base_font_px = 60 * self.scale
                font_size = base_font_px * 0.75
                font_size = max(8, min(30, font_size))
                label = CoreLabel(
                    text=text, font_size=font_size, color=(0, 0, 0, 1))
                label.refresh()
                padding = 2
                Color(1, 1, 1, 0.7)
                Rectangle(
                    pos=(px_x - label.texture.size[0]/2 - padding,
                         px_y - label.texture.size[1]/2 - padding),
                    size=(label.texture.size[0] + padding*2,
                          label.texture.size[1] + padding*2)
                )
                Color(0, 0, 0, 1)
                Rectangle(
                    texture=label.texture,
                    pos=(px_x - label.texture.size[0]/2,
                         px_y - label.texture.size[1]/2),
                    size=label.texture.size
                )

    def clear_undo_stack(self):
        """← ИСПРАВЛЕНО: Очищает стек и создает ТОЛЬКО ОДНО начальное состояние"""
        # ← КРИТИЧНО: Сначала очищаем стек полностью
        self.undo_stack = []
        self.redo_stack = []
        # ← КРИТИЧНО: Правильно определяем закрытость перед сохранением
        if hasattr(self, 'is_room_closed'):
            self.room_closed = self.is_room_closed()
        self.save_state()
