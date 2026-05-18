"""Начальное заполнение поставщика «Сатурн» (без PDF)."""
from supplier_prices_util import normalize_price_record
from supplier_db import get_or_create_supplier, load_supplier_prices, save_supplier_prices

SATURN_FALLBACK_COST = {
    "armstrong_retail": ("Плита Армстронг Retail (Сат-147189)", 190.0),
    "guide_3600": ("Направляющая 3600", 131.0),
    "guide_1200": ("Направляющая 1200", 44.0),
    "guide_600": ("Направляющая 600", 22.68),
    "corner": ("Уголок 3 м", 89.0),
    "susp_05": ("Подвес 0,5 м", 11.0),
    "light_fixture_led": ("Светильник LED 600×600", 656.0),
}


def seed_saturn_fallback(merge=False):
    """Записать цены Сатурна за шт. merge=True — не затирать уже заданные позиции."""
    s = get_or_create_supplier("Сатурн")
    existing = load_supplier_prices(s.id) if merge else {}
    for key, (name, cost) in SATURN_FALLBACK_COST.items():
        if merge and key in existing and float(existing[key].get("unit_price_cost") or 0) > 0:
            continue
        existing[key] = normalize_price_record(
            {"product_name": name, "unit_price_cost": cost}
        )
    save_supplier_prices(s.id, existing)
    return s
