"""Нормализация цен поставщика: закуп / клиент, упаковка → штука."""

import math

CLIENT_MARKUP_DEFAULT = 0.10


def client_from_cost(cost, markup=CLIENT_MARKUP_DEFAULT):
    c = float(cost or 0)
    if c <= 0:
        return 0.0
    return round(c * (1.0 + float(markup)), 2)


def piece_price_for_display(piece_price, receipt_unit="piece", units_per_pack=1):
    """Цена за штуку в БД → показать в форме (шт или уп)."""
    price = float(piece_price or 0)
    if price <= 0:
        return 0.0
    if (receipt_unit or "piece").lower() in ("pack", "уп", "упак"):
        n = float(units_per_pack or 1)
        if n > 1:
            return round(price * n, 2)
    return price


def bills_by_pack(receipt_unit="piece", units_per_pack=1):
    """
    Оплата упаковками: явно в чеке (уп) или в каталоге units_per_pack > 1
    (плиты Армстронг 20 шт — цена в БД за штуку, считаем целые пачки).
    """
    upp = float(units_per_pack or 1)
    if upp <= 1:
        return False
    if (receipt_unit or "piece").lower() in ("pack", "уп", "упак"):
        return True
    return True


def qty_to_bill_units(qty_pieces, receipt_unit="piece", units_per_pack=1):
    """
    Штуки из расчёта материалов → количество для оплаты.
    Для упаковки: округление вверх до целых пачек (19+5 шт → 2 уп по 20).
    """
    qty = int(qty_pieces or 0)
    if qty <= 0:
        return 0, "шт"
    if bills_by_pack(receipt_unit, units_per_pack):
        upp = max(1, int(float(units_per_pack)))
        return int(math.ceil(qty / upp)), "уп"
    return qty, "шт"


def unit_price_for_billing(piece_price, receipt_unit="piece", units_per_pack=1):
    """Цена за штуку в БД → цена за единицу оплаты (шт или уп)."""
    price = float(piece_price or 0)
    if price <= 0:
        return 0.0
    if bills_by_pack(receipt_unit, units_per_pack):
        n = float(units_per_pack or 1)
        if (receipt_unit or "piece").lower() in ("pack", "уп", "упак"):
            return piece_price_for_display(price, receipt_unit, units_per_pack)
        return round(price * n, 2)
    return price


def receipt_price_to_piece(unit_price, receipt_unit="piece", units_per_pack=1):
    """Цена из чека → цена за штуку (для каталога и расчёта)."""
    price = float(unit_price or 0)
    if price <= 0:
        return 0.0
    if (receipt_unit or "piece").lower() in ("pack", "уп", "упак"):
        n = float(units_per_pack or 1)
        if n > 1:
            return round(price / n, 4)
    return price


def normalize_price_record(data, default_markup=CLIENT_MARKUP_DEFAULT):
    """
    Приводит запись цены к виду:
      unit_price_cost, unit_price_client, product_name, receipt_unit, units_per_pack
    """
    if not data:
        data = {}
    cost = data.get("unit_price_cost")
    if cost is None:
        cost = data.get("unit_price")
    try:
        cost = float(cost or 0)
    except (TypeError, ValueError):
        cost = 0.0

    client = data.get("unit_price_client")
    if client is None:
        client = data.get("unit_price_client_auto")
    try:
        client = float(client) if client is not None and str(client).strip() != "" else None
    except (TypeError, ValueError):
        client = None

    if cost > 0 and (client is None or client <= 0):
        client = client_from_cost(cost, default_markup)

    out = {
        "product_name": (data.get("product_name") or "").strip(),
        "unit_price_cost": cost,
        "unit_price_client": float(client or 0),
        "receipt_unit": (data.get("receipt_unit") or "piece").strip() or "piece",
        "units_per_pack": float(data.get("units_per_pack") or 1),
    }
    # Совместимость со старым кодом
    out["unit_price"] = out["unit_price_client"]
    return out
