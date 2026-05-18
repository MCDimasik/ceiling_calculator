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


