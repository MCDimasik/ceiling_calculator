"""
Сопоставление названий из чеков поставщиков → item_key каталога.

Правила проверяются по убыванию priority (сначала более точные).
Текст нормализуется: нижний регистр, ё→е, ×/х унифицируются.
"""
import re

from material_catalog import get_catalog_entry, get_billing_meta

# priority, item_key, условия, опционально receipt_unit / units_per_pack
# all_contains — все подстроки должны быть в тексте
# any_contains — хотя бы одна
# none_contains — ни одной не должно быть
# regex — любой паттерн re.I
ALIAS_RULES = [
    # --- Армстронг: плиты ---
    {
        "priority": 120,
        "item_key": "armstrong_retail",
        "all_contains": ["ритейл"],
        "any_contains": ["армстронг", "плит"],
        "receipt_unit": "pack",
        "units_per_pack": 20,
    },
    {
        "priority": 115,
        "item_key": "armstrong_metal_perf",
        "any_contains": ["цесал", "cesal"],
        "all_contains": ["кассет"],
    },
    {
        "priority": 110,
        "item_key": "armstrong_metal_perf",
        "all_contains": ["перф"],
        "any_contains": ["плит", "кассет", "алюмин"],
    },
    {
        "priority": 100,
        "item_key": "armstrong_baikal",
        "all_contains": ["байкал"],
        "any_contains": ["армстронг", "плит"],
        "receipt_unit": "pack",
        "units_per_pack": 20,
    },
    {
        "priority": 95,
        "item_key": "armstrong_tile",
        "all_contains": ["армстронг"],
        "any_contains": ["плит", "потолочн"],
        "none_contains": ["грильято", "grilyato", "профиль", "направляющ"],
        "receipt_unit": "pack",
        "units_per_pack": 20,
    },
    # --- Свет ---
    {
        "priority": 120,
        "item_key": "light_fixture_led",
        "any_contains": ["светильник", "led", "595"],
    },
    # --- Подвесы ---
    {
        "priority": 110,
        "item_key": "susp_05",
        "regex": [r"европодвес.*500", r"500\s*мм", r"подвес.*0[,.]5", r"0[,.]5\s*м"],
    },
    {
        "priority": 100,
        "item_key": "susp_10",
        "regex": [r"подвес.*1\s*м", r"европодвес.*1000"],
        "none_contains": ["1,5", "1.5"],
    },
    {
        "priority": 100,
        "item_key": "susp_15",
        "regex": [r"подвес.*1[,.]5"],
    },
    # --- Уголок ---
    {
        "priority": 110,
        "item_key": "corner",
        "any_contains": [
            "уголок",
            "угловой",
            "пристенный кант",
            "периметральн",
        ],
        "none_contains": ["папа", "мама", "грильято"],
    },
    # --- Соединитель ---
    {
        "priority": 100,
        "item_key": "connector",
        "any_contains": ["соединитель"],
    },
    # --- Грильято: профили папа/мама (до общих направляющих) ---
    {
        "priority": 95,
        "item_key": "profile_papa_100",
        "all_contains": ["папа"],
        "any_contains": ["100", "100х100", "100x100"],
    },
    {
        "priority": 95,
        "item_key": "profile_mama_100",
        "all_contains": ["мама"],
        "any_contains": ["100", "100х100", "100x100"],
    },
    {
        "priority": 95,
        "item_key": "profile_papa_75",
        "all_contains": ["папа"],
        "any_contains": ["75", "75х75", "75x75"],
    },
    {
        "priority": 95,
        "item_key": "profile_mama_75",
        "all_contains": ["мама"],
        "any_contains": ["75", "75х75", "75x75"],
    },
    {
        "priority": 90,
        "item_key": "profile_papa_50",
        "all_contains": ["папа"],
        "any_contains": ["50", "50х50", "50x50"],
    },
    {
        "priority": 90,
        "item_key": "profile_mama_50",
        "all_contains": ["мама"],
        "any_contains": ["50", "50х50", "50x50"],
    },
    # --- Грильято: несущие / направляющие по длине ---
    {
        "priority": 85,
        "item_key": "guide_2400",
        "any_contains": ["грильято", "grilyato"],
        "regex": [r"l\s*=\s*2400", r"2400\s*мм", r"\b2400\b"],
        "none_contains": ["папа", "мама"],
    },
    {
        "priority": 84,
        "item_key": "guide_1200",
        "any_contains": ["грильято", "несущ"],
        "regex": [r"l\s*=\s*1200", r"1200\s*мм", r"\b1200\b"],
        "none_contains": ["папа", "мама", "т-профиль", "т профиль"],
    },
    {
        "priority": 83,
        "item_key": "guide_600",
        "any_contains": ["грильято", "grilyato"],
        "regex": [r"l\s*=\s*600", r"600\s*мм"],
        "none_contains": ["папа", "мама", "75х75", "100х100"],
    },
    # --- Армстронг: Т-профиль (направляющие) ---
    {
        "priority": 80,
        "item_key": "guide_3600",
        "any_contains": ["т-профиль", "т профиль", "подвесного потолка"],
        "regex": [r"3[,.]6\s*м", r"\b3600\b"],
        "none_contains": ["грильято", "папа", "мама"],
    },
    {
        "priority": 80,
        "item_key": "guide_1200",
        "any_contains": ["т-профиль", "т профиль", "подвесного потолка"],
        "regex": [r"1[,.]2\s*м", r"\b1200\b"],
        "none_contains": ["грильято", "папа", "мама", "несущ"],
    },
    {
        "priority": 80,
        "item_key": "guide_600",
        "any_contains": ["т-профиль", "т профиль", "подвесного потолка"],
        "regex": [r"0[,.]6\s*м"],
        "none_contains": ["грильято", "папа", "мама"],
    },
    # --- Заглушки (на будущее) ---
    {
        "priority": 70,
        "item_key": "stopper_100",
        "all_contains": ["заглуш"],
        "any_contains": ["100"],
    },
    {
        "priority": 70,
        "item_key": "stopper_75",
        "all_contains": ["заглуш"],
        "any_contains": ["75"],
    },
    {
        "priority": 70,
        "item_key": "stopper_50",
        "all_contains": ["заглуш"],
        "any_contains": ["50"],
    },
]


def normalize_receipt_text(text):
    t = (text or "").lower().replace("ё", "е")
    t = t.replace("×", "x").replace("х", "x")
    t = re.sub(r"\s+", " ", t)
    return t.strip()


def _rule_matches(norm_text, rule):
    for sub in rule.get("none_contains") or []:
        if sub in norm_text:
            return False
    for sub in rule.get("all_contains") or []:
        if sub not in norm_text:
            return False
    any_list = rule.get("any_contains") or []
    if any_list and not any(sub in norm_text for sub in any_list):
        return False
    regex_list = rule.get("regex") or []
    if regex_list and not any(re.search(pat, norm_text, re.I) for pat in regex_list):
        return False
    if not any_list and not rule.get("all_contains") and not regex_list:
        return False
    return True


def match_product_alias(raw_name):
    """
    Возвращает dict или None:
      item_key, product_name (из каталога), receipt_unit, units_per_pack, priority
    """
    norm = normalize_receipt_text(raw_name)
    if not norm:
        return None

    best = None
    for rule in ALIAS_RULES:
        if not _rule_matches(norm, rule):
            continue
        pr = int(rule.get("priority", 0))
        if best is None or pr > best["priority"]:
            entry = get_catalog_entry(rule["item_key"])
            billing = get_billing_meta(rule["item_key"])
            best = {
                "item_key": rule["item_key"],
                "product_name": entry["name"] if entry else rule["item_key"],
                "calc_match_key": entry["calc_match_key"] if entry else None,
                "receipt_unit": rule.get("receipt_unit") or billing.get("receipt_unit", "piece"),
                "units_per_pack": rule.get("units_per_pack", billing.get("units_per_pack", 1)),
                "priority": pr,
            }
    return best
