import math


def ceil_div(value, divisor):
    if divisor == 0:
        return 0
    return math.ceil(value / divisor)


def room_perimeter_cm(walls):
    if not walls:
        return 0.0
    perimeter = 0.0
    for x1, y1, x2, y2 in walls:
        perimeter += math.hypot(x2 - x1, y2 - y1)
    return perimeter


def room_length_for_rows_cm(walls):
    """Берем максимальный размер комнаты как рабочую длину ряда."""
    if not walls:
        return 0.0
    xs = []
    ys = []
    for x1, y1, x2, y2 in walls:
        xs.extend([x1, x2])
        ys.extend([y1, y2])
    return max(max(xs) - min(xs), max(ys) - min(ys))


def room_dims_cm(walls):
    if not walls:
        return 0.0, 0.0
    xs = []
    ys = []
    for x1, y1, x2, y2 in walls:
        xs.extend([x1, x2])
        ys.extend([y1, y2])
    return max(xs) - min(xs), max(ys) - min(ys)


def _ordered_points_from_walls(walls):
    if not walls:
        return []
    points = [(walls[0][0], walls[0][1])]
    for x1, y1, x2, y2 in walls:
        if not points or points[-1] != (x1, y1):
            points.append((x1, y1))
        points.append((x2, y2))
    if len(points) > 1 and points[0] == points[-1]:
        points.pop()
    return points


def room_area_m2(walls):
    points = _ordered_points_from_walls(walls)
    if len(points) < 3:
        return 0.0
    s = 0.0
    n = len(points)
    for i in range(n):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    area_cm2 = abs(s) * 0.5
    return area_cm2 / 10000.0


def _segment_lengths_cm(points):
    lengths = []
    n = len(points)
    for i in range(n):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % n]
        lengths.append(math.hypot(x2 - x1, y2 - y1))
    return lengths


def _is_rectangle(points, eps=1e-3):
    if len(points) != 4:
        return False
    lengths = _segment_lengths_cm(points)
    if min(lengths) <= eps:
        return False
    a, b, c, d = lengths
    return abs(a - c) <= eps and abs(b - d) <= eps


def grilyato_cassette_count(walls, fallback_count):
    """
    Закупка кассет: max(ceil(S / 0.36), fallback).
    ceil(S/0.36) — как у поставщиков (10×10 м → 278).
    """
    area = room_area_m2(walls)
    from_area = math.ceil(area / 0.36) if area > 0 else 0
    return max(from_area, int(fallback_count or 0))


def auto_rows_for_armstrong(walls):
    w, h = room_dims_cm(walls)
    short_side = min(w, h) if w > 0 and h > 0 else max(w, h)
    if short_side <= 0:
        return 1, 1
    rows_3600 = max(1, math.ceil(short_side / 120.0))
    rows_2400 = rows_3600
    return rows_3600, rows_2400


def auto_rows_for_grilyato_classic(walls):
    w, h = room_dims_cm(walls)
    short_side = min(w, h) if w > 0 and h > 0 else max(w, h)
    if short_side <= 0:
        return 1, 1
    rows_3600 = max(1, math.ceil(short_side / 120.0))
    rows_2400 = max(1, math.ceil(short_side / 60.0))
    return rows_3600, rows_2400


def calc_armstrong(walls, cassette_count, rows_3600, rows_2400):
    perimeter_cm = room_perimeter_cm(walls)
    area_m2 = room_area_m2(walls)

    # Армстронг (по ТЗ):
    # Направляющая 3,6 = ceil((S * 0,84) / 3,6)
    # Направляющая 1,2 = ceil((S * 1,68) / 1,2)
    # Направляющая 0,6 = ceil((S * 0,85) / 0,6)
    # Подвес = (направляющая 3,6) * 4
    # Уголок = ceil(P / 3)
    corner_3m = ceil_div(perimeter_cm, 300)
    guide_3600 = math.ceil((area_m2 * 0.84) / 3.6)
    guide_1200 = math.ceil((area_m2 * 1.68) / 1.2)
    guide_600 = math.ceil((area_m2 * 0.85) / 0.6)
    suspensions = guide_3600 * 4

    # Порядок вывода — как в UI
    return {
        "Плиты/кассеты": cassette_count,
        "Направляющая 3600": guide_3600,
        "Направляющая 1200": guide_1200,
        "Направляющая 600": guide_600,
        "Подвес": suspensions,
        "Уголок": corner_3m,
    }

def _grilyato_profile_factor(cell_size: str) -> int:
    # По ТЗ:
    # 50x50 -> *11
    # 75x75 -> *7
    # 100x100 -> *5
    if cell_size == "75x75":
        return 7
    if cell_size == "50x50":
        return 11
    return 5


def calc_grilyato_gl(walls, cassette_count, rows_3600, rows_2400, cell_size):
    perimeter_cm = room_perimeter_cm(walls)
    area_m2 = room_area_m2(walls)

    cassette_count = grilyato_cassette_count(walls, cassette_count)
    k = _grilyato_profile_factor(cell_size)

    # Направляющие и подвесы — как Армстронг
    corner_3m = ceil_div(perimeter_cm, 300)
    guide_3600 = math.ceil((area_m2 * 0.84) / 3.6)
    guide_1200 = math.ceil((area_m2 * 1.68) / 1.2)
    guide_600 = math.ceil((area_m2 * 0.85) / 0.6)
    suspensions = guide_3600 * 4

    # Решётка: папа/мама = кассеты × k; L-профиль/заглушки = кассеты × 4
    profile = cassette_count * k
    stoppers = cassette_count * 4

    return {
        "Профиль Папа": profile,
        "Профиль Мама": profile,
        "Направляющая 3600": guide_3600,
        "Направляющая 1200": guide_1200,
        "Направляющая 600": guide_600,
        "Подвес": suspensions,
        "Уголок": corner_3m,
        "Заглушки": stoppers,
    }


def calc_grilyato_classic(walls, cassette_count, rows_3600, rows_2400, cell_size):
    perimeter_cm = room_perimeter_cm(walls)
    area_m2 = room_area_m2(walls)
    cassette_count = grilyato_cassette_count(walls, cassette_count)

    # Каркас как Армстронг, несущие 2400; подвесы ×3; папа/мама = кассеты × k
    corner_3m = ceil_div(perimeter_cm, 300)
    guide_2400 = math.ceil((area_m2 * 0.84) / 2.4)
    guide_1200 = math.ceil((area_m2 * 1.68) / 1.2)
    guide_600 = math.ceil((area_m2 * 0.85) / 0.6)
    k = _grilyato_profile_factor(cell_size)
    profile = cassette_count * k

    return {
        "Профиль Папа": profile,
        "Профиль Мама": profile,
        "Направляющая 2400": guide_2400,
        "Направляющая 1200": guide_1200,
        "Направляющая 600": guide_600,
        "Подвес": guide_2400 * 3,
        "Уголок": corner_3m,
        "Соединитель": guide_2400,
    }


def effective_tile_counts_after_lights(full_tiles, cut_tiles, light_count):
    """
    Светильник занимает ячейку вместо плиты: сначала вычитаем из целых, затем из резаных.
    """
    lights = max(0, int(light_count or 0))
    full = max(0, int(full_tiles or 0))
    cut = max(0, int(cut_tiles or 0))
    rem = lights
    from_full = min(rem, full)
    full -= from_full
    rem -= from_full
    cut = max(0, cut - rem)
    return full, cut


def apply_light_fixture_deductions(result, ceiling_type, cell_size, light_count):
    """Уменьшает плиты (Армстронг) или профили (Грильято) на одну ячейку на светильник."""
    if light_count <= 0:
        return result
    result = dict(result)
    if ceiling_type == "armstrong":
        key = "Плиты/кассеты"
        if key in result:
            result[key] = max(0, int(result[key]) - light_count)
    elif ceiling_type in ("grilyato_classic", "grilyato_gl"):
        k = _grilyato_profile_factor(cell_size)
        deduct = light_count * k
        for key in ("Профиль Папа", "Профиль Мама"):
            if key in result:
                result[key] = max(0, int(result[key]) - deduct)
        if ceiling_type == "grilyato_gl" and "Заглушки" in result:
            profile = int(result.get("Профиль Мама", 0))
            result["Заглушки"] = math.ceil((profile / float(k)) * 4.0)
    return result


def calculate_materials(ceiling_type, walls, cassette_count, rows_3600=None, rows_2400=None, cell_size="100x100", light_count=0):
    if rows_3600 is None or rows_2400 is None:
        if ceiling_type == "grilyato_classic":
            auto_3600, auto_2400 = auto_rows_for_grilyato_classic(walls)
        else:
            auto_3600, auto_2400 = auto_rows_for_armstrong(walls)
        if rows_3600 is None:
            rows_3600 = auto_3600
        if rows_2400 is None:
            rows_2400 = auto_2400

    if ceiling_type == "armstrong":
        result = calc_armstrong(walls, cassette_count, rows_3600, rows_2400)
    elif ceiling_type == "grilyato_gl":
        result = calc_grilyato_gl(walls, cassette_count, rows_3600, rows_2400, cell_size)
    elif ceiling_type == "grilyato_classic":
        result = calc_grilyato_classic(walls, cassette_count, rows_3600, rows_2400, cell_size)
    else:
        result = {}

    result = apply_light_fixture_deductions(result, ceiling_type, cell_size, light_count)
    if light_count > 0:
        ordered = {"Светильники": light_count}
        ordered.update(result)
        return ordered
    return result
