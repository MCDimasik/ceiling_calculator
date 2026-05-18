"""Суммарный расчёт количества материалов по проекту (как на экране полного расчёта)."""
from models import CeilingLayout
from materials_calculator import (
    calculate_materials,
    room_perimeter_cm,
    room_area_m2,
    grilyato_cassette_count,
)

TYPE_MAP = {"Армстронг": "armstrong", "Грильято": "grilyato_classic", "GL": "grilyato_gl"}


def room_effective_config(room, project):
    p_ceiling = getattr(project, "materials_ceiling", None) or "Армстронг"
    p_susp = getattr(project, "materials_susp", None) or "Подвес 0,5"
    p_cell = getattr(project, "materials_cell", None) or "50x50"
    if bool(getattr(room, "materials_override", False)):
        return (
            getattr(room, "materials_ceiling", None) or p_ceiling,
            getattr(room, "materials_susp", None) or p_susp,
            getattr(room, "materials_cell", None) or p_cell,
        )
    return p_ceiling, p_susp, p_cell


def normalize_result_key(name, value, ceiling, susp, cell):
    key = name
    if name == "Подвес":
        size_txt = (susp or "Подвес 0,5").replace("Подвес", "").strip()
        key = f"Подвес ({size_txt})"
    elif name in ("Профиль Папа", "Профиль Мама", "Заглушки"):
        key = f"{name} ({cell})"
    elif name == "Плиты/кассеты":
        key = f"{name} ({ceiling})"
    elif name == "Светильники":
        key = "Светильники"
    return key, int(value)


def aggregate_project_totals(project):
    """
    Возвращает (totals: dict[str,int], area_m2, perimeter_m).
  totals — ключи как в экране полного расчёта.
    """
    totals = {}
    total_area = 0.0
    total_perimeter_m = 0.0

    if not project or not getattr(project, "rooms", None):
        return totals, total_area, total_perimeter_m

    for room in project.rooms:
        if not getattr(room, "walls", None):
            continue

        ceiling, susp, cell = room_effective_config(room, project)
        calc_type = TYPE_MAP.get(ceiling, "armstrong")

        layout = CeilingLayout(room)
        layout.calculate_layout()
        cassette_count = layout.full_tiles + layout.cut_tiles
        if calc_type in ("grilyato_gl", "grilyato_classic"):
            cassette_count = grilyato_cassette_count(room.walls, cassette_count)

        light_count = len(getattr(room, "light_fixtures", []) or [])

        result = calculate_materials(
            ceiling_type=calc_type,
            walls=room.walls,
            cassette_count=cassette_count,
            rows_3600=None,
            rows_2400=None,
            cell_size=cell,
            light_count=light_count,
        )

        total_area += room_area_m2(room.walls)
        total_perimeter_m += room_perimeter_cm(room.walls) / 100.0

        for name, value in result.items():
            key, qty = normalize_result_key(name, value, ceiling, susp, cell)
            totals[key] = totals.get(key, 0) + qty

    return totals, total_area, total_perimeter_m
