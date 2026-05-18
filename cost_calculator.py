"""Расчёт стоимости проекта по ценам поставщика (для клиента)."""

from project_materials import aggregate_project_totals

from supplier_db import prices_by_calc_match_key





def calculate_project_cost(project, supplier_id):

    """

    Возвращает dict:

      area_m2, perimeter_m,

      lines: [{name, qty, unit_price, line_total, has_price}],

      total, missing_count

    Цены — для клиента (unit_price_client).

    """

    totals, area_m2, perimeter_m = aggregate_project_totals(project)

    price_map = prices_by_calc_match_key(supplier_id, for_client=True)



    lines = []

    total = 0.0

    missing = 0



    for key in sorted(totals.keys()):

        qty = int(totals[key])

        pinfo = price_map.get(key)

        if pinfo and pinfo["unit_price"] > 0:

            unit = float(pinfo["unit_price"])

            line_total = unit * qty

            total += line_total

            lines.append(

                {

                    "name": pinfo["product_name"],

                    "calc_key": key,

                    "qty": qty,

                    "unit_price": unit,

                    "line_total": line_total,

                    "has_price": True,

                }

            )

        else:

            missing += 1

            lines.append(

                {

                    "name": key,

                    "calc_key": key,

                    "qty": qty,

                    "unit_price": None,

                    "line_total": None,

                    "has_price": False,

                }

            )



    return {

        "area_m2": area_m2,

        "perimeter_m": perimeter_m,

        "lines": lines,

        "total": total,

        "missing_count": missing,

    }


