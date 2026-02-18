# database.py
import sqlite3
import json
from datetime import datetime
from models import Project, Room

DB_NAME = "ceiling_calculator.db"


def init_db():
    """Инициализирует базу данных и создает таблицы."""
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()

    # Таблица для проектов
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
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
        FOREIGN KEY (project_id) REFERENCES projects (id)
    )
    """)

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
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    try:
        if project.id is None:
            cursor.execute("""
            INSERT INTO projects (name, created_at) VALUES (?, ?)
            """, (project.name, project.created_at.isoformat()))
            project.id = cursor.lastrowid
        else:
            cursor.execute("""
            UPDATE projects SET name = ?, created_at = ?
            WHERE id = ?
            """, (project.name, project.created_at.isoformat(), project.id))

        cursor.execute("DELETE FROM rooms WHERE project_id = ?", (project.id,))

        for room in project.rooms:
            walls_json_str = json.dumps(room.walls)
            last_pos_json_str = json.dumps(room.last_position) if hasattr(
                room, 'last_position') and room.last_position else None
            grid_offset_x = getattr(room, 'grid_offset_x', 0)
            grid_offset_y = getattr(room, 'grid_offset_y', 0)
            cursor.execute("""
            INSERT INTO rooms (project_id, name, created_at, walls_json, last_position_json, grid_offset_x, grid_offset_y)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (project.id, room.name, room.created_at.isoformat(), walls_json_str, last_pos_json_str, grid_offset_x, grid_offset_y))

        conn.commit()
        print(f"Проект '{project.name}' успешно сохранен в базу данных.")
    except sqlite3.Error as e:
        print(f"Ошибка при сохранении проекта в базу данных: {e}")
        conn.rollback()
    finally:
        conn.close()


def load_project(project_id):
    """Загружает проект (и его комнаты) из базы данных по ID."""
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT id, name, created_at FROM projects WHERE id = ?", (project_id,))
        row = cursor.fetchone()
        if row is None:
            return None
        project = Project(row[1])
        project.id = row[0]
        project.created_at = datetime.fromisoformat(row[2])

        # ← КРИТИЧНО: Загружаем комнаты с всеми полями
        cursor.execute(
            "SELECT id, name, created_at, walls_json, last_position_json, grid_offset_x, grid_offset_y FROM rooms WHERE project_id = ?", (project_id,))
        for room_row in cursor.fetchall():
            room = Room(room_row[1])
            room.id = room_row[0]
            room.created_at = datetime.fromisoformat(room_row[2])
            room.walls = json.loads(room_row[3])
            if room_row[4]:
                room.last_position = json.loads(room_row[4])
            room.grid_offset_x = room_row[5] if room_row[5] else 0
            room.grid_offset_y = room_row[6] if room_row[6] else 0
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
    conn = sqlite3.connect(DB_NAME)
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


def delete_project(project_id):
    """Удаляет проект и все его комнаты из базы данных."""
    conn = sqlite3.connect(DB_NAME)
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
    conn = sqlite3.connect(DB_NAME)
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
