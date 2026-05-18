"""

Справочник позиций для цен поставщиков.

calc_match_key — ключ строки в суммарном расчёте проекта (см. project_materials).

Разные item_key с одним calc_match_key — варианты номенклатуры (цвет, модель), количество в расчёте одно.

"""



# (category, item_key, display_name, calc_match_key)

CATALOG_ENTRIES = [

    # Плиты Армстронг (варианты — одна строка в расчёте количества)

    ("Плиты Армстронг", "armstrong_tile", "Плита Армстронг", "Плиты/кассеты (Армстронг)"),

    ("Плиты Армстронг", "armstrong_baikal", "Плита Армстронг Байкал", "Плиты/кассеты (Армстронг)"),

    ("Плиты Армстронг", "armstrong_retail", "Плита Армстронг Retail", "Плиты/кассеты (Армстронг)"),

    ("Плиты Армстронг", "armstrong_metal", "Плита Армстронг металлическая", "Плиты/кассеты (Армстронг)"),

    (

        "Плиты Армстронг",

        "armstrong_metal_perf",

        "Плита Армстронг металл. перфорированная",

        "Плиты/кассеты (Армстронг)",

    ),

    ("Плиты Армстронг", "armstrong_oregon", "Плита Армстронг Oregon", "Плиты/кассеты (Армстронг)"),

    # Кассеты грильято / GL

    ("Кассеты / решётки", "cassette_grilyato", "Кассета Грильято", "Плиты/кассеты (Грильято)"),

    ("Кассеты / решётки", "cassette_grilyato_white", "Кассета Грильято белая", "Плиты/кассеты (Грильято)"),

    ("Кассеты / решётки", "cassette_grilyato_black", "Кассета Грильято чёрная", "Плиты/кассеты (Грильято)"),

    ("Кассеты / решётки", "cassette_gl", "Кассета GL", "Плиты/кассеты (GL)"),

    ("Кассеты / решётки", "cassette_gl_white", "Кассета GL белая", "Плиты/кассеты (GL)"),

    ("Кассеты / решётки", "cassette_gl_black", "Кассета GL чёрная", "Плиты/кассеты (GL)"),

    # Светильники (кол-во с раскладки)

    ("Светильники", "light_fixture_led", "Светильник LED 600×600", "Светильники"),

    # Подвесы

    ("Подвесы", "susp_05", "Подвес 0,5 м", "Подвес (0,5)"),

    ("Подвесы", "susp_10", "Подвес 1 м", "Подвес (1)"),

    ("Подвесы", "susp_15", "Подвес 1,5 м", "Подвес (1,5)"),

    # Направляющие (армстронг / GL)

    ("Направляющие", "guide_3600", "Направляющая 3600", "Направляющая 3600"),

    ("Направляющие", "guide_1200", "Направляющая 1200", "Направляющая 1200"),

    ("Направляющие", "guide_600", "Направляющая 600", "Направляющая 600"),

    ("Направляющие", "guide_2400", "Направляющая 2400", "Направляющая 2400"),

    # Профили грильято

    ("Профили", "profile_papa_50", "Профиль Папа 50×50", "Профиль Папа (50x50)"),

    ("Профили", "profile_mama_50", "Профиль Мама 50×50", "Профиль Мама (50x50)"),

    ("Профили", "profile_papa_75", "Профиль Папа 75×75", "Профиль Папа (75x75)"),

    ("Профили", "profile_mama_75", "Профиль Мама 75×75", "Профиль Мама (75x75)"),

    ("Профили", "profile_papa_100", "Профиль Папа 100×100", "Профиль Папа (100x100)"),

    ("Профили", "profile_mama_100", "Профиль Мама 100×100", "Профиль Мама (100x100)"),

    # Прочее

    ("Прочее", "corner", "Уголок 3 м", "Уголок"),

    ("Прочее", "connector", "Соединитель", "Соединитель"),

    ("Прочее", "stopper_50", "Заглушки 50×50", "Заглушки (50x50)"),

    ("Прочее", "stopper_75", "Заглушки 75×75", "Заглушки (75x75)"),

    ("Прочее", "stopper_100", "Заглушки 100×100", "Заглушки (100x100)"),

]



# Как в чеке может быть указана цена → перевод в цену за штуку

# units_per_pack: 20 — типовая упаковка плит 600×600 (20 шт / 7,2 м²)

CATALOG_BILLING = {

    "armstrong_tile": {"receipt_unit": "piece", "units_per_pack": 20},

    "armstrong_baikal": {"receipt_unit": "piece", "units_per_pack": 20},

    "armstrong_retail": {"receipt_unit": "piece", "units_per_pack": 20},

    "armstrong_metal": {"receipt_unit": "piece", "units_per_pack": 20},

    "armstrong_metal_perf": {"receipt_unit": "piece", "units_per_pack": 20},

    "armstrong_oregon": {"receipt_unit": "piece", "units_per_pack": 20},

}



CATEGORIES_ORDER = [

    "Плиты Армстронг",

    "Кассеты / решётки",

    "Светильники",

    "Подвесы",

    "Направляющие",

    "Профили",

    "Прочее",

]





def catalog_by_category():

    out = {c: [] for c in CATEGORIES_ORDER}

    for cat, item_key, name, match in CATALOG_ENTRIES:

        out.setdefault(cat, []).append(

            {

                "item_key": item_key,

                "name": name,

                "calc_match_key": match,

                "variant_note": _variant_note(item_key, match),

            }

        )

    return out





def _variant_note(item_key, calc_match_key):

    siblings = [e for e in CATALOG_ENTRIES if e[3] == calc_match_key]

    if len(siblings) <= 1:

        return ""

    return "вариант цены, в расчёте — одна строка"


def _longest_common_prefix(names):
    if not names:
        return ""
    prefix = names[0]
    for name in names[1:]:
        while name[: len(prefix)] != prefix and prefix:
            prefix = prefix[:-1]
    return prefix.rstrip(" -–,")


def _is_redundant_generic_variant(variant, all_variants):
    """Скрываем «Плита Армстронг», если есть «Плита Армстронг Байкал» и т.п."""
    if len(all_variants) <= 1:
        return False
    base = variant["name"]
    for other in all_variants:
        if other["item_key"] == variant["item_key"]:
            continue
        if other["name"].startswith(base + " "):
            return True
    return False


def _variant_short_labels(variants):
    names = [v["name"] for v in variants]
    prefix = _longest_common_prefix(names)
    labels = {}
    for v in variants:
        name = v["name"]
        if len(variants) == 1:
            labels[v["item_key"]] = name
        elif name == prefix:
            labels[v["item_key"]] = "Общая"
        elif prefix and name.startswith(prefix):
            short = name[len(prefix) :].lstrip(" -–,")
            labels[v["item_key"]] = short or name
        else:
            labels[v["item_key"]] = name
    return labels


def _group_title(variants):
    if len(variants) == 1:
        return variants[0]["name"]
    prefix = _longest_common_prefix([v["name"] for v in variants])
    if prefix:
        return prefix
    return variants[0]["name"]


def catalog_product_groups():
    """
    Группы номенклатуры: категория + строка расчёта (calc_match_key) + варианты.
    picker_variants — без «общих» дублей, short_label — короткое имя в списке.
    """
    ordered = []
    index = {}
    for cat, item_key, name, match in CATALOG_ENTRIES:
        gk = (cat, match)
        if gk not in index:
            grp = {
                "category": cat,
                "calc_match_key": match,
                "variants": [],
            }
            index[gk] = grp
            ordered.append(grp)
        index[gk]["variants"].append({"item_key": item_key, "name": name})

    for grp in ordered:
        variants = grp["variants"]
        grp["group_title"] = _group_title(variants)
        short = _variant_short_labels(variants)
        picker = [v for v in variants if not _is_redundant_generic_variant(v, variants)]
        grp["picker_variants"] = [
            {**v, "short_label": short[v["item_key"]]} for v in picker
        ]
        grp["variants"] = [{**v, "short_label": short[v["item_key"]]} for v in variants]
    return ordered


def catalog_picker_groups(exclude_keys=None):
    """Группы для модалки «Добавить позицию» (только ещё не добавленные варианты)."""
    exclude = set(exclude_keys or [])
    out = []
    for grp in catalog_product_groups():
        picker = [v for v in grp["picker_variants"] if v["item_key"] not in exclude]
        if picker:
            out.append({**grp, "picker_variants": picker})
    return out


def supplier_price_groups(item_keys):
    """Группы для экрана цен поставщика — только добавленные item_key."""
    key_set = set(item_keys or [])
    out = []
    for grp in catalog_product_groups():
        active = [v for v in grp["variants"] if v["item_key"] in key_set]
        if active:
            out.append({**grp, "variants": active})
    return out


def catalog_item_keys():

    return [e[1] for e in CATALOG_ENTRIES]





def get_catalog_entry(item_key):

    for cat, key, name, match in CATALOG_ENTRIES:

        if key == item_key:

            billing = CATALOG_BILLING.get(key, {"receipt_unit": "piece", "units_per_pack": 1})

            return {

                "category": cat,

                "item_key": key,

                "name": name,

                "calc_match_key": match,

                "receipt_unit": billing.get("receipt_unit", "piece"),

                "units_per_pack": billing.get("units_per_pack", 1),

            }

    return None





def get_billing_meta(item_key):

    entry = get_catalog_entry(item_key)

    if not entry:

        return {"receipt_unit": "piece", "units_per_pack": 1}

    return {

        "receipt_unit": entry.get("receipt_unit", "piece"),

        "units_per_pack": entry.get("units_per_pack", 1),

    }


