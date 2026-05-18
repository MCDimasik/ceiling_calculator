"""Расчёт стоимости проекта по ценам поставщика (для клиента)."""

from project_materials import aggregate_project_totals
from supplier_db import prices_by_calc_match_key
from supplier_prices_util import qty_to_bill_units, unit_price_for_billing, bills_by_pack


def _line_amount(qty_pieces, piece_unit_price, receipt_unit, units_per_pack):
    bill_qty, bill_unit = qty_to_bill_units(qty_pieces, receipt_unit, units_per_pack)
    unit_bill = unit_price_for_billing(piece_unit_price, receipt_unit, units_per_pack)
    return bill_qty, bill_unit, unit_bill, bill_qty * unit_bill


def calculate_project_cost(project, supplier_id):
    """
    Возвращает dict:
      area_m2, perimeter_m,
      lines: [{name, qty, bill_qty, bill_unit, unit_price, line_total, has_price, ...}],
      total, total_cost, benefit, missing_count

    Цены — для клиента (unit_price_client). Упаковки (20 шт) — округление пачек вверх.
    """
    totals, area_m2, perimeter_m = aggregate_project_totals(project)
    client_map = prices_by_calc_match_key(supplier_id, for_client=True)
    cost_map = prices_by_calc_match_key(supplier_id, for_client=False)

    lines = []
    total_client = 0.0
    total_cost = 0.0
    missing = 0

    for key in sorted(totals.keys()):
        qty_pieces = int(totals[key])
        client_info = client_map.get(key)
        cost_info = cost_map.get(key)

        has_client = client_info and float(client_info["unit_price"]) > 0
        has_cost = cost_info and float(cost_info["unit_price"]) > 0

        receipt_unit = "piece"
        units_per_pack = 1.0
        if has_client:
            receipt_unit = client_info.get("receipt_unit") or "piece"
            units_per_pack = float(client_info.get("units_per_pack") or 1)

        if has_client:
            piece_unit = float(client_info["unit_price"])
            bill_qty, bill_unit, unit_bill, line_total = _line_amount(
                qty_pieces, piece_unit, receipt_unit, units_per_pack
            )
            total_client += line_total
            name = client_info["product_name"]
        else:
            missing += 1
            bill_qty, bill_unit, unit_bill, line_total = qty_pieces, "шт", None, None
            name = key

        if has_cost:
            cost_unit = float(cost_info["unit_price"])
            ru = cost_info.get("receipt_unit") or receipt_unit
            upp = float(cost_info.get("units_per_pack") or units_per_pack)
            _, _, _, cost_line = _line_amount(qty_pieces, cost_unit, ru, upp)
            total_cost += cost_line

        lines.append(
            {
                "name": name,
                "calc_key": key,
                "qty": qty_pieces,
                "bill_qty": bill_qty,
                "bill_unit": bill_unit,
                "by_pack": bills_by_pack(receipt_unit, units_per_pack),
                "units_per_pack": int(units_per_pack) if units_per_pack > 1 else 1,
                "unit_price": unit_bill if has_client else None,
                "line_total": line_total,
                "has_price": has_client,
            }
        )

    benefit = total_client - total_cost if total_cost > 0 else None

    return {
        "area_m2": area_m2,
        "perimeter_m": perimeter_m,
        "lines": lines,
        "total": total_client,
        "total_cost": total_cost,
        "benefit": benefit,
        "missing_count": missing,
    }
