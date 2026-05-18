"""Экспорт и импорт проектов в файл .ccproj (JSON)."""
import json
from datetime import datetime

from models import Project, Room

FORMAT_VERSION = 1
FILE_EXTENSION = ".ccproj"
MIME_TYPE = "application/vnd.ceiling-calculator.project+json"


def _room_export_dict(room: Room) -> dict:
    return {
        "name": room.name,
        "created_at": room.created_at.isoformat() if room.created_at else datetime.now().isoformat(),
        "walls": room.walls,
        "last_position": room.last_position,
        "grid_offset_x": getattr(room, "grid_offset_x", 0) or 0,
        "grid_offset_y": getattr(room, "grid_offset_y", 0) or 0,
        "light_fixtures": list(getattr(room, "light_fixtures", []) or []),
        "materials_override": bool(getattr(room, "materials_override", False)),
        "materials_ceiling": getattr(room, "materials_ceiling", None),
        "materials_susp": getattr(room, "materials_susp", None),
        "materials_cell": getattr(room, "materials_cell", None),
    }


def _room_from_export(data: dict) -> Room:
    room = Room(data["name"])
    room.id = None
    room.created_at = datetime.fromisoformat(data["created_at"])
    room.walls = data.get("walls") or []
    room.last_position = data.get("last_position")
    room.grid_offset_x = data.get("grid_offset_x", 0) or 0
    room.grid_offset_y = data.get("grid_offset_y", 0) or 0
    room.light_fixtures = data.get("light_fixtures") or []
    room.materials_override = bool(data.get("materials_override", False))
    room.materials_ceiling = data.get("materials_ceiling")
    room.materials_susp = data.get("materials_susp")
    room.materials_cell = data.get("materials_cell")
    return room


def build_export_payload(project: Project, rooms=None) -> dict:
    """rooms: None — все комнаты; иначе список объектов Room."""
    if rooms is None:
        room_list = list(project.rooms)
        export_name = project.name
    else:
        room_list = list(rooms)
        if len(room_list) == 1:
            export_name = room_list[0].name
        else:
            export_name = project.name

    return {
        "format_version": FORMAT_VERSION,
        "exported_at": datetime.now().isoformat(),
        "project": {
            "name": export_name,
            "created_at": (
                project.created_at.isoformat()
                if getattr(project, "created_at", None)
                else datetime.now().isoformat()
            ),
            "materials_ceiling": getattr(project, "materials_ceiling", None),
            "materials_susp": getattr(project, "materials_susp", None),
            "materials_cell": getattr(project, "materials_cell", None),
            "rooms": [_room_export_dict(r) for r in room_list],
        },
    }


def write_project_file(path: str, project: Project, rooms=None) -> str:
    payload = build_export_payload(project, rooms=rooms)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    return path


def read_project_file(path: str) -> Project:
    with open(path, "r", encoding="utf-8") as f:
        payload = json.load(f)

    version = payload.get("format_version", 0)
    if version > FORMAT_VERSION:
        raise ValueError("Файл создан в более новой версии приложения.")

    data = payload.get("project")
    if not data:
        raise ValueError("Некорректный файл проекта.")

    project = Project(data["name"])
    project.id = None
    project.created_at = datetime.fromisoformat(data.get("created_at", datetime.now().isoformat()))
    project.materials_ceiling = data.get("materials_ceiling")
    project.materials_susp = data.get("materials_susp")
    project.materials_cell = data.get("materials_cell")
    project.rooms = [_room_from_export(r) for r in data.get("rooms", [])]
    return project


def safe_export_basename(name: str) -> str:
    forbidden = '<>:"/\\|?*'
    cleaned = "".join(c for c in (name or "project").strip() if c not in forbidden)
    return cleaned[:80] or "project"
