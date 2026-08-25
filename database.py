# database.py
import sqlite3
import json
import os
import shutil
from datetime import datetime
from models import Project, Room

DB_NAME = "ceiling_calculator.db"


def _app_user_data_dir():
    """
    Возвращает папку данных приложения (переживает обновления APK).
    На Android это /data/data/<package>/files.
    """
    try:
        from kivy.app import App

        app = App.get_running_app()
        if app is not None and getattr(app, "user_data_dir", None):
            return str(app.user_data_dir)
    except Exception:
        pass
    return None


def get_db_path() -> str:
    """
    Абсолютный путь к БД.
    Важно: на Android БД должна лежать в user_data_dir, иначе при обновлениях
    пакетные файлы могут перезаписываться.
    """
    udd = _app_user_data_dir()
    if udd:
        return os.path.join(udd, DB_NAME)
    # fallback для десктопа/ранних импортов
    return os.path.abspath(DB_NAME)


def _ensure_db_location():
    """
    Одноразовая миграция расположения:
    - если БД уже есть в user_data_dir — ничего не делаем
    - если БД есть в старом месте (рядом с кодом) — копируем в user_data_dir
    """
    udd = _app_user_data_dir()
    if not udd:
        return

    new_path = os.path.join(udd, DB_NAME)
    if os.path.exists(new_path):
        return

    old_path = os.path.abspath(DB_NAME)
    if os.path.exists(old_path):
        try:
            os.makedirs(udd, exist_ok=True)
            shutil.copy2(old_path, new_path)
        except Exception as e:
            print(f"Не удалось перенести базу данных в user_data_dir: {e}")


def init_db():
    """Инициализирует базу данных и создает таблицы."""
    _ensure_db_location()
    conn = sqlite3.connect(get_db_path())
    cursor = conn.cursor()

    # Таблица для проектов
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        materials_ceiling TEXT,
        materials_susp TEXT,
        materials_cell TEXT
    )
    """)

    # Таблица для комнат
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS rooms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        walls_json TEXT NOT NULL,
        last_position_json TEXT,
        grid_offset_x INTEGER DEFAULT 0,
        grid_offset_y INTEGER DEFAULT 0,
        materials_override INTEGER DEFAULT 0,
        materials_ceiling TEXT,
        materials_susp TEXT,
        materials_cell TEXT,
        FOREIGN KEY (project_id) REFERENCES projects (id)
    )
    """)

    # Миграции для старых БД
    for col_ddl in (
        "ALTER TABLE projects ADD COLUMN materials_ceiling TEXT",
        "ALTER TABLE projects ADD COLUMN materials_susp TEXT",
        "ALTER TABLE projects ADD COLUMN materials_cell TEXT",
        "ALTER TABLE rooms ADD COLUMN materials_override INTEGER DEFAULT 0",
        "ALTER TABLE rooms ADD COLUMN materials_ceiling TEXT",
        "ALTER TABLE rooms ADD COLUMN materials_susp TEXT",
        "ALTER TABLE rooms ADD COLUMN materials_cell TEXT",
        "ALTER TABLE rooms ADD COLUMN light_fixtures_json TEXT",
    ):
        try:
            cursor.execute(col_ddl)
        except sqlite3.OperationalError:
            pass

    # ← КРИТИЧНО: Миграция для старых БД
    try:
        cursor.execute(
            "ALTER TABLE rooms ADD COLUMN grid_offset_x INTEGER DEFAULT 0")
    except sqlite3.OperationalError:
        pass  # Колонка уже существует

    try:
        cursor.execute(
            "ALTER TABLE rooms ADD COLUMN grid_offset_y INTEGER DEFAULT 0")
    except sqlite3.OperationalError:
        pass  # Колонка уже существует

    conn.commit()
    conn.close()


def save_project(project):
    """Сохраняет проект (и его комнаты) в базу данных."""
    _ensure_db_location()
    conn = sqlite3.connect(get_db_path())
    cursor = conn.cursor()
    try:
        p_ceiling = getattr(project, "materials_ceiling", None)
        p_susp = getattr(project, "materials_susp", None)
        p_cell = getattr(project, "materials_cell", None)

        if project.id is None:
            cursor.execute("""
            INSERT INTO projects (name, created_at, materials_ceiling, materials_susp, materials_cell) VALUES (?, ?, ?, ?, ?)
            """, (project.name, project.created_at.isoformat(), p_ceiling, p_susp, p_cell))
            project.id = cursor.lastrowid
        else:
            cursor.execute("""
            UPDATE projects SET name = ?, created_at = ?, materials_ceiling = ?, materials_susp = ?, materials_cell = ?
            WHERE id = ?
            """, (project.name, project.created_at.isoformat(), p_ceiling, p_susp, p_cell, project.id))

        cursor.execute("DELETE FROM rooms WHERE project_id = ?", (project.id,))

        for room in project.rooms:
            walls_json_str = json.dumps(room.walls)
            last_pos_json_str = json.dumps(room.last_position) if hasattr(
                room, 'last_position') and room.last_position else None
            grid_offset_x = getattr(room, 'grid_offset_x', 0)
            grid_offset_y = getattr(room, 'grid_offset_y', 0)
            m_override = 1 if bool(getattr(room, "materials_override", False)) else 0
            m_ceiling = getattr(room, "materials_ceiling", None)
            m_susp = getattr(room, "materials_susp", None)
            m_cell = getattr(room, "materials_cell", None)
            lights_json = json.dumps(getattr(room, "light_fixtures", []) or [])
            cursor.execute("""
            INSERT INTO rooms (project_id, name, created_at, walls_json, last_position_json, grid_offset_x, grid_offset_y,
                               materials_override, materials_ceiling, materials_susp, materials_cell, light_fixtures_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (project.id, room.name, room.created_at.isoformat(), walls_json_str, last_pos_json_str, grid_offset_x, grid_offset_y,
                  m_override, m_ceiling, m_susp, m_cell, lights_json))

        conn.commit()
        print(f"Проект '{project.name}' успешно сохранен в базу данных.")
    except sqlite3.Error as e:
        print(f"Ошибка при сохранении проекта в базу данных: {e}")
        conn.rollback()
    finally:
        conn.close()


def load_project(project_id):
    """Загружает проект (и его комнаты) из базы данных по ID."""
    _ensure_db_location()
    conn = sqlite3.connect(get_db_path())
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT id, name, created_at, materials_ceiling, materials_susp, materials_cell FROM projects WHERE id = ?", (project_id,))
        row = cursor.fetchone()
        if row is None:
            return None
        project = Project(row[1])
        project.id = row[0]
        project.created_at = datetime.fromisoformat(row[2])
        project.materials_ceiling = row[3] if len(row) > 3 else None
        project.materials_susp = row[4] if len(row) > 4 else None
        project.materials_cell = row[5] if len(row) > 5 else None

        # ← КРИТИЧНО: Загружаем комнаты с всеми полями
        cursor.execute(
            "SELECT id, name, created_at, walls_json, last_position_json, grid_offset_x, grid_offset_y, materials_override, materials_ceiling, materials_susp, materials_cell, light_fixtures_json FROM rooms WHERE project_id = ?",
            (project_id,),
        )
        for room_row in cursor.fetchall():
            room = Room(room_row[1])
            room.id = room_row[0]
            room.created_at = datetime.fromisoformat(room_row[2])
            room.walls = json.loads(room_row[3])
            if room_row[4]:
                room.last_position = json.loads(room_row[4])
            room.grid_offset_x = room_row[5] if room_row[5] else 0
            room.grid_offset_y = room_row[6] if room_row[6] else 0
            room.materials_override = bool(room_row[7]) if len(room_row) > 7 else False
            room.materials_ceiling = room_row[8] if len(room_row) > 8 else None
            room.materials_susp = room_row[9] if len(room_row) > 9 else None
            room.materials_cell = room_row[10] if len(room_row) > 10 else None
            if len(room_row) > 11 and room_row[11]:
                try:
                    room.light_fixtures = json.loads(room_row[11]) or []
                except (json.JSONDecodeError, TypeError):
                    room.light_fixtures = []
            else:
                room.light_fixtures = []
            project.rooms.append(room)

        print(
            f"Проект '{project.name}' загружен. Комнат: {len(project.rooms)}")
        return project
    except sqlite3.Error as e:
        print(f"Ошибка при загрузке проекта: {e}")
        return None
    finally:
        conn.close()


def load_all_projects():
    """Загружает список всех проектов (без комнат)."""
    _ensure_db_location()
    conn = sqlite3.connect(get_db_path())
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT id, name, created_at FROM projects ORDER BY created_at DESC")
        rows = cursor.fetchall()
        projects = []
        for row in rows:
            proj = Project(row[1])
            proj.id = row[0]
            proj.created_at = datetime.fromisoformat(row[2])
            projects.append(proj)
        return projects
    except sqlite3.Error as e:
        print(f"Ошибка при загрузке списка проектов: {e}")
        return []
    finally:
        conn.close()


def update_project_materials_config(project_id: int, ceiling: str = None, susp: str = None, cell: str = None):
    """Легковесное обновление конфигурации материалов для проекта (без пересохранения всех комнат)."""
    _ensure_db_location()
    conn = sqlite3.connect(get_db_path())
    cursor = conn.cursor()
    try:
        cursor.execute(
            "UPDATE projects SET materials_ceiling = ?, materials_susp = ?, materials_cell = ? WHERE id = ?",
            (ceiling, susp, cell, project_id),
        )
        conn.commit()
        return True
    except sqlite3.Error as e:
        print(f"Ошибка при обновлении конфигурации материалов проекта: {e}")
        conn.rollback()
        return False
    finally:
        conn.close()


def update_room_materials_config(room_id: int, *, override: bool = None, ceiling: str = None, susp: str = None, cell: str = None):
    """Легковесное обновление конфигурации материалов для комнаты."""
    _ensure_db_location()
    conn = sqlite3.connect(get_db_path())
    cursor = conn.cursor()
    try:
        if override is None:
            cursor.execute(
                "UPDATE rooms SET materials_ceiling = ?, materials_susp = ?, materials_cell = ? WHERE id = ?",
                (ceiling, susp, cell, room_id),
            )
        else:
            cursor.execute(
                "UPDATE rooms SET materials_override = ?, materials_ceiling = ?, materials_susp = ?, materials_cell = ? WHERE id = ?",
                (1 if override else 0, ceiling, susp, cell, room_id),
            )
        conn.commit()
        return True
    except sqlite3.Error as e:
        print(f"Ошибка при обновлении конфигурации материалов комнаты: {e}")
        conn.rollback()
        return False
    finally:
        conn.close()


def delete_project(project_id):
    """Удаляет проект и все его комнаты из базы данных."""
    _ensure_db_location()
    conn = sqlite3.connect(get_db_path())
    cursor = conn.cursor()
    try:
        cursor.execute("DELETE FROM rooms WHERE project_id = ?", (project_id,))
        cursor.execute("DELETE FROM projects WHERE id = ?", (project_id,))
        conn.commit()
        print(f"Проект с ID {project_id} и его комнаты успешно удалены.")
        return True
    except sqlite3.Error as e:
        print(f"Ошибка при удалении проекта: {e}")
        conn.rollback()
        return False
    finally:
        conn.close()


def delete_room_from_project(project_id, room_id):
    """Удаляет комнату из базы данных, связанной с проектом."""
    _ensure_db_location()
    conn = sqlite3.connect(get_db_path())
    cursor = conn.cursor()
    try:
        cursor.execute(
            "DELETE FROM rooms WHERE id = ? AND project_id = ?", (room_id, project_id))
        conn.commit()
        if cursor.rowcount > 0:
            print(
                f"Комната с ID {room_id} из проекта с ID {project_id} успешно удалена.")
            return True
        else:
            print(
                f"Комната с ID {room_id} не найдена в проекте с ID {project_id}.")
            return False
    except sqlite3.Error as e:
        print(f"Ошибка при удалении комнаты: {e}")
        conn.rollback()
        return False
    finally:
        conn.close()
