from kivy.uix.widget import Widget
from kivy.graphics import Color, Line, Rectangle, Mesh
from kivy.properties import NumericProperty, ObjectProperty, BooleanProperty
from kivy.metrics import dp
from kivy.core.text import Label as CoreLabel
from kivy.clock import Clock
from functools import partial
import math


class LayoutWidget(Widget):
    """Виджет для отображения раскладки 60×60 см"""
    scale = NumericProperty(0.3)
    offset_x = NumericProperty(0)
    offset_y = NumericProperty(0)
    grid_offset_x = NumericProperty(0)
    grid_offset_y = NumericProperty(0)
    on_grid_move = ObjectProperty(None)
    on_lights_changed = ObjectProperty(None)
    dragging_enabled = BooleanProperty(True)
    light_placement_mode = BooleanProperty(False)
    show_dimensions = BooleanProperty(True)
    show_wall_dimensions = BooleanProperty(True)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.walls = []
        self.layout = None
        self.room_bounds = None
        self.is_rotated = False
        self.rotation_angle = 0
        self.redraw_scheduled = False
        self.last_redraw_time = 0
        self.dragging_enabled = True
        self.panning = False
        self.last_pan_pos = None
        self.dragging = False
        self.last_touch_pos = None
        self.touches = {}
        self.pinch_start_distance = None
        self.pinch_start_scale = None
        self.pinch_center = None
        self.bg_color = (0.12, 0.13, 0.13, 1)
        self.wall_color = (0.94, 0.96, 0.98, 1)
        self.room_color = (0.32, 0.38, 0.42, 1)
        self.grid_color = (0.79, 0.84, 0.87, 0.7)
        self.full_tile_color = (0.9, 0.9, 0.9, 0.3)
        self.cut_tile_color = (0.7, 0.7, 0.7, 0.3)
        self.light_tile_color = (1.0, 0.96, 0.72, 0.85)
        self.light_fixtures = set()
        self._light_touch_start = None
        self.TILE_SIZE = 60
        self.text_color = (0.94, 0.96, 0.98, 1)
        self.bind(size=self._update_canvas)

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

    def _walls_ccw(self):
        if not self.walls:
            return True
        pts = [(self.walls[0][0], self.walls[0][1])]
        for wall in self.walls:
            pts.append((wall[2], wall[3]))
        if len(pts) > 1 and pts[0] == pts[-1]:
            pts = pts[:-1]
        if len(pts) < 3:
            return True
        return self._is_ccw(pts)

    def _point_in_triangle(self, p, a, b, c):
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
                return []
        if len(idxs) == 3:
            triangles.append((idxs[0], idxs[1], idxs[2]))
        return triangles

    def _update_canvas(self, *args):
        try:
            if hasattr(self, 'room_bounds') and self.room_bounds:
                self.center_room()
                if hasattr(self, 'draw_layout'):
                    self.draw_layout()
        except Exception as e:
            print(f"Ошибка при обновлении канваса: {e}")

    def set_room(self, walls):
        self.walls = walls
        if not walls:
            return
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
        self.center_room()
        self.grid_offset_x = 0
        self.grid_offset_y = 0
        self.draw_layout()

    def center_room(self):
        if not self.room_bounds:
            return
        min_x, max_x = self.room_bounds['min_x'], self.room_bounds['max_x']
        min_y, max_y = self.room_bounds['min_y'], self.room_bounds['max_y']
        room_width = max_x - min_x
        room_height = max_y - min_y
        if room_width <= 0:
            room_width = 10
        if room_height <= 0:
            room_height = 10
        padding_top = 0.12
        padding_bottom = 0.12
        padding_sides = 0.10
        available_height = self.height * (1 - padding_top - padding_bottom)
        available_width = self.width * (1 - 2 * padding_sides)
        scale_x = available_width / room_width if room_width > 0 else 0.3
        scale_y = available_height / room_height if room_height > 0 else 0.3
        self.scale = min(scale_x, scale_y)
        self.scale = max(0.1, min(self.scale, 1.0))
        room_center_x = (min_x + max_x) / 2
        room_center_y = (min_y + max_y) / 2
        widget_center_x = self.width / 2
        widget_center_y = self.height / 2
        self.offset_x = widget_center_x - room_center_x * self.scale
        self.offset_y = widget_center_y - room_center_y * self.scale
        bottom_bound = self.offset_y + min_y * self.scale
        top_bound = self.offset_y + max_y * self.scale
        min_top_padding = self.height * padding_top
        min_bottom_padding = self.height * padding_bottom
        if top_bound > self.height - min_top_padding:
            self.offset_y -= (top_bound - (self.height - min_top_padding))
        if bottom_bound < min_bottom_padding:
            self.offset_y += (min_bottom_padding - bottom_bound)

    def cm_to_px(self, cm_x, cm_y):
        px_x = self.offset_x + cm_x * self.scale
        px_y = self.offset_y + cm_y * self.scale
        return px_x, px_y

    def draw_layout(self):
        from kivy.graphics import StencilPush, StencilUse, StencilUnUse, StencilPop

        self.canvas.clear()
        with self.canvas:
            # Клиппинг по рамке виджета раскладки,
            # чтобы не перекрывать верх/низ экрана
            StencilPush()
            Rectangle(pos=self.pos, size=self.size)
            StencilUse()

            Color(*self.bg_color)
            Rectangle(pos=self.pos, size=self.size)
            self.draw_room_fill()
            self.draw_grid_tiles()
            self.draw_walls()
            if self.show_wall_dimensions:
                self.draw_wall_dimensions()
            if self.show_dimensions:
                self.draw_all_cut_dimensions()

            StencilUnUse()
            Rectangle(pos=self.pos, size=self.size)
            StencilPop()

    def draw_wall_dimensions(self):
        """← ИСПРАВЛЕНО: Показываем float с 1 знаком"""
        if not self.walls:
            return
        from kivy.graphics import PushMatrix, PopMatrix, Rotate
        ccw = self._walls_ccw()
        for wall in self.walls:
            x1, y1, x2, y2 = wall
            length = math.sqrt((x2 - x1)**2 + (y2 - y1)**2)
            mid_x = (x1 + x2) / 2
            mid_y = (y1 + y2) / 2
            dx = x2 - x1
            dy = y2 - y1
            angle_degrees = math.degrees(math.atan2(dy, dx))
            if angle_degrees > 90 or angle_degrees < -90:
                angle_degrees += 180
            length_wall = math.sqrt(dx**2 + dy**2)
            if length_wall > 0:
                # Левый нормаль; для CCW он направлен внутрь, инвертируем
                nx = -dy / length_wall
                ny = dx / length_wall
                if ccw:
                    nx = -nx
                    ny = -ny
                offset = 100
                text_x = mid_x + nx * offset
                text_y = mid_y + ny * offset
                px_x, px_y = self.cm_to_px(text_x, text_y)
                # ← ИСПРАВЛЕНО: Показываем float с 1 знаком
                if length == int(length):
                    text = f"{int(length):,}".replace(",", " ") + " см"
                else:
                    text = f"{length:.1f}".replace(".", ",") + " см"
                base_font_px = 60 * self.scale
                font_size = base_font_px * 0.75
                font_size = max(8, min(30, font_size))
                label = CoreLabel(text=text, font_size=font_size, color=(
                    0, 0, 0, 1), angle=angle_degrees)
                label.refresh()
                padding = 4
                Color(1, 1, 1, 0.85)
                PushMatrix()
                Rotate(angle=angle_degrees, origin=(px_x, px_y, 0))
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
                PopMatrix()

    def draw_all_cut_dimensions(self):
        if not self.layout or not self.layout.tiles:
            return

        def fmt_cut(value):
            # Показываем до 0.1 см, чтобы не терять пограничные подрезки
            v = round(max(0.0, min(60.0, value)), 1)
            if abs(v - round(v)) < 0.05:
                return f"{int(round(v))}"
            return f"{v:.1f}".replace(".", ",")

        show_cut_threshold = 59.95  # все, что заметно меньше 60 см, считаем подрезкой

        for tile in self.layout.tiles:
            if tile['type'] != 'cut':
                continue
            remaining_x = tile.get('cut_x', 60.0)
            remaining_y = tile.get('cut_y', 60.0)
            texts = []
            if remaining_x < show_cut_threshold:
                texts.append(fmt_cut(remaining_x))
            if remaining_y < show_cut_threshold:
                texts.append(fmt_cut(remaining_y))
            if not texts:
                continue
            text = f"{texts[0]}×{texts[1]}" if len(texts) == 2 else texts[0]
            x1, y1, x2, y2 = tile['x1'], tile['y1'], tile['x2'], tile['y2']
            center_x = (x1 + x2) / 2
            center_y = (y1 + y2) / 2
            px_center = self.cm_to_px(center_x, center_y)
            tile_height_px = 60 * self.scale
            if '×' in text:
                font_scale = 0.30
            else:
                font_scale = 0.50
            font_size = tile_height_px * font_scale
            font_size = max(8, min(30, font_size))
            label = CoreLabel(text=text, font_size=font_size,
                              color=self.text_color, bold=True)
            label.refresh()
            pos_x = px_center[0] - label.texture.size[0] / 2
            pos_y = px_center[1] - label.texture.size[1] / 2
            padding_x = label.texture.size[0] * 0.05
            padding_y = label.texture.size[1] * 0.05
            Color(0, 0, 0, 0.3)
            Rectangle(
                pos=(pos_x - padding_x, pos_y - padding_y),
                size=(label.texture.size[0] + padding_x * 2,
                      label.texture.size[1] + padding_y * 2)
            )
            Color(*self.text_color)
            Rectangle(
                texture=label.texture,
                pos=(pos_x, pos_y),
                size=label.texture.size
            )

    def draw_room_fill(self):
        """Заливка внутренней области комнаты (впуклые тоже)"""
        if len(self.walls) < 3:
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

        poly_pts = unique_points[:-1]
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

    def _visible_world_bounds(self):
        """Возвращает видимую область в мировых координатах (см)."""
        # Важно использовать реальные координаты виджета на экране,
        # иначе culling будет обрезать содержимое сверху/сбоку.
        min_x = (self.x - self.offset_x) / self.scale
        max_x = (self.right - self.offset_x) / self.scale
        min_y = (self.y - self.offset_y) / self.scale
        max_y = (self.top - self.offset_y) / self.scale
        return min_x, max_x, min_y, max_y

    def _tile_visible(self, tile, world_bounds, margin_cm=60):
        min_x, max_x, min_y, max_y = world_bounds
        return not (
            tile['x2'] < min_x - margin_cm or
            tile['x1'] > max_x + margin_cm or
            tile['y2'] < min_y - margin_cm or
            tile['y1'] > max_y + margin_cm
        )

    def _append_rect_mesh(self, vertices, indices, x1, y1, x2, y2):
        base = len(vertices) // 4
        vertices.extend([x1, y1, 0, 0])
        vertices.extend([x2, y1, 0, 0])
        vertices.extend([x2, y2, 0, 0])
        vertices.extend([x1, y2, 0, 0])
        indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])

    def _append_rect_line_mesh(self, vertices, indices, x1, y1, x2, y2):
        base = len(vertices) // 4
        vertices.extend([x1, y1, 0, 0])
        vertices.extend([x2, y1, 0, 0])
        vertices.extend([x2, y2, 0, 0])
        vertices.extend([x1, y2, 0, 0])
        indices.extend([
            base, base + 1,
            base + 1, base + 2,
            base + 2, base + 3,
            base + 3, base
        ])

    def tile_cell_key(self, tile):
        """Индекс ячейки относительно смещения сетки — сохраняется при движении сетки."""
        gx = self.grid_offset_x
        gy = self.grid_offset_y
        ts = self.TILE_SIZE
        return (
            int(round((tile['x1'] - gx) / ts)),
            int(round((tile['y1'] - gy) / ts)),
        )

    def set_light_fixtures(self, fixtures):
        self.light_fixtures = set()
        for item in fixtures or []:
            if isinstance(item, (list, tuple)) and len(item) >= 2:
                self.light_fixtures.add((int(item[0]), int(item[1])))

    def light_fixtures_list(self):
        return sorted([list(k) for k in self.light_fixtures])

    def prune_outside_light_fixtures(self):
        """Убирает светильники, чья ячейка полностью вышла за контур помещения."""
        if not self.light_fixtures:
            return False
        if not self.layout or not self.layout.tiles:
            return False
        valid_keys = set()
        for tile in self.layout.tiles:
            if tile["type"] == "outside":
                continue
            if tile["type"] == "cut":
                if tile.get("cut_x", 0) < 1.0 or tile.get("cut_y", 0) < 1.0:
                    continue
            valid_keys.add(self.tile_cell_key(tile))
        stale = self.light_fixtures - valid_keys
        if not stale:
            return False
        self.light_fixtures -= stale
        if self.on_lights_changed:
            self.on_lights_changed()
        return True

    def world_cm_from_touch(self, touch):
        return (
            (touch.x - self.offset_x) / self.scale,
            (touch.y - self.offset_y) / self.scale,
        )

    def find_tile_at_world(self, wx, wy):
        if not self.layout or not self.layout.tiles:
            return None
        for tile in self.layout.tiles:
            if tile['type'] == 'outside':
                continue
            if tile['x1'] <= wx < tile['x2'] and tile['y1'] <= wy < tile['y2']:
                if tile['type'] == 'cut':
                    cut_x = tile.get('cut_x', 0)
                    cut_y = tile.get('cut_y', 0)
                    if cut_x < 1.0 or cut_y < 1.0:
                        continue
                return tile
        return None

    def toggle_light_at_touch(self, touch):
        wx, wy = self.world_cm_from_touch(touch)
        tile = self.find_tile_at_world(wx, wy)
        if not tile:
            return
        key = self.tile_cell_key(tile)
        if key in self.light_fixtures:
            self.light_fixtures.discard(key)
        else:
            self.light_fixtures.add(key)
        if self.on_lights_changed:
            self.on_lights_changed()
        self.draw_layout()

    def draw_grid_tiles(self):
        if not self.layout or not self.layout.tiles:
            return
        visible_bounds = self._visible_world_bounds()
        full_vertices, full_indices = [], []
        cut_vertices, cut_indices = [], []
        light_vertices, light_indices = [], []
        line_vertices, line_indices = [], []

        for tile in self.layout.tiles:
            if tile['type'] == 'outside':
                continue
            if not self._tile_visible(tile, visible_bounds):
                continue
            if tile['type'] == 'cut':
                cut_x = tile.get('cut_x', 0)
                cut_y = tile.get('cut_y', 0)
                # Если подрезка по любой оси практически нулевая — не рисуем плитку
                if cut_x < 1.0 or cut_y < 1.0:
                    continue
            x1, y1, x2, y2 = tile['x1'], tile['y1'], tile['x2'], tile['y2']
            px1 = self.cm_to_px(x1, y1)
            px2 = self.cm_to_px(x2, y2)
            rx1, rx2 = min(px1[0], px2[0]), max(px1[0], px2[0])
            ry1, ry2 = min(px1[1], px2[1]), max(px1[1], px2[1])
            cell_key = self.tile_cell_key(tile)
            is_light = cell_key in self.light_fixtures
            if is_light:
                self._append_rect_mesh(light_vertices, light_indices, rx1, ry1, rx2, ry2)
            elif tile['type'] == 'full':
                self._append_rect_mesh(full_vertices, full_indices, rx1, ry1, rx2, ry2)
            else:
                self._append_rect_mesh(cut_vertices, cut_indices, rx1, ry1, rx2, ry2)
            self._append_rect_line_mesh(line_vertices, line_indices, rx1, ry1, rx2, ry2)

        if full_vertices:
            Color(*self.full_tile_color)
            Mesh(vertices=full_vertices, indices=full_indices, mode='triangles')
        if cut_vertices:
            Color(*self.cut_tile_color)
            Mesh(vertices=cut_vertices, indices=cut_indices, mode='triangles')
        if light_vertices:
            Color(*self.light_tile_color)
            Mesh(vertices=light_vertices, indices=light_indices, mode='triangles')
        if line_vertices:
            Color(*self.grid_color)
            Mesh(vertices=line_vertices, indices=line_indices, mode='lines')

    def schedule_redraw(self):
        if not self.redraw_scheduled:
            self.redraw_scheduled = True
            Clock.schedule_once(self.redraw_now, 0.05)

    def redraw_now(self, dt):
        self.redraw_scheduled = False
        self.draw_layout()

    def move_grid(self, dx_cm, dy_cm):
        self.grid_offset_x = (self.grid_offset_x + dx_cm) % 60
        self.grid_offset_y = (self.grid_offset_y + dy_cm) % 60
        if self.on_grid_move:
            self.on_grid_move(self.grid_offset_x, self.grid_offset_y)
        self.schedule_redraw()

    def zoom_at_center(self, zoom_in=True):
        center_world_x = (self.width / 2 - self.offset_x) / self.scale
        center_world_y = (self.height / 2 - self.offset_y) / self.scale
        if zoom_in:
            new_scale = min(3.0, self.scale + 0.05)
        else:
            new_scale = max(0.1, self.scale - 0.05)
        new_offset_x = self.width / 2 - center_world_x * new_scale
        new_offset_y = self.height / 2 - center_world_y * new_scale
        self.scale = new_scale
        self.offset_x = new_offset_x
        self.offset_y = new_offset_y
        self.apply_bounds_protection()
        self.canvas.clear()
        if hasattr(self, 'draw_editor'):
            self.draw_editor()
        else:
            self.draw_layout()

    def zoom_at_point(self, screen_x, screen_y, zoom_in=True):
        """Масштабирует относительно заданной точки экрана."""
        if self.scale <= 0:
            return
        world_x = (screen_x - self.offset_x) / self.scale
        world_y = (screen_y - self.offset_y) / self.scale
        if zoom_in:
            new_scale = min(2.0, self.scale + 0.05)
        else:
            new_scale = max(0.1, self.scale - 0.05)
        self.scale = new_scale
        self.offset_x = screen_x - world_x * self.scale
        self.offset_y = screen_y - world_y * self.scale
        self.apply_bounds_protection()
        self.draw_layout()

    def apply_bounds_protection(self):
        if not self.room_bounds:
            return
        min_x = self.room_bounds['min_x']
        max_x = self.room_bounds['max_x']
        min_y = self.room_bounds['min_y']
        max_y = self.room_bounds['max_y']
        visible_min_x = (0 - self.offset_x) / self.scale
        visible_max_x = (self.width - self.offset_x) / self.scale
        visible_min_y = (0 - self.offset_y) / self.scale
        visible_max_y = (self.height - self.offset_y) / self.scale
        if max_x < visible_min_x:
            self.offset_x += (visible_min_x - max_x) * self.scale
        if min_x > visible_max_x:
            self.offset_x -= (min_x - visible_max_x) * self.scale
        if max_y < visible_min_y:
            self.offset_y += (visible_min_y - max_y) * self.scale
        if min_y > visible_max_y:
            self.offset_y -= (min_y - visible_max_y) * self.scale

    def get_distance(self, touch1, touch2):
        return ((touch1.x - touch2.x) ** 2 + (touch1.y - touch2.y) ** 2) ** 0.5

    def get_center(self, touch1, touch2):
        return ((touch1.x + touch2.x) / 2, (touch1.y + touch2.y) / 2)

    def on_touch_down(self, touch):
        if self.collide_point(*touch.pos):
            if touch.is_mouse_scrolling:
                if touch.button == 'scrolldown':
                    self.zoom_at_point(touch.x, touch.y, zoom_in=False)
                elif touch.button == 'scrollup':
                    self.zoom_at_point(touch.x, touch.y, zoom_in=True)
                return True
            self.touches[touch.id] = touch
            if len(self.touches) == 2:
                touches = list(self.touches.values())
                self.pinch_start_distance = self.get_distance(
                    touches[0], touches[1])
                self.pinch_start_scale = self.scale
                self.pinch_center = self.get_center(touches[0], touches[1])
                return True
            if self.light_placement_mode:
                self._light_touch_start = touch.pos
                self.panning = True
                self.last_pan_pos = touch.pos
            elif self.dragging_enabled:
                self.dragging = True
                self.last_touch_pos = touch.pos
            else:
                self.panning = True
                self.last_pan_pos = touch.pos
            return True
        return super().on_touch_down(touch)

    def on_touch_move(self, touch):
        if touch.id in self.touches and len(self.touches) == 2:
            touches = list(self.touches.values())
            current_distance = self.get_distance(touches[0], touches[1])
            if self.pinch_start_distance:
                scale_factor = current_distance / self.pinch_start_distance
                new_scale = self.pinch_start_scale * scale_factor
                new_scale = max(0.1, min(2.0, new_scale))
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
                    self.draw_layout()
                    return True
        if self.dragging and self.dragging_enabled:
            dx_px = touch.x - self.last_touch_pos[0]
            dy_px = touch.y - self.last_touch_pos[1]
            dx_cm = round(dx_px / self.scale)
            dy_cm = round(dy_px / self.scale)
            self.grid_offset_x += dx_cm
            self.grid_offset_y += dy_cm
            self.last_touch_pos = touch.pos
            if self.on_grid_move:
                self.on_grid_move()
            self.draw_layout()
            return True
        if self.panning and not self.dragging_enabled:
            dx = touch.x - self.last_pan_pos[0]
            dy = touch.y - self.last_pan_pos[1]
            self.offset_x += dx
            self.offset_y += dy
            self.last_pan_pos = touch.pos
            self.draw_layout()
            return True
        return super().on_touch_move(touch)

    def on_touch_up(self, touch):
        if (
            self.light_placement_mode
            and self._light_touch_start is not None
            and touch.id in self.touches
            and len(self.touches) <= 1
        ):
            dx = touch.x - self._light_touch_start[0]
            dy = touch.y - self._light_touch_start[1]
            tap_threshold = dp(14) ** 2
            if dx * dx + dy * dy <= tap_threshold:
                self.toggle_light_at_touch(touch)
        self.touches.pop(touch.id, None)
        self.pinch_start_distance = None
        self.pinch_center = None
        self.dragging = False
        self.panning = False
        self.last_touch_pos = None
        self.last_pan_pos = None
        self._light_touch_start = None
        return super().on_touch_up(touch)
