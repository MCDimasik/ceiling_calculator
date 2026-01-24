# database.py
import sqlite3
import json
from datetime import datetime
from models import Project, Room  # Предполагается, что модели определены так же

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
            walls_json TEXT NOT NULL, -- Хранение стен как JSON
            last_position_json TEXT,  -- Опционально: последняя позиция в редакторе
            FOREIGN KEY (project_id) REFERENCES projects (id)
        )
    """)
    conn.commit()
    conn.close()


def save_project(project):
    """Сохраняет проект (и его комнаты) в базу данных."""
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()

    try:
        # Вставка или обновление проекта
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

        # Удаление существующих комнат проекта перед обновлением (для простоты)
        cursor.execute("DELETE FROM rooms WHERE project_id = ?", (project.id,))

        # Вставка комнат
        for room in project.rooms:
            walls_json_str = json.dumps(room.walls)
            last_pos_json_str = json.dumps(room.last_position) if hasattr(
                room, 'last_position') else None
            cursor.execute("""
                INSERT INTO rooms (project_id, name, created_at, walls_json, last_position_json)
                VALUES (?, ?, ?, ?, ?)
            """, (project.id, room.name, room.created_at.isoformat(), walls_json_str, last_pos_json_str))

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
        # Загрузка проекта
        cursor.execute(
            "SELECT id, name, created_at FROM projects WHERE id = ?", (project_id,))
        row = cursor.fetchone()
        if row is None:
            return None

        project = Project(row[1])  # name
        project.id = row[0]       # id
        project.created_at = datetime.fromisoformat(row[2])  # created_at

        # Загрузка комнат проекта
        cursor.execute(
            "SELECT id, name, created_at, walls_json, last_position_json FROM rooms WHERE project_id = ?", (project_id,))
        for room_row in cursor.fetchall():
            room = Room(room_row[1])  # name
            room.id = room_row[0]    # id
            room.created_at = datetime.fromisoformat(room_row[2])  # created_at
            room.walls = json.loads(room_row[3])  # walls_json
            if room_row[4]:  # last_position_json
                room.last_position = json.loads(room_row[4])

            project.rooms.append(room)

        print(f"Проект '{project.name}' успешно загружен из базы данных.")
        return project

    except sqlite3.Error as e:
        print(f"Ошибка при загрузке проекта из базы данных: {e}")
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
            proj = Project(row[1])  # name
            proj.id = row[0]       # id
            proj.created_at = datetime.fromisoformat(row[2])  # created_at
            projects.append(proj)
        return projects
    except sqlite3.Error as e:
        print(f"Ошибка при загрузке списка проектов: {e}")
        return []
    finally:
        conn.close()


def update_room(room):
    """Обновляет конкретную комнату в базе данных."""
    # Предполагается, что у комнаты уже есть project_id
    # Нужно найти project_id, к которому принадлежит комната
    # Это может быть сложно, если у нас есть только объект Room
    # Лучше передавать project_id явно или обновлять через проект
    # Реализация зависит от того, как ты будешь использовать эту функцию
    # В текущем контексте, возможно, проще сохранять весь проект целиком
    pass  # Пока не используется напрямую, save_project обновляет комнаты

# --- Добавим функции для удаления ---


def delete_project(project_id):
    """Удаляет проект и все его комнаты из базы данных."""
    conn = sqlite3.connect('ceiling_calculator.db')
    cursor = conn.cursor()
    try:
        # Удаляем комнаты проекта (каскадное удаление через внешний ключ)
        cursor.execute("DELETE FROM rooms WHERE project_id = ?", (project_id,))
        # Удаляем сам проект
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
    conn = sqlite3.connect('ceiling_calculator.db')
    cursor = conn.cursor()
    try:
        cursor.execute("DELETE FROM rooms WHERE id = ? AND project_id = ?", (room_id, project_id))
        conn.commit()
        if cursor.rowcount > 0:
            print(f"Комната с ID {room_id} из проекта с ID {project_id} успешно удалена.")
            return True
        else:
            print(f"Комната с ID {room_id} не найдена в проекте с ID {project_id}.")
            return False
    except sqlite3.Error as e:
        print(f"Ошибка при удалении комнаты: {e}")
        conn.rollback()
        return False
    finally:
        conn.close()