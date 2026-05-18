"""
Шаблоны разбора чеков (JSON в папке receipt_templates/).

Как добавить новый тип чека:
1. Положите образец PDF в receipt_templates/samples/ (для себя, в git по желанию).
2. Создайте receipt_templates/имя_поставщика.json по образцу _example.template.json.
3. В detect — фразы из шапки чека (ИНН, название, «Счёт на оплату»).
4. В mappings — что в строке чека соответствует какой позиции каталога (item_key).

При импорте: сначала ищется подходящий шаблон, иначе — общий эвристический разбор.
"""
import json
import os
import re
from pathlib import Path

from material_catalog import get_catalog_entry, get_billing_meta
from product_aliases import match_product_alias
from supplier_prices_util import receipt_price_to_piece

_TEMPLATES_DIR = Path(__file__).resolve().parent / "receipt_templates"
_CACHE = None


def templates_dir():
    return _TEMPLATES_DIR


def load_templates(force_reload=False):
    global _CACHE
    if _CACHE is not None and not force_reload:
        return _CACHE

    templates = []
    if not _TEMPLATES_DIR.is_dir():
        _CACHE = []
        return _CACHE

    for path in sorted(_TEMPLATES_DIR.glob("*.json")):
        if path.name.startswith("_"):
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and data.get("id"):
                data["_path"] = str(path)
                templates.append(data)
        except (json.JSONDecodeError, OSError) as e:
            print(f"Шаблон чека не загружен {path.name}: {e}")

    _CACHE = templates
    return _CACHE


def reload_templates():
    return load_templates(force_reload=True)


def _normalize_text(text):
    return (text or "").replace("\r", "\n")


def _lines(text):
    return [ln.strip() for ln in _normalize_text(text).splitlines() if ln.strip()]


def _score_template(text, tpl):
    detect = tpl.get("detect") or {}
    score = 0
    text_low = text.lower()
    lines = _lines(text)

    for phrase in detect.get("any_contains") or []:
        if phrase.lower() in text_low:
            score += int(detect.get("weight_contains", 2))

    for phrase in detect.get("all_contains") or []:
        if phrase.lower() in text_low:
            score += int(detect.get("weight_all", 3))
        else:
            score = 0
            break

    for pattern in detect.get("regex") or []:
        if re.search(pattern, text, re.I | re.M):
            score += int(detect.get("weight_regex", 2))

    min_lines = int(detect.get("min_lines", 0))
    if len(lines) < min_lines:
        score = 0

    return score


def detect_template(text):
    """Возвращает (template_dict | None, score)."""
    best = None
    best_score = 0
    for tpl in load_templates():
        s = _score_template(text, tpl)
        min_score = int((tpl.get("detect") or {}).get("min_score", 2))
        if s >= min_score and s > best_score:
            best_score = s
            best = tpl
    return best, best_score


def _parse_price(s):
    if s is None:
        return None
    s = str(s).replace(" ", "").replace(",", ".")
    m = re.search(r"(\d+(?:\.\d{1,2})?)", s)
    if not m:
        return None
    try:
        return float(m.group(1))
    except ValueError:
        return None


def _should_skip_line(line, tpl):
    low = line.lower()
    for w in (tpl.get("skip_lines") or {}).get("contains") or []:
        if w.lower() in low:
            return True
    for pattern in (tpl.get("skip_lines") or {}).get("regex") or []:
        if re.search(pattern, line, re.I):
            return True
    return False


def _extract_supplier_name(lines, tpl):
    sup = tpl.get("supplier") or {}
    if sup.get("fixed_name"):
        return sup["fixed_name"].strip()

    idx = int(sup.get("line_index", 0))
    if lines and 0 <= idx < len(lines):
        candidate = lines[idx]
        pattern = sup.get("from_regex")
        if pattern:
            m = re.search(pattern, candidate, re.I)
            if m:
                return (m.group(1) if m.lastindex else m.group(0)).strip()
        return candidate.strip()

    return lines[0] if lines else "Поставщик"


def _parse_lines_with_template(lines, tpl):
    items = []
    patterns = tpl.get("line_patterns") or []
    use_qty_as_price = bool(tpl.get("use_line_qty_as_unit_price"))

    for ln in lines:
        if _should_skip_line(ln, tpl):
            continue
        matched = False
        for pat in patterns:
            regex = pat.get("regex")
            if not regex:
                continue
            m = re.search(regex, ln, re.I)
            if not m:
                continue
            gd = m.groupdict()
            name = (gd.get("name") or "").strip()
            if not name and pat.get("name_group"):
                name = (m.group(pat["name_group"]) or "").strip()
            price_raw = gd.get("price") or gd.get("sum") or gd.get("amount")
            if price_raw is None and pat.get("price_group"):
                try:
                    price_raw = m.group(pat["price_group"])
                except IndexError:
                    price_raw = None
            qty_raw = gd.get("qty")
            unit_price = _parse_price(price_raw)
            if unit_price is None and qty_raw and use_qty_as_price:
                unit_price = _parse_price(qty_raw)
            if unit_price is None or unit_price <= 0:
                continue
            if len(name) < 2:
                continue
            items.append({"raw_name": name, "unit_price": unit_price, "source_line": ln})
            matched = True
            break

        if not matched and tpl.get("fallback_trailing_price", True):
            m = re.search(r"([\d\s]+[.,]\d{2})\s*(?:руб|₽|rur)?\s*$", ln, re.I)
            if not m:
                m = re.search(r"(\d+(?:[.,]\d{2})?)\s*(?:руб|₽)?\s*$", ln, re.I)
            if m:
                price = _parse_price(m.group(1))
                name_part = ln[: m.start()].strip(" -:\t")
                if price and price > 0 and len(name_part) >= 2:
                    items.append({"raw_name": name_part, "unit_price": price, "source_line": ln})

    return items


def _mapping_match(raw_name, mappings):
    hit = match_product_alias(raw_name)
    if hit:
        return {
            "item_key": hit["item_key"],
            "product_name": hit["product_name"],
        }
    raw_low = raw_name.lower()
    for rule in mappings:
        keys = rule.get("match_contains") or []
        if keys and any(k.lower() in raw_low for k in keys):
            return rule
        for pattern in rule.get("match_regex") or []:
            if re.search(pattern, raw_name, re.I):
                return rule
    return None


def map_items_with_template(items, tpl):
    mappings = tpl.get("mappings") or []
    mapped = []
    for row in items:
        rule = _mapping_match(row["raw_name"], mappings)
        if rule and rule.get("item_key"):
            entry = get_catalog_entry(rule["item_key"])
            mapped.append(
                {
                    **row,
                    "item_key": rule["item_key"],
                    "product_name": rule.get("product_name") or row["raw_name"],
                    "catalog_name": entry["name"] if entry else rule["item_key"],
                }
            )
        else:
            mapped.append({**row, "item_key": None})
    return mapped


def _saturn_article_entries(tpl):
    """article_map + article_config → список {code, item_key, receipt_unit, units_per_pack}."""
    skip = set(tpl.get("skip_articles") or [])
    config = tpl.get("article_config") or {}
    legacy = tpl.get("article_map") or {}
    codes = set(legacy.keys()) | set(config.keys())
    out = []
    for code in sorted(codes):
        if code in skip:
            continue
        cfg = dict(config.get(code) or {})
        if not cfg.get("item_key") and code in legacy:
            cfg["item_key"] = legacy[code]
        if not cfg.get("item_key"):
            continue
        out.append(
            {
                "code": code,
                "item_key": cfg["item_key"],
                "receipt_unit": cfg.get("receipt_unit", "piece"),
                "units_per_pack": cfg.get("units_per_pack"),
            }
        )
    return out


def _parse_saturn_v1(text, tpl):
    """
    Счёт ООО «Сатурн»: артикулы Сат-XXXXXX, цена — число перед суммой строки.
    Работает даже при «битой» кириллице в PDF (шрифты без ToUnicode).
    """
    items = []
    mapped = []

    for art in _saturn_article_entries(tpl):
        art_code = art["code"]
        item_key = art["item_key"]
        m = re.search(
            rf"-{re.escape(art_code)}[\s\S]*?"
            r"(\d+)\s+\S+[\s\n]*(\d+(?:[.,]\d+)?)\s+(\d+(?:[.,]\d+)?)",
            text,
        )
        if not m:
            continue
        qty, unit_price_raw, _sum_raw = m.groups()
        receipt_price = _parse_price(unit_price_raw)
        if not receipt_price or receipt_price <= 0:
            continue
        billing = get_billing_meta(item_key)
        receipt_unit = art.get("receipt_unit") or billing.get("receipt_unit", "piece")
        units_per_pack = art.get("units_per_pack")
        if units_per_pack is None:
            units_per_pack = billing.get("units_per_pack", 1)
        unit_piece = receipt_price_to_piece(receipt_price, receipt_unit, units_per_pack)
        entry = get_catalog_entry(item_key)
        raw_name = f"Сат-{art_code}"
        row = {
            "raw_name": raw_name,
            "unit_price": unit_piece,
            "unit_price_receipt": receipt_price,
            "receipt_unit": receipt_unit,
            "units_per_pack": units_per_pack,
            "qty": int(qty),
            "article": art_code,
            "source_line": raw_name,
        }
        items.append(row)
        mapped.append(
            {
                **row,
                "item_key": item_key,
                "product_name": entry["name"] if entry else raw_name,
                "catalog_name": entry["name"] if entry else item_key,
            }
        )

    supplier_name = (tpl.get("supplier") or {}).get("fixed_name") or "Сатурн"
    return {
        "supplier_name": supplier_name,
        "items": items,
        "mapped_items": mapped,
        "template_id": tpl.get("id"),
        "template_name": tpl.get("name"),
    }


_CUSTOM_PARSERS = {
    "saturn_v1": _parse_saturn_v1,
}


def parse_with_template(text, tpl):
    parser_id = tpl.get("custom_parser")
    if parser_id and parser_id in _CUSTOM_PARSERS:
        return _CUSTOM_PARSERS[parser_id](text, tpl)

    lines = _lines(text)
    start = int((tpl.get("items") or {}).get("start_line_index", 1))
    if start > 0:
        lines = lines[start:]

    supplier_name = _extract_supplier_name(_lines(text), tpl)
    items = _parse_lines_with_template(lines, tpl)
    mapped = map_items_with_template(items, tpl)

    return {
        "supplier_name": supplier_name,
        "items": items,
        "mapped_items": mapped,
        "template_id": tpl.get("id"),
        "template_name": tpl.get("name"),
    }


def list_template_summaries():
    out = []
    for tpl in load_templates():
        out.append(
            {
                "id": tpl.get("id"),
                "name": tpl.get("name"),
                "file": os.path.basename(tpl.get("_path", "")),
            }
        )
    return out
