# models.py (изменим класс Room)
import json
from datetime import datetime
import math

class Project:
    """Класс проекта (здания/объекта)"""
    def __init__(self, name):
        self.id = None
        self.name = name
        self.created_at = datetime.now()
        self.rooms = []  # Список объектов Room

    def to_dict(self):
        """Конвертирует проект в словарь"""
        return {
            'id': self.id,
            'name': self.name,
            'created_at': self.created_at.isoformat(),
            'rooms': [room.to_dict() for room in self.rooms]
        }

    @classmethod
    def from_dict(cls, data):
        """Создает проект из словаря"""
        project = cls(data['name'])
        project.id = data['id']
        project.created_at = datetime.fromisoformat(data['created_at'])
        project.rooms = [Room.from_dict(room_data)
                         for room_data in data['rooms']]
        return project

class Room:
    """Класс комнаты"""
    def __init__(self, name):
        self.id = None
        self.name = name
        self.created_at = datetime.now()
        self.walls = []  # Список стен в формате [[x1, y1, x2, y2], ...]
        self.last_position = None # Добавлено для сохранения позиции в редакторе

    def to_dict(self):
        """Конвертирует комнату в словарь"""
        return {
            'id': self.id,
            'name': self.name,
            'created_at': self.created_at.isoformat(),
            'walls': self.walls,
            'last_position': self.last_position # Добавлено
        }

    @classmethod
    def from_dict(cls, data):
        """Создает комнату из словаря"""
        room = cls(data['name'])
        room.id = data['id']
        room.created_at = datetime.fromisoformat(data['created_at'])
        room.walls = data['walls']
        room.last_position = data.get('last_position') # Добавлено
        return room

# --- Остальная часть models.py остается без изменений ---
# (Класс CeilingLayout и его методы)
class CeilingLayout:
    """Класс для расчета раскладки потолка 60×60 см"""
    TILE_SIZE = 60  # 60 см

    def __init__(self, room):
        self.room = room
        self.grid_offset_x = 0  # Смещение сетки по X (0-59 см)
        self.grid_offset_y = 0  # Смещение сетки по Y (0-59 см)
        self.tiles = []  # Список плиток
        self.full_tiles = 0
        self.cut_tiles = 0
        self.waste_percentage = 0 # Процент отходов
        self.room_polygon = self._build_room_polygon()
        self.room_bounds = self.get_room_bounds()
        self.room_area_sqm = 0.0 # Новое поле для площади в м²

    def _build_room_polygon(self):
        """Предварительно строит полигон комнаты один раз"""
        if not self.room.walls:
            return []
        points = []
        for wall in self.room.walls:
            points.append((wall[0], wall[1]))
            points.append((wall[2], wall[3]))

        # Удаляем дубликаты и замыкаем полигон
        unique_points = []
        for point in points:
            if point not in unique_points:
                unique_points.append(point)
        if unique_points and unique_points[0] != unique_points[-1]:
            unique_points.append(unique_points[0])
        return unique_points

    def calculate_layout(self):
        """Рассчитывает раскладку для текущего смещения с учетом реальной геометрии комнаты"""
        # Сбрасываем статистику
        self.tiles = []
        self.full_tiles = 0
        self.cut_tiles = 0
        if not self.room.walls:
            self.calculate_statistics()
            return

        # 1. Находим ВСЕ возможные плитки в разумных пределах
        # Используем расширенный bounding box для поиска всех потенциально пересекающихся плиток
        all_x = []
        all_y = []
        for wall in self.room.walls:
            x1, y1, x2, y2 = wall
            all_x.extend([x1, x2])
            all_y.extend([y1, y2])

        min_x, max_x = min(all_x), max(all_x)
        min_y, max_y = min(all_y), max(all_y)

        # Расширяем поиск на 60 см во все стороны
        search_min_x = min_x - 60
        search_max_x = max_x + 60
        search_min_y = min_y - 60
        search_max_y = max_y + 60

        # 2. Определяем границы сетки
        grid_start_x = math.floor((search_min_x - self.grid_offset_x) /
                                  self.TILE_SIZE) * self.TILE_SIZE + self.grid_offset_x
        grid_start_y = math.floor((search_min_y - self.grid_offset_y) /
                                  self.TILE_SIZE) * self.TILE_SIZE + self.grid_offset_y

        # 3. Проходим по всем возможным плиткам
        x = grid_start_x
        while x < search_max_x:
            y = grid_start_y
            while y < search_max_y:
                tile_x2 = x + self.TILE_SIZE
                tile_y2 = y + self.TILE_SIZE

                # Анализируем плитку с учетом реальной геометрии
                tile_info = self.analyze_tile(x, y, tile_x2, tile_y2)
                if tile_info['type'] != 'outside':
                    self.tiles.append(tile_info)
                    if tile_info['type'] == 'full':
                        self.full_tiles += 1
                    elif tile_info['type'] == 'cut':
                        self.cut_tiles += 1
                y += self.TILE_SIZE
            x += self.TILE_SIZE

        # 4. Рассчитываем статистику
        self.calculate_statistics()

    def analyze_tile(self, x1, y1, x2, y2):
        """Анализирует плитку с учетом реальной геометрии комнаты"""
        # Сначала проверяем быстрый выход по bounding box
        room_min_x, room_max_x, room_min_y, room_max_y = self.get_room_bounds()

        # Если плитка полностью вне bounding box комнаты
        if x2 <= room_min_x or x1 >= room_max_x or y2 <= room_min_y or y1 >= room_max_y:
            return {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'type': 'outside', 'cut_x': 0, 'cut_y': 0}

        # Проверяем, полностью ли плитка внутри комнаты
        corners = [(x1, y1), (x2, y1), (x2, y2), (x1, y2)]
        corners_inside = sum(
            1 for corner in corners if self.is_point_inside_room(*corner))
        if corners_inside == 4:
            return {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'type': 'full', 'cut_x': 60, 'cut_y': 60}

        # Проверяем, полностью ли плитка снаружи (даже если пересекает bounding box)
        if corners_inside == 0:
            # Дополнительная проверка центра и промежуточных точек
            test_points = [
                ((x1 + x2) / 2, (y1 + y2) / 2),  # Центр
                (x1 + 20, y1 + 20), (x2 - 20, y2 - 20),  # Дополнительные точки
                (x1 + 20, y2 - 20), (x2 - 20, y1 + 20)
            ]
            points_inside = sum(
                1 for point in test_points if self.is_point_inside_room(*point))
            if points_inside == 0:
                return {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'type': 'outside', 'cut_x': 0, 'cut_y': 0}

        # Рассчитываем полезные размеры для резаной плитки
        useful_x, useful_y = self.calculate_cut_dimensions(x1, y1, x2, y2)

        # Если оба размера очень маленькие, считаем плитку снаружи
        if useful_x < 0.1 and useful_y < 0.1:
            return {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'type': 'outside', 'cut_x': 0, 'cut_y': 0}

        return {
            'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2,
            'type': 'cut',
            'cut_x': max(0.1, useful_x),
            'cut_y': max(0.1, useful_y)
        }

    def get_room_bounds(self):
        """Возвращает границы комнаты для быстрой проверки"""
        all_x = []
        all_y = []
        for wall in self.room.walls:
            x1, y1, x2, y2 = wall
            all_x.extend([x1, x2])
            all_y.extend([y1, y2])
        return min(all_x), max(all_x), min(all_y), max(all_y)

    def calculate_cut_dimensions(self, x1, y1, x2, y2):
        """Точный расчет полезных размеров плитки для любых форм комнат"""
        # 1. Сначала собираем все координаты стен
        all_x = []
        all_y = []
        for wall in self.room.walls:
            x1_w, y1_w, x2_w, y2_w = wall
            all_x.extend([x1_w, x2_w])
            all_y.extend([y1_w, y2_w])

        if not all_x or not all_y:
            return 0.0, 0.0

        # 2. Определяем границы комнаты
        room_min_x = min(all_x)
        room_max_x = max(all_x)
        room_min_y = min(all_y)
        room_max_y = max(all_y)

        # 3. Определяем, является ли комната прямоугольной (4 стены с прямыми углами)
        is_rectangular = False
        if len(self.room.walls) == 4:
            corners = set()
            for wall in self.room.walls:
                corners.add((wall[0], wall[1]))
                corners.add((wall[2], wall[3]))
            if len(corners) == 4:
                corner_x = sorted(set([p[0] for p in corners]))
                corner_y = sorted(set([p[1] for p in corners]))
                if (len(corner_x) == 2 and len(corner_y) == 2 and
                    room_min_x in corner_x and room_max_x in corner_x and
                    room_min_y in corner_y and room_max_y in corner_y):
                    is_rectangular = True

        if is_rectangular:
            # Для прямоугольных комнат используем точный метод как в старой версии
            intersect_x1 = max(x1, room_min_x)
            intersect_y1 = max(y1, room_min_y)
            intersect_x2 = min(x2, room_max_x)
            intersect_y2 = min(y2, room_max_y)

            if intersect_x1 >= intersect_x2 or intersect_y1 >= intersect_y2:
                return 0.0, 0.0

            # Округляем до целых сантиметров для избежания неточностей
            useful_x = round(intersect_x2 - intersect_x1)
            useful_y = round(intersect_y2 - intersect_y1)
            return max(0.0, min(60.0, useful_x)), max(0.0, min(60.0, useful_y))
        else:
            # === ОПТИМИЗИРОВАННЫЙ МЕТОД ДЛЯ СЛОЖНЫХ ФОРМ ===
            # Сначала проверяем углы плитки
            corners = [(x1, y1), (x2, y1), (x2, y2), (x1, y2)]
            corners_inside = [
                p for p in corners if self.is_point_inside_room(*p)]

            # Если все углы внутри - это не резаная плитка (должно обрабатываться выше)
            if len(corners_inside) == 4:
                return 60.0, 60.0

            # Если ни одного угла внутри, проверяем центр
            center = ((x1 + x2) / 2, (y1 + y2) / 2)
            if not corners_inside and not self.is_point_inside_room(*center):
                return 0.0, 0.0

            # 2. Находим пересечения с границами комнаты - ОСНОВНАЯ ОПТИМИЗАЦИЯ
            intersection_points = []

            # Проверяем пересечение каждой стены комнаты с границами плитки
            for wall in self.room.walls:
                wx1, wy1, wx2, wy2 = wall
                # Проверяем пересечение с каждой стороной плитки
                # Левая сторона плитки (x1, y1-y2)
                inter = self.line_intersection(
                    x1, y1, x1, y2, wx1, wy1, wx2, wy2)
                if inter:
                    intersection_points.append(inter)
                # Правая сторона плитки (x2, y1-y2)
                inter = self.line_intersection(
                    x2, y1, x2, y2, wx1, wy1, wx2, wy2)
                if inter:
                    intersection_points.append(inter)
                # Верхняя сторона плитки (x1-x2, y1)
                inter = self.line_intersection(
                    x1, y1, x2, y1, wx1, wy1, wx2, wy2)
                if inter:
                    intersection_points.append(inter)
                # Нижняя сторона плитки (x1-x2, y2)
                inter = self.line_intersection(
                    x1, y2, x2, y2, wx1, wy1, wx2, wy2)
                if inter:
                    intersection_points.append(inter)

            # 3. Собираем все точки, которые внутри комнаты
            inside_points = corners_inside.copy()
            if intersection_points:
                # Добавляем точки пересечения
                inside_points.extend(intersection_points)
            else:
                # Если нет пересечений, проверяем несколько ключевых точек внутри плитки
                key_points = [
                    (x1 + 20, y1 + 20), (x1 + 40, y1 + 20),
                    (x1 + 20, y1 + 40), (x1 + 40, y1 + 40),
                    (x1 + 30, y1 + 30)  # центр
                ]
                for px, py in key_points:
                    if self.is_point_inside_room(px, py):
                        inside_points.append((px, py))

            if not inside_points:
                return 0.0, 0.0

            # 4. Находим реальные границы по всем найденным точкам
            min_x = min(p[0] for p in inside_points)
            max_x = max(p[0] for p in inside_points)
            min_y = min(p[1] for p in inside_points)
            max_y = max(p[1] for p in inside_points)

            # 5. Дополнительно проверяем границы для точности в 1 см
            # Проверяем вертикальные срезы с шагом 10 см для уточнения границ
            for test_x in [x1 + 10, x1 + 20, x1 + 30, x1 + 40, x1 + 50]:
                # Проверяем верхнюю и нижнюю точки на этой вертикали
                if self.is_point_inside_room(test_x, y1 + 1) and test_x < max_x:
                    min_x = min(min_x, test_x)
                if self.is_point_inside_room(test_x, y2 - 1) and test_x > min_x:
                    max_x = max(max_x, test_x)
            # Проверяем горизонтальные срезы с шагом 10 см
            for test_y in [y1 + 10, y1 + 20, y1 + 30, y1 + 40, y1 + 50]:
                # Проверяем левую и правую точки на этой горизонтали
                if self.is_point_inside_room(x1 + 1, test_y) and test_y < max_y:
                    min_y = min(min_y, test_y)
                if self.is_point_inside_room(x2 - 1, test_y) and test_y > min_y:
                    max_y = max(max_y, test_y)

            # 6. Вычисляем полезные размеры с точностью до 1 см
            useful_x = max(0.0, min(60.0, round(max_x - min_x)))
            useful_y = max(0.0, min(60.0, round(max_y - min_y)))

            # Гарантируем минимальный размер 0.1 см для избежания деления на ноль
            return max(0.1, useful_x), max(0.1, useful_y)

    def line_intersection(self, x1, y1, x2, y2, x3, y3, x4, y4):
        """Находит точку пересечения двух отрезков или возвращает None"""
        # Проверяем, не являются ли линии параллельными
        denom = (y4-y3)*(x2-x1) - (x4-x3)*(y2-y1)
        if abs(denom) < 0.001:  # почти параллельны
            return None

        ua = ((x4-x3)*(y1-y3) - (y4-y3)*(x1-x3)) / denom
        ub = ((x2-x1)*(y1-y3) - (y2-y1)*(x1-x3)) / denom

        # Проверяем, пересекаются ли отрезки
        if ua < 0 or ua > 1 or ub < 0 or ub > 1:
            return None

        # Вычисляем точку пересечения
        x = x1 + ua * (x2-x1)
        y = y1 + ua * (y2-y1)

        # Проверяем, находится ли точка в пределах обоих отрезков
        if (min(x1, x2) - 1 <= x <= max(x1, x2) + 1 and
            min(y1, y2) - 1 <= y <= max(y1, y2) + 1 and
            min(x3, x4) - 1 <= x <= max(x3, x4) + 1 and
            min(y3, y4) - 1 <= y <= max(y3, y4) + 1):
            return (x, y)
        return None

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

    def is_point_on_wall(self, px, py, tolerance=0.5):
        """Проверяет, лежит ли точка на какой-либо стене комнаты"""
        for wall in self.room.walls:
            x1, y1, x2, y2 = wall
            distance = self.point_to_line_distance(px, py, x1, y1, x2, y2)
            if distance < tolerance:
                # Проверяем, попадает ли точка в пределы отрезка
                min_x, max_x = min(x1, x2), max(x1, x2)
                min_y, max_y = min(y1, y2), max(y1, y2)
                if (min_x - tolerance <= px <= max_x + tolerance and
                    min_y - tolerance <= py <= max_y + tolerance):
                    return True
        return False

    def is_point_inside_room(self, px, py):
        """Оптимизированная проверка с использованием кэшированного полигона"""
        if not self.room_polygon:
            return False

        # Быстрая проверка по bounding box
        min_x, max_x, min_y, max_y = self.room_bounds
        if px < min_x - 1 or px > max_x + 1 or py < min_y - 1 or py > max_y + 1:
            return False

        # Алгоритм ray casting с кэшированным полигоном
        inside = False
        j = len(self.room_polygon) - 1
        for i in range(len(self.room_polygon)):
            xi, yi = self.room_polygon[i]
            xj, yj = self.room_polygon[j]
            if ((yi > py) != (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi + 1e-10) + xi):
                inside = not inside
            j = i
        return inside

    def calculate_room_area(self):
        """Точный расчет площади комнаты методом триангуляции для сложных форм"""
        if not self.room.walls or len(self.room.walls) < 3:
            return 0

        # Собираем точки полигона комнаты
        points = []
        if self.room.walls:
            points.append((self.room.walls[0][0], self.room.walls[0][1]))
            for wall in self.room.walls:
                points.append((wall[2], wall[3]))
        # Замыкаем полигон
        if points[0] != points[-1]:
            points.append(points[0])

        # Метод Гаусса для расчета площади полигона
        area = 0
        n = len(points) - 1  # Последняя точка совпадает с первой
        for i in range(n):
            x1, y1 = points[i]
            x2, y2 = points[i + 1]
            area += x1 * y2 - x2 * y1
        return abs(area) / 2

    def calculate_statistics(self):
        """Рассчитывает статистику раскладки с правильным учетом площади комнаты"""
        if not self.room.walls:
            self.waste_percentage = 0
            self.room_area_sqm = 0.0
            return

        # 1. Точно считаем площадь комнаты в см²
        room_area_sqcm = self.calculate_room_area()
        # 2. Конвертируем площадь в м²
        self.room_area_sqm = room_area_sqcm / 10000.0 # 1 м² = 10000 см²

        # 3. Площадь целых плиток
        full_area = self.full_tiles * (self.TILE_SIZE * self.TILE_SIZE)
        # 4. Площадь полезной части резаных плиток
        cut_area_total = 0
        for tile in self.tiles:
            if tile['type'] == 'cut':
                useful_x = tile.get('cut_x', 0)
                useful_y = tile.get('cut_y', 0)
                useful_area = useful_x * useful_y
                cut_area_total += useful_area

        # 5. Общая полезная площадь
        useful_area_total = full_area + cut_area_total
        # 6. Общая площадь всех плиток (включая отходы)
        total_tiles_area = (self.full_tiles + self.cut_tiles) * \
                           (self.TILE_SIZE * self.TILE_SIZE)
        # 7. Отходы = вся площадь плиток - полезная площадь
        waste_area = total_tiles_area - useful_area_total
        # 8. Процент отходов относительно площади комнаты
        if room_area_sqcm > 0: # Проверка деления на ноль
            waste_percent = (waste_area / room_area_sqcm) * 100
            self.waste_percentage = round(waste_percent, 1)
        else:
            self.waste_percentage = 0

    def move_grid(self, dx, dy):
        """Смещает сетку"""
        self.grid_offset_x = (self.grid_offset_x + dx) % self.TILE_SIZE
        self.grid_offset_y = (self.grid_offset_y + dy) % self.TILE_SIZE
        self.calculate_layout()
