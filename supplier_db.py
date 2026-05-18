"""Поставщики и цены в SQLite."""
import os
import sqlite3
from datetime import datetime

from database import DB_NAME, get_db_path, _ensure_db_location
from material_catalog import CATALOG_ENTRIES, get_catalog_entry
from supplier_prices_util import CLIENT_MARKUP_DEFAULT, normalize_price_record

_LEGACY_DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), DB_NAME)


def init_supplier_tables():
    _ensure_db_location()
    conn = sqlite3.connect(get_db_path())
    cur = conn.cursor()
    cur.execute("""
    CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
    )
    """)
    cur.execute("""
    CREATE TABLE IF NOT EXISTS supplier_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        item_key TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit_price REAL NOT NULL DEFAULT 0,
        unit_price_cost REAL NOT NULL DEFAULT 0,
        unit_price_client REAL NOT NULL DEFAULT 0,
        receipt_unit TEXT NOT NULL DEFAULT 'piece',
        units_per_pack REAL NOT NULL DEFAULT 1,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE,
        UNIQUE(supplier_id, item_key)
    )
    """)
    _migrate_supplier_prices_columns(cur)
    conn.commit()
    conn.close()
    bootstrap_suppliers_if_empty()


def _migrate_supplier_prices_columns(cur):
    cur.execute("PRAGMA table_info(supplier_prices)")
    cols = {row[1] for row in cur.fetchall()}
    alters = []
    if "unit_price_cost" not in cols:
        alters.append("ALTER TABLE supplier_prices ADD COLUMN unit_price_cost REAL NOT NULL DEFAULT 0")
    if "unit_price_client" not in cols:
        alters.append("ALTER TABLE supplier_prices ADD COLUMN unit_price_client REAL NOT NULL DEFAULT 0")
    if "receipt_unit" not in cols:
        alters.append("ALTER TABLE supplier_prices ADD COLUMN receipt_unit TEXT NOT NULL DEFAULT 'piece'")
    if "units_per_pack" not in cols:
        alters.append("ALTER TABLE supplier_prices ADD COLUMN units_per_pack REAL NOT NULL DEFAULT 1")
    for sql in alters:
        cur.execute(sql)
    if alters:
        cur.execute(
            """
            UPDATE supplier_prices
            SET unit_price_cost = CASE WHEN unit_price_cost > 0 THEN unit_price_cost ELSE unit_price END,
                unit_price_client = CASE
                    WHEN unit_price_client > 0 THEN unit_price_client
                    WHEN unit_price > 0 THEN ROUND(unit_price * ?, 2)
                    ELSE 0
                END
            WHERE unit_price > 0 OR unit_price_cost > 0
            """,
            (1.0 + CLIENT_MARKUP_DEFAULT,),
        )


def _supplier_count(conn):
    try:
        return conn.execute("SELECT COUNT(*) FROM suppliers").fetchone()[0]
    except sqlite3.OperationalError:
        return 0


def _migrate_suppliers_from_legacy_db():
    active = get_db_path()
    legacy = _LEGACY_DB_PATH
    if not os.path.isfile(legacy) or os.path.abspath(legacy) == os.path.abspath(active):
        return False
    src = sqlite3.connect(legacy)
    if _supplier_count(src) == 0:
        src.close()
        return False
    dst = sqlite3.connect(active)
    if _supplier_count(dst) > 0:
        src.close()
        dst.close()
        return False
    try:
        for row in src.execute("SELECT id, name, created_at FROM suppliers"):
            dst.execute(
                "INSERT INTO suppliers (id, name, created_at) VALUES (?, ?, ?)",
                row,
            )
        dst_cols = {r[1] for r in dst.execute("PRAGMA table_info(supplier_prices)")}
        src_cols = {r[1] for r in src.execute("PRAGMA table_info(supplier_prices)")}
        if "unit_price_cost" in dst_cols and "unit_price_cost" in src_cols:
            for row in src.execute(
                """
                SELECT supplier_id, item_key, product_name, unit_price,
                       unit_price_cost, unit_price_client, receipt_unit, units_per_pack
                FROM supplier_prices
                """
            ):
                dst.execute(
                    """
                    INSERT INTO supplier_prices (
                        supplier_id, item_key, product_name, unit_price,
                        unit_price_cost, unit_price_client, receipt_unit, units_per_pack
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    row,
                )
        else:
            for row in src.execute(
                "SELECT supplier_id, item_key, product_name, unit_price FROM supplier_prices"
            ):
                sid, ikey, pname, price = row
                price = float(price or 0)
                client = round(price * (1 + CLIENT_MARKUP_DEFAULT), 2)
                dst.execute(
                    """
                    INSERT INTO supplier_prices (
                        supplier_id, item_key, product_name, unit_price,
                        unit_price_cost, unit_price_client, receipt_unit, units_per_pack
                    )
                    VALUES (?, ?, ?, ?, ?, ?, 'piece', 1)
                    """,
                    (sid, ikey, pname, client, price, client),
                )
        dst.commit()
        return True
    finally:
        src.close()
        dst.close()


def bootstrap_suppliers_if_empty():
    conn = sqlite3.connect(get_db_path())
    try:
        if _supplier_count(conn) > 0:
            return
    finally:
        conn.close()

    if _migrate_suppliers_from_legacy_db():
        return

    from supplier_seed import seed_saturn_fallback

    seed_saturn_fallback(merge=False)


class Supplier:
    def __init__(self, name, supplier_id=None, created_at=None):
        self.id = supplier_id
        self.name = name
        self.created_at = created_at or datetime.now()


def list_suppliers():
    init_supplier_tables()
    conn = sqlite3.connect(get_db_path())
    cur = conn.cursor()
    cur.execute("SELECT id, name, created_at FROM suppliers ORDER BY name COLLATE NOCASE")
    rows = cur.fetchall()
    conn.close()
    result = []
    for r in rows:
        s = Supplier(r[1], r[0], datetime.fromisoformat(r[2]))
        result.append(s)
    return result


def load_supplier(supplier_id):
    init_supplier_tables()
    conn = sqlite3.connect(get_db_path())
    cur = conn.cursor()
    cur.execute("SELECT id, name, created_at FROM suppliers WHERE id = ?", (supplier_id,))
    row = cur.fetchone()
    conn.close()
    if not row:
        return None
    return Supplier(row[1], row[0], datetime.fromisoformat(row[2]))


def save_supplier(supplier):
    init_supplier_tables()
    conn = sqlite3.connect(get_db_path())
    cur = conn.cursor()
    if supplier.id is None:
        cur.execute(
            "INSERT INTO suppliers (name, created_at) VALUES (?, ?)",
            (supplier.name, supplier.created_at.isoformat()),
        )
        supplier.id = cur.lastrowid
    else:
        cur.execute("UPDATE suppliers SET name = ? WHERE id = ?", (supplier.name, supplier.id))
    conn.commit()
    conn.close()
    return supplier


def delete_supplier(supplier_id):
    init_supplier_tables()
    conn = sqlite3.connect(get_db_path())
    cur = conn.cursor()
    cur.execute("DELETE FROM suppliers WHERE id = ?", (supplier_id,))
    conn.commit()
    conn.close()


def load_supplier_prices(supplier_id):
    """{item_key: {product_name, unit_price_cost, unit_price_client, ...}}"""
    init_supplier_tables()
    conn = sqlite3.connect(get_db_path())
    cur = conn.cursor()
    cur.execute(
        """
        SELECT item_key, product_name, unit_price, unit_price_cost, unit_price_client,
               receipt_unit, units_per_pack
        FROM supplier_prices WHERE supplier_id = ?
        """,
        (supplier_id,),
    )
    out = {}
    for row in cur.fetchall():
        item_key = row[0]
        raw = {
            "product_name": row[1],
            "unit_price": row[2],
            "unit_price_cost": row[3],
            "unit_price_client": row[4],
            "receipt_unit": row[5] or "piece",
            "units_per_pack": row[6] or 1,
        }
        out[item_key] = normalize_price_record(raw)
    conn.close()
    return out


def save_supplier_prices(supplier_id, prices_dict):
    init_supplier_tables()
    conn = sqlite3.connect(get_db_path())
    cur = conn.cursor()
    cur.execute("DELETE FROM supplier_prices WHERE supplier_id = ?", (supplier_id,))
    for item_key, data in prices_dict.items():
        rec = normalize_price_record(data)
        cost = float(rec.get("unit_price_cost") or 0)
        if cost <= 0:
            continue
        entry = get_catalog_entry(item_key)
        product_name = rec.get("product_name") or ""
        if not product_name and entry:
            product_name = entry["name"]
        if not product_name:
            product_name = item_key
        client = float(rec.get("unit_price_client") or 0)
        cur.execute(
            """
            INSERT INTO supplier_prices (
                supplier_id, item_key, product_name, unit_price,
                unit_price_cost, unit_price_client, receipt_unit, units_per_pack
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                supplier_id,
                item_key,
                product_name,
                client,
                cost,
                client,
                rec.get("receipt_unit") or "piece",
                float(rec.get("units_per_pack") or 1),
            ),
        )
    conn.commit()
    conn.close()


def find_supplier_by_name(name):
    name = (name or "").strip().lower()
    if not name:
        return None
    for s in list_suppliers():
        if s.name.strip().lower() == name:
            return s
    return None


def get_or_create_supplier(name):
    s = find_supplier_by_name(name)
    if s:
        return s
    s = Supplier(name.strip())
    return save_supplier(s)


def prices_by_calc_match_key(supplier_id, for_client=True):
    stored = load_supplier_prices(supplier_id)
    by_match = {}
    price_field = "unit_price_client" if for_client else "unit_price_cost"
    for _cat, item_key, display_name, calc_match_key in CATALOG_ENTRIES:
        if item_key not in stored or not calc_match_key:
            continue
        rec = stored[item_key]
        unit = float(rec.get(price_field) or 0)
        if unit <= 0:
            continue
        if calc_match_key not in by_match:
            by_match[calc_match_key] = {
                "item_key": item_key,
                "product_name": rec["product_name"],
                "unit_price": unit,
                "unit_price_cost": rec.get("unit_price_cost"),
                "unit_price_client": rec.get("unit_price_client"),
            }
    return by_match
