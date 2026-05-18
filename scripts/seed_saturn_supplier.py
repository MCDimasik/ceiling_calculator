"""
Заполнить поставщика «Сатурн» ценами из типового счёта (или указанного PDF).
Запуск: python scripts/seed_saturn_supplier.py [путь_к_pdf]
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)


def _db_paths_to_seed():
    """Проектная БД и папка Kivy (как при python main.py)."""
    paths = {os.path.join(ROOT, "ceiling_calculator.db")}
    try:
        from main import CeilingCalculatorApp

        app = CeilingCalculatorApp()
        os.makedirs(app.user_data_dir, exist_ok=True)
        paths.add(os.path.join(app.user_data_dir, "ceiling_calculator.db"))
    except Exception:
        pass
    return list(paths)


def _with_db(path, fn):
    import database

    old = database.get_db_path
    database.get_db_path = lambda: path
    try:
        return fn()
    finally:
        database.get_db_path = old


from supplier_db import init_supplier_tables, get_or_create_supplier, load_supplier_prices
from receipt_import import import_receipt_pdf

DEFAULT_PDF = os.path.expanduser(
    r"~\Downloads\20260512_12-16-07 (1).pdf"
)

def seed_from_pdf(path):
    result, err = import_receipt_pdf(path, merge=False)
    if err:
        return False, err
    n = len(result["matched"])
    return True, f"Импорт из PDF: {n} позиций, поставщик «{result['supplier'].name}»"


def seed_fallback():
    from supplier_seed import seed_saturn_fallback

    s = seed_saturn_fallback(merge=False)
    return True, f"Записано позиций Сатурн (резервные цены за шт), id={s.id}"


def main():
    pdf = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PDF
    db_paths = _db_paths_to_seed()
    last_msg = ""
    for db_path in db_paths:
        print(f"DB: {db_path}")

        def work():
            init_supplier_tables()
            if os.path.isfile(pdf):
                return seed_from_pdf(pdf)
            return seed_fallback()

        ok, last_msg = _with_db(db_path, work)
        if not ok:
            print(last_msg)
            sys.exit(1)

        def show():
            s = get_or_create_supplier("Сатурн")
            prices = load_supplier_prices(s.id)
            print(f"  supplier id={s.id}, items={len(prices)}")
            for k, v in sorted(prices.items()):
                print(
                    f"    {k}: cost {v['unit_price_cost']:.2f} | "
                    f"client {v['unit_price_client']:.2f}"
                )

        _with_db(db_path, show)
    print(last_msg)


if __name__ == "__main__":
    main()
