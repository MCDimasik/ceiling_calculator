import os
import mimetypes
from pathlib import Path


def is_binary_file(file_path, sample_size=1024):
    """Проверяет, является ли файл бинарным."""
    try:
        with open(file_path, 'rb') as f:
            sample = f.read(sample_size)
            if b'\0' in sample:  # Простая эвристика: если есть нулевые байты — скорее всего бинарник
                return True
            # Дополнительно: попробуем декодировать как UTF-8
            try:
                sample.decode('utf-8')
                return False
            except UnicodeDecodeError:
                return True
    except Exception:
        return True  # Если не удалось прочитать — считаем бинарным


def should_skip_dir(dir_name):
    """Возвращает True, если директорию нужно пропустить."""
    skip_dirs = {
        '.git', '__pycache__', 'node_modules', 'venv', 'env', '.venv',
        '.idea', '.vscode', '.DS_Store', 'dist', 'build', 'coverage',
        '.pytest_cache', '.mypy_cache', '.tox', '.eggs', '*.egg-info'
    }
    return dir_name in skip_dirs or dir_name.endswith('.egg-info')


def should_skip_file(file_name):
    """Возвращает True, если файл нужно пропустить."""
    skip_extensions = {'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.exe', '.dll', '.so', '.dylib',
                       '.zip', '.tar', '.gz', '.rar', '.pdf', '.bin', '.dat', '.log', '.lock', '.txt'}
    ext = Path(file_name).suffix.lower()
    return ext in skip_extensions


def generate_repo_summary(repo_path, output_file="repo_summary.txt"):
    repo_path = Path(repo_path).resolve()
    if not repo_path.exists():
        raise ValueError(f"Путь не существует: {repo_path}")

    with open(output_file, "w", encoding="utf-8") as out_f:
        out_f.write(f"РЕПОЗИТОРИЙ: {repo_path}\n")
        out_f.write("=" * 80 + "\n\n")

        # Сначала соберём дерево структуры
        tree_lines = []
        file_list = []

        for root, dirs, files in os.walk(repo_path):
            # Пропускаем ненужные директории
            dirs[:] = [d for d in dirs if not should_skip_dir(d)]

            level = root.replace(str(repo_path), '').count(os.sep)
            indent = '│   ' * (level - 1) + '├── ' if level > 0 else ''
            tree_lines.append(f"{indent}{os.path.basename(root)}/")

            for file in sorted(files):
                if should_skip_file(file):
                    continue
                file_path = Path(root) / file
                rel_path = file_path.relative_to(repo_path)
                file_list.append(file_path)

                file_indent = '│   ' * level + '├── '
                tree_lines.append(f"{file_indent}{file}")

        # Записываем дерево
        out_f.write("СТРУКТУРА ПРОЕКТА:\n")
        out_f.write("-" * 40 + "\n")
        for line in tree_lines:
            out_f.write(line + "\n")
        out_f.write("\n" + "=" * 80 + "\n\n")

        # Теперь записываем содержимое каждого файла
        for file_path in sorted(file_list):
            rel_path = file_path.relative_to(repo_path)
            try:
                if is_binary_file(file_path):
                    continue

                out_f.write(f"\n{'='*60}\n")
                out_f.write(f"ФАЙЛ: {rel_path}\n")
                out_f.write(f"{'='*60}\n\n")

                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    out_f.write(content)
                    if not content.endswith('\n'):
                        out_f.write('\n')

            except Exception as e:
                out_f.write(f"\n[ОШИБКА ПРИ ЧТЕНИИ ФАЙЛА: {e}]\n")

    print(f"✅ Готово! Сводка сохранена в: {output_file}")


# === ОСНОВНОЙ ЗАПУСК ===
if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Использование: python repo_to_text.py <путь_к_репозиторию> [выходной_файл.txt]")
        repo_path = input("Введите путь к репозиторию: ").strip()
    else:
        repo_path = sys.argv[1]

    output_file = sys.argv[2] if len(sys.argv) > 2 else "repo_summary.txt"

    generate_repo_summary(repo_path, output_file)
