"""Поделиться / импортировать проект или одну комнату."""
from database import load_project, save_project
from project_export import write_project_file, read_project_file
from platform_files import make_export_path, share_project_file, pick_project_file


def share_project_by_id(project_id):
    project = load_project(project_id) if project_id else None
    if not project:
        return False
    path = make_export_path(project.name)
    write_project_file(path, project)
    return share_project_file(path)


def share_room(project_id, room):
    project = load_project(project_id) if project_id else None
    if not project or not room:
        return False
    path = make_export_path(room.name)
    write_project_file(path, project, rooms=[room])
    return share_project_file(path, chooser_title=f"Поделиться: {room.name}")


def import_project(on_success, on_cancel=None, on_error=None):
    def _done(path):
        if not path:
            if on_cancel:
                on_cancel()
            return
        try:
            project = read_project_file(path)
            save_project(project)
            if on_success:
                on_success(project)
        except Exception as e:
            if on_error:
                on_error(str(e))

    pick_project_file(_done)
