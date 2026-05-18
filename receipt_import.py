"""Импорт PDF-чека: извлечение текста и попытка сопоставить цены с каталогом."""
import re
import sys

from material_catalog import get_catalog_entry, get_billing_meta
from product_aliases import match_product_alias
from receipt_template_engine import detect_template, list_template_summaries, parse_with_template
from supplier_db import get_or_create_supplier, load_supplier_prices, save_supplier_prices
from supplier_prices_util import normalize_price_record, receipt_price_to_piece

_PDF_INSTALL_HINT = (
    "Для импорта PDF нужен пакет pypdf.\n\n"
    "В папке проекта выполните:\n"
    "  .venv\\Scripts\\pip install pypdf\n\n"
    "Или добавьте поставщика вручную: Поставщики → Добавить."
)


def _pdf_import_error_message():
    if getattr(sys, "frozen", False):
        return "Импорт PDF недоступен в этой сборке."
    return _PDF_INSTALL_HINT


def extract_pdf_text(path):
    errors = []

    try:
        from pypdf import PdfReader

        return _extract_with_reader(PdfReader, path), None
    except ImportError as e:
        errors.append(str(e))
    except Exception as e:
        errors.append(f"pypdf: {e}")

    try:
        from PyPDF2 import PdfReader

        return _extract_with_reader(PdfReader, path), None
    except ImportError:
        pass
    except Exception as e:
        errors.append(f"PyPDF2: {e}")

    try:
        import fitz

        doc = fitz.open(path)
        parts = [doc[i].get_text() or "" for i in range(len(doc))]
        doc.close()
        text = "\n".join(parts)
        if text.strip():
            return text, None
    except ImportError:
        pass
    except Exception as e:
        errors.append(f"pymupdf: {e}")

    if errors:
        return None, _pdf_import_error_message()
    return None, _pdf_import_error_message()


def _extract_with_reader(reader_cls, path):
    reader = reader_cls(path)
    parts = []
    for page in reader.pages:
        parts.append(page.extract_text() or "")
    return "\n".join(parts)


def _parse_price_token(s):
    s = s.replace(" ", "").replace(",", ".")
    m = re.search(r"(\d+(?:\.\d{1,2})?)", s)
    if not m:
        return None
    try:
        return float(m.group(1))
    except ValueError:
        return None


def parse_receipt_text(text):
    lines = [ln.strip() for ln in (text or "").splitlines() if ln.strip()]
    supplier_name = lines[0] if lines else "Поставщик"
    items = []

    for ln in lines[1:]:
        low = ln.lower()
        if any(w in low for w in ("итого", "total", "сумма", "ндс", "всего")):
            continue
        m = re.search(r"([\d\s]+[.,]\d{2})\s*(?:руб|₽|rur)?\s*$", ln, re.I)
        if not m:
            m = re.search(r"(\d+(?:[.,]\d{2})?)\s*(?:руб|₽)?\s*$", ln, re.I)
        if not m:
            continue
        price = _parse_price_token(m.group(1))
        if price is None or price <= 0:
            continue
        name_part = ln[: m.start()].strip(" -:\t")
        if len(name_part) < 2:
            continue
        items.append({"raw_name": name_part, "unit_price": price})

    return {"supplier_name": supplier_name, "items": items}


def _match_item_key(raw_name):
    hit = match_product_alias(raw_name)
    return hit["item_key"] if hit else None


def _match_row_from_alias(raw_name):
    """Полная строка для импорта: item_key + единицы из чека."""
    return match_product_alias(raw_name)


def _price_row_from_receipt(item_key, product_name, receipt_price, receipt_unit=None, units_per_pack=None):
    billing = get_billing_meta(item_key)
    ru = receipt_unit or billing.get("receipt_unit", "piece")
    upp = units_per_pack if units_per_pack is not None else billing.get("units_per_pack", 1)
    cost = receipt_price_to_piece(receipt_price, ru, upp)
    return normalize_price_record(
        {
            "product_name": product_name,
            "unit_price_cost": cost,
            "receipt_unit": "piece",
            "units_per_pack": upp,
        }
    )


def apply_parsed_receipt(parsed, merge=True, template_mapped=None):
    supplier = get_or_create_supplier(parsed["supplier_name"])
    existing = load_supplier_prices(supplier.id) if merge else {}

    matched = []
    unmatched = []

    rows = template_mapped if template_mapped is not None else parsed["items"]
    for row in rows:
        item_key = row.get("item_key") if template_mapped is not None else None
        alias = None
        if item_key is None:
            alias = _match_row_from_alias(row["raw_name"])
            if alias:
                item_key = alias["item_key"]
        if item_key is None:
            item_key = _match_item_key(row["raw_name"])
        if item_key:
            entry = get_catalog_entry(item_key)
            product_name = row.get("product_name") or (alias or {}).get("product_name") or row["raw_name"]
            receipt_price = row.get("unit_price_receipt", row.get("unit_price", 0))
            rec = _price_row_from_receipt(
                item_key,
                product_name,
                receipt_price,
                receipt_unit=row.get("receipt_unit") or (alias or {}).get("receipt_unit"),
                units_per_pack=row.get("units_per_pack") if row.get("units_per_pack") is not None else (alias or {}).get("units_per_pack"),
            )
            if merge and item_key in existing and not rec["product_name"]:
                rec["product_name"] = existing[item_key].get("product_name", "")
            existing[item_key] = rec
            matched.append(
                {
                    **row,
                    "item_key": item_key,
                    "catalog_name": entry["name"] if entry else item_key,
                    "unit_price_cost": rec["unit_price_cost"],
                    "unit_price_client": rec["unit_price_client"],
                }
            )
        else:
            unmatched.append(row)

    save_supplier_prices(supplier.id, existing)
    return {
        "supplier": supplier,
        "matched": matched,
        "unmatched": unmatched,
    }


def parse_receipt_text_smart(text):
    tpl, score = detect_template(text)
    if tpl:
        parsed = parse_with_template(text, tpl)
        return parsed, {
            "template_id": tpl.get("id"),
            "template_name": tpl.get("name"),
            "score": score,
        }
    return parse_receipt_text(text), None


def import_receipt_pdf(path, merge=True):
    text, err = extract_pdf_text(path)
    if err:
        return None, err
    parsed, tpl_info = parse_receipt_text_smart(text)
    if not parsed.get("items"):
        n_templates = len(list_template_summaries())
        hint = (
            f" Загружено шаблонов: {n_templates}. "
            "Добавьте JSON в папку receipt_templates/ под формат вашего чека."
            if n_templates == 0
            else " Шаблон не подошёл — уточните detect/mappings в JSON или добавьте новый."
        )
        return None, "Не удалось найти позиции с ценами в PDF." + hint

    template_mapped = parsed.get("mapped_items") if tpl_info else None
    result = apply_parsed_receipt(parsed, merge=merge, template_mapped=template_mapped)
    result["raw_text_preview"] = (text or "")[:2000]
    result["parser"] = tpl_info or {"mode": "generic"}
    return result, None
