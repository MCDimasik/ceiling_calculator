"""Редактирование поставщика: только добавленные позиции + выбор из каталога."""
from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.textinput import TextInput
from kivy.uix.scrollview import ScrollView
from kivy.metrics import dp

from ui_style import (
    COLORS,
    apply_btn_style,
    wrap_button_text,
    style_title,
    style_text_input,
    bind_label_autosize,
    make_price_input,
)
from widgets.ui_components import RoundedButton, RoundedLabel
from widgets.screen_bg import make_bg_root
from widgets.ui_modal import RoundedModal
from material_catalog import catalog_by_category, get_catalog_entry, get_billing_meta, CATALOG_ENTRIES
from supplier_db import (
    load_supplier,
    save_supplier,
    save_supplier_prices,
    load_supplier_prices,
    delete_supplier,
    Supplier,
)
from supplier_prices_util import (
    normalize_price_record,
    client_from_cost,
    receipt_price_to_piece,
    piece_price_for_display,
)
import theme


def _catalog_items_flat():
    """Все позиции каталога в порядке категорий."""
    by_cat = catalog_by_category()
    out = []
    for cat, items in by_cat.items():
        for it in items:
            out.append({**it, "category": cat})
    return out


def _item_sort_key(item_key):
    order = {e[1]: i for i, e in enumerate(CATALOG_ENTRIES)}
    return order.get(item_key, 9999)


class SupplierEditScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._supplier_id = None
        self._prices = {}
        self._billing_ui = {}
        self._cost_inputs = {}
        self._client_inputs = {}
        self._name_inputs = {}

        self._root, _ = make_bg_root()
        main = BoxLayout(orientation="vertical", spacing=dp(6), padding=dp(10), size_hint=(1, 1))

        toolbar = BoxLayout(size_hint=(1, None), height=dp(72), spacing=dp(6))
        btn_back = RoundedButton(text="Назад", size_hint=(0.25, 1), font_size=dp(14))
        btn_back.corner_radius = dp(12)
        apply_btn_style(btn_back, role="secondary")
        wrap_button_text(btn_back)
        btn_back.bind(on_press=self._go_back)

        self.title = RoundedLabel(
            text="Поставщик",
            size_hint=(0.50, 1),
            color=COLORS["text"],
            halign="center",
            valign="middle",
        )
        self.title.corner_radius = dp(12)
        style_title(self.title)
        self.title.bind(size=self.title.setter("text_size"))

        btn_save = RoundedButton(text="Сохранить", size_hint=(0.25, 1), font_size=dp(14))
        btn_save.corner_radius = dp(12)
        apply_btn_style(btn_save, role="primary")
        wrap_button_text(btn_save)
        btn_save.bind(on_press=self._save)

        toolbar.add_widget(btn_back)
        toolbar.add_widget(self.title)
        toolbar.add_widget(btn_save)

        hint = Label(
            text="Только добавленные позиции. Цена за шт или за уп. Клиент: +10% кнопкой.",
            font_size=dp(11),
            color=COLORS["text"],
            halign="left",
            valign="top",
        )
        bind_label_autosize(hint, min_height_dp=32, pad_dp=8)

        name_row = BoxLayout(size_hint=(1, None), height=dp(48), spacing=dp(8))
        name_row.add_widget(Label(text="Имя:", size_hint=(0.25, 1), color=COLORS["text"], font_size=dp(14)))
        self.name_input = TextInput(multiline=False, font_size=dp(16), size_hint=(0.75, 1))
        style_text_input(self.name_input)
        name_row.add_widget(self.name_input)

        btn_add = RoundedButton(text="+ Добавить позицию", size_hint=(1, None), height=dp(48), font_size=dp(15))
        btn_add.corner_radius = dp(14)
        apply_btn_style(btn_add, role="primary")
        btn_add.bind(on_press=self._open_add_picker)

        self.form_box = BoxLayout(orientation="vertical", spacing=dp(12), size_hint_y=None)
        self.form_box.bind(minimum_height=self.form_box.setter("height"))

        scroll = ScrollView(size_hint=(1, 1))
        scroll.add_widget(self.form_box)

        btn_del = RoundedButton(text="Удалить поставщика", size_hint=(1, None), height=dp(48), font_size=dp(14))
        btn_del.corner_radius = dp(12)
        apply_btn_style(btn_del, role="danger")
        btn_del.bind(on_press=self._confirm_delete)

        main.add_widget(toolbar)
        main.add_widget(hint)
        main.add_widget(name_row)
        main.add_widget(btn_add)
        main.add_widget(scroll)
        main.add_widget(btn_del)

        self._root.add_widget(main)
        self.add_widget(self._root)

    def on_pre_enter(self):
        self._root.apply_bg()
        self._supplier_id = getattr(self.manager, "supplier_edit_id", None)
        self._prices = {}
        self._billing_ui.clear()
        self._cost_inputs.clear()
        self._client_inputs.clear()
        self._name_inputs.clear()

        if self._supplier_id:
            s = load_supplier(self._supplier_id)
            self.name_input.text = s.name if s else ""
            self.title.text = "Редактирование"
            raw = load_supplier_prices(self._supplier_id)
            for key, rec in raw.items():
                if float(rec.get("unit_price_cost") or 0) > 0:
                    self._prices[key] = dict(rec)
                    ru = rec.get("receipt_unit") or "piece"
                    if ru in ("pack", "уп", "упак"):
                        self._billing_ui[key] = "pack"
                    else:
                        self._billing_ui[key] = "piece"
        else:
            self.name_input.text = ""
            self.title.text = "Новый поставщик"

        self._rebuild_rows()

    def _rebuild_rows(self):
        self._cost_inputs.clear()
        self._client_inputs.clear()
        self._name_inputs.clear()
        self.form_box.clear_widgets()

        if not self._prices:
            empty = Label(
                text="Позиций пока нет.\nНажмите «Добавить позицию».",
                font_size=dp(14),
                color=(0.5, 0.5, 0.5, 1),
                halign="center",
                size_hint_y=None,
                height=dp(72),
            )
            empty._theme_slot = "muted"
            empty.bind(size=empty.setter("text_size"))
            self.form_box.add_widget(empty)
            return

        keys = sorted(self._prices.keys(), key=_item_sort_key)
        last_cat = None
        for item_key in keys:
            entry = get_catalog_entry(item_key)
            if not entry:
                continue
            cat = entry["category"]
            if cat != last_cat:
                last_cat = cat
                hdr = Label(
                    text=cat,
                    size_hint_y=None,
                    height=dp(26),
                    font_size=dp(14),
                    color=COLORS["text"],
                    halign="left",
                )
                hdr.bind(size=lambda inst, val: setattr(inst, "text_size", (inst.width, None)))
                self.form_box.add_widget(hdr)

            self.form_box.add_widget(self._build_price_row(item_key, entry))

    def _billing_for(self, item_key, entry):
        mode = self._billing_ui.get(item_key, "piece")
        upp = float(entry.get("units_per_pack") or 1)
        if upp <= 1:
            return "piece"
        return mode

    def _unit_bar(self, item_key, entry, on_change=None):
        upp = float(entry.get("units_per_pack") or 1)
        bar = BoxLayout(size_hint=(1, None), height=dp(34), spacing=dp(6))
        if upp <= 1:
            lbl = Label(text="за шт", font_size=dp(10), color=(0.5, 0.5, 0.5, 1), size_hint=(1, 1))
            lbl._theme_slot = "muted"
            bar.add_widget(lbl)
            return bar

        btn_piece = RoundedButton(text="за шт", font_size=dp(11), size_hint=(0.5, 1))
        btn_pack = RoundedButton(text=f"за уп ({int(upp)})", font_size=dp(11), size_hint=(0.5, 1))
        for b in (btn_piece, btn_pack):
            b.corner_radius = dp(8)

        def refresh():
            m = self._billing_for(item_key, entry)
            apply_btn_style(btn_piece, role="primary" if m == "piece" else "secondary")
            apply_btn_style(btn_pack, role="primary" if m == "pack" else "secondary")

        def set_piece(*_):
            self._billing_ui[item_key] = "piece"
            refresh()
            if on_change:
                on_change()

        def set_pack(*_):
            self._billing_ui[item_key] = "pack"
            refresh()
            if on_change:
                on_change()

        btn_piece.bind(on_press=set_piece)
        btn_pack.bind(on_press=set_pack)
        refresh()
        bar.add_widget(btn_piece)
        bar.add_widget(btn_pack)
        return bar

    def _display_cost(self, item_key, entry):
        rec = self._prices.get(item_key, {})
        cost_piece = float(rec.get("unit_price_cost") or 0)
        mode = self._billing_for(item_key, entry)
        upp = float(entry.get("units_per_pack") or 1)
        return piece_price_for_display(cost_piece, mode, upp)

    def _sync_card_height(self, card, widgets):
        def _refresh(*_):
            total = dp(16)
            for w in widgets:
                if getattr(w, "height", None):
                    total += w.height
                else:
                    total += dp(32)
            card.height = total

        for w in widgets:
            if hasattr(w, "bind"):
                w.bind(height=_refresh)
        _refresh()
        return _refresh

    def _build_price_row(self, item_key, entry):
        stored = normalize_price_record(self._prices.get(item_key, {}))
        card = BoxLayout(
            orientation="vertical",
            size_hint_y=None,
            spacing=dp(8),
            padding=(dp(6), dp(10)),
        )

        nm = Label(
            text=entry["name"],
            font_size=dp(14),
            color=COLORS["text"],
            halign="left",
            valign="top",
            bold=True,
        )
        bind_label_autosize(nm, min_height_dp=26, pad_dp=8)

        sub = Label(
            text=f"В расчёте: {entry['calc_match_key'] or '—'}",
            font_size=dp(11),
            color=(0.55, 0.55, 0.55, 1),
            halign="left",
            valign="top",
        )
        sub._theme_slot = "muted"
        bind_label_autosize(sub, min_height_dp=18, pad_dp=6)

        pname = make_price_input("Номенклатура поставщика", font_size_dp=13, height_dp=40)
        pname.input_filter = None
        pname.text = stored.get("product_name") or entry["name"]

        def on_unit_change():
            c2 = self._display_cost(item_key, entry)
            cost_in.text = f"{c2:g}" if c2 else ""

        unit_bar = self._unit_bar(item_key, entry, on_change=on_unit_change)

        lbl_cost = Label(
            text="Наша цена",
            font_size=dp(11),
            color=COLORS["text"],
            size_hint_y=None,
            height=dp(18),
            halign="left",
        )
        cost_in = make_price_input("0", font_size_dp=15, height_dp=44)
        c = self._display_cost(item_key, entry)
        cost_in.text = f"{c:g}" if c else ""

        lbl_client = Label(
            text="Цена для клиента",
            font_size=dp(11),
            color=COLORS["text"],
            size_hint_y=None,
            height=dp(18),
            halign="left",
        )
        client_in = make_price_input("0", font_size_dp=15, height_dp=44)
        cl_piece = float(stored.get("unit_price_client") or 0)
        cl_show = piece_price_for_display(
            cl_piece,
            self._billing_for(item_key, entry),
            float(entry.get("units_per_pack") or 1),
        )
        client_in.text = f"{cl_show:g}" if cl_show else ""

        actions = BoxLayout(size_hint_y=None, height=dp(40), spacing=dp(8))
        btn_fill = RoundedButton(text="+10% к клиенту", font_size=dp(12))
        btn_fill.corner_radius = dp(12)
        apply_btn_style(btn_fill, role="secondary")
        wrap_button_text(btn_fill, horizontal_padding_dp=6)

        def fill_client(*_):
            entered = self._parse_float(cost_in.text)
            mode = self._billing_for(item_key, entry)
            upp = float(entry.get("units_per_pack") or 1)
            piece = receipt_price_to_piece(entered, mode, upp)
            if piece > 0:
                cl_p = client_from_cost(piece)
                cl_disp = piece_price_for_display(cl_p, mode, upp)
                client_in.text = f"{cl_disp:g}"

        btn_fill.bind(on_press=fill_client)

        btn_rm = RoundedButton(text="Удалить", font_size=dp(12))
        btn_rm.corner_radius = dp(12)
        apply_btn_style(btn_rm, role="danger")
        wrap_button_text(btn_rm, horizontal_padding_dp=6)

        def remove_row(*_):
            self._prices.pop(item_key, None)
            self._billing_ui.pop(item_key, None)
            self._rebuild_rows()

        btn_rm.bind(on_press=remove_row)
        actions.add_widget(btn_fill)
        actions.add_widget(btn_rm)

        for w in (nm, sub, pname, unit_bar, lbl_cost, cost_in, lbl_client, client_in, actions):
            card.add_widget(w)

        track = [nm, sub, pname, unit_bar, lbl_cost, cost_in, lbl_client, client_in, actions]
        self._sync_card_height(card, track)

        self._cost_inputs[item_key] = cost_in
        self._client_inputs[item_key] = client_in
        self._name_inputs[item_key] = pname
        return card

    def _open_add_picker(self, *_):
        available = [it for it in _catalog_items_flat() if it["item_key"] not in self._prices]
        if not available:
            self._show_info("Все позиции каталога уже добавлены.")
            return

        content = BoxLayout(orientation="vertical", padding=dp(12), spacing=dp(8))
        title = Label(
            text="Выберите позицию",
            font_size=dp(16),
            color=COLORS["text"],
            size_hint_y=None,
            height=dp(28),
            bold=True,
        )
        content.add_widget(title)

        list_box = BoxLayout(orientation="vertical", spacing=dp(6), size_hint_y=None)
        list_box.bind(minimum_height=list_box.setter("height"))

        pending_binds = []
        last_cat = None
        for it in available:
            if it["category"] != last_cat:
                last_cat = it["category"]
                hdr = Label(
                    text=last_cat,
                    font_size=dp(12),
                    color=(0.45, 0.45, 0.45, 1),
                    size_hint_y=None,
                    height=dp(22),
                    halign="left",
                )
                hdr._theme_slot = "muted"
                hdr.bind(size=lambda inst, val: setattr(inst, "text_size", (inst.width, None)))
                list_box.add_widget(hdr)

            btn = RoundedButton(
                text=it["name"],
                size_hint_y=None,
                height=dp(52),
                font_size=dp(13),
            )
            btn.corner_radius = dp(12)
            apply_btn_style(btn, role="surface")
            wrap_button_text(btn, horizontal_padding_dp=8)
            pending_binds.append((btn, it["item_key"]))
            list_box.add_widget(btn)

        scroll = ScrollView(size_hint=(1, 1))
        scroll.add_widget(list_box)
        content.add_widget(scroll)

        btn_cancel = RoundedButton(text="Отмена", size_hint=(1, None), height=dp(40))
        btn_cancel.corner_radius = dp(12)
        apply_btn_style(btn_cancel, role="secondary")
        content.add_widget(btn_cancel)

        picker_modal = RoundedModal(content=content, card_size_hint=(0.92, 0.75))
        for btn, key in pending_binds:
            btn.bind(
                on_press=lambda _, k=key, m=picker_modal: self._open_price_dialog(k, m)
            )
        btn_cancel.bind(on_press=lambda *_: picker_modal.dismiss())
        picker_modal.open()

    def _open_price_dialog(self, item_key, picker_modal=None):
        if picker_modal:
            picker_modal.dismiss()

        entry = get_catalog_entry(item_key)
        if not entry:
            return

        self._billing_ui.setdefault(item_key, "piece")
        upp = float(entry.get("units_per_pack") or 1)

        content = BoxLayout(orientation="vertical", padding=dp(14), spacing=dp(10))
        dlg_title = Label(
            text=entry["name"],
            font_size=dp(15),
            color=COLORS["text"],
            halign="center",
            valign="top",
        )
        bind_label_autosize(dlg_title, min_height_dp=32, pad_dp=8)
        content.add_widget(dlg_title)

        sub = Label(
            text=f"В расчёте: {entry['calc_match_key']}",
            font_size=dp(11),
            color=(0.5, 0.5, 0.5, 1),
            halign="left",
            valign="top",
        )
        sub._theme_slot = "muted"
        bind_label_autosize(sub, min_height_dp=20, pad_dp=6)
        content.add_widget(sub)

        unit_holder = BoxLayout(size_hint_y=None, height=dp(34))

        cost_in = make_price_input("Наша цена, ₽/шт", font_size_dp=15, height_dp=46)
        client_in = make_price_input("Клиент, ₽/шт (пусто = +10%)", font_size_dp=14, height_dp=46)

        def upd_cost_hint():
            m = self._billing_for(item_key, entry)
            if m == "pack" and upp > 1:
                cost_in.hint_text = "Наша цена, ₽/уп"
                client_in.hint_text = "Клиент, ₽/уп (пусто = +10%)"
            else:
                cost_in.hint_text = "Наша цена, ₽/шт"
                client_in.hint_text = "Клиент, ₽/шт (пусто = +10%)"

        if upp > 1:
            unit_holder.add_widget(
                self._unit_bar(item_key, entry, on_change=upd_cost_hint)
            )
        else:
            lbl = Label(text="Цена за штуку", font_size=dp(11), color=(0.5, 0.5, 0.5, 1))
            lbl._theme_slot = "muted"
            unit_holder.add_widget(lbl)

        upd_cost_hint()
        content.add_widget(unit_holder)
        content.add_widget(cost_in)
        content.add_widget(client_in)

        btns = BoxLayout(size_hint_y=None, height=dp(44), spacing=dp(8))
        btn_ok = RoundedButton(text="Добавить")
        btn_ok.corner_radius = dp(12)
        apply_btn_style(btn_ok, role="primary")
        btn_no = RoundedButton(text="Отмена")
        btn_no.corner_radius = dp(12)
        apply_btn_style(btn_no, role="secondary")
        btns.add_widget(btn_no)
        btns.add_widget(btn_ok)
        content.add_widget(btns)

        modal = RoundedModal(content=content, card_size_hint=(0.92, None), card_height_dp=400)

        def confirm(*_):
            entered = self._parse_float(cost_in.text)
            if entered <= 0:
                return
            mode = self._billing_for(item_key, entry)
            cost_piece = receipt_price_to_piece(entered, mode, upp)
            client_entered = self._parse_float(client_in.text)
            client_piece = (
                receipt_price_to_piece(client_entered, mode, upp)
                if client_entered > 0
                else None
            )
            self._prices[item_key] = normalize_price_record(
                {
                    "product_name": entry["name"],
                    "unit_price_cost": cost_piece,
                    "unit_price_client": client_piece,
                    "receipt_unit": "piece",
                    "units_per_pack": upp,
                }
            )
            modal.dismiss()
            self._rebuild_rows()

        btn_ok.bind(on_press=confirm)
        btn_no.bind(on_press=lambda *_: modal.dismiss())
        modal.open()

    def _show_info(self, text):
        content = BoxLayout(orientation="vertical", padding=dp(16), spacing=dp(12))
        lbl = Label(text=text, font_size=dp(14), color=COLORS["text"], halign="center")
        lbl.bind(size=lambda inst, val: setattr(inst, "text_size", (inst.width, None)))
        btn = RoundedButton(text="OK", size_hint_y=None, height=dp(40))
        btn.corner_radius = dp(12)
        apply_btn_style(btn, role="primary")
        content.add_widget(lbl)
        content.add_widget(btn)
        modal = RoundedModal(content=content, card_size_hint=(0.85, None), card_height_dp=160)
        btn.bind(on_press=lambda *_: modal.dismiss())
        modal.open()

    def _parse_float(self, text):
        raw = (text or "").strip().replace(",", ".")
        try:
            return float(raw) if raw else 0.0
        except ValueError:
            return 0.0

    def _go_back(self, *_):
        self.manager.current = "suppliers"

    def _collect_prices_from_form(self):
        out = {}
        for item_key in self._prices:
            entry = get_catalog_entry(item_key)
            if not entry or item_key not in self._cost_inputs:
                continue
            entered = self._parse_float(self._cost_inputs[item_key].text)
            if entered <= 0:
                continue
            mode = self._billing_for(item_key, entry)
            upp = float(entry.get("units_per_pack") or 1)
            cost_piece = receipt_price_to_piece(entered, mode, upp)
            client_entered = self._parse_float(self._client_inputs[item_key].text)
            client_piece = (
                receipt_price_to_piece(client_entered, mode, upp)
                if client_entered > 0
                else None
            )
            out[item_key] = normalize_price_record(
                {
                    "product_name": self._name_inputs[item_key].text.strip() or entry["name"],
                    "unit_price_cost": cost_piece,
                    "unit_price_client": client_piece,
                    "receipt_unit": "piece",
                    "units_per_pack": upp,
                }
            )
        return out

    def _save(self, *_):
        name = self.name_input.text.strip()
        if not name:
            return
        if self._supplier_id:
            s = load_supplier(self._supplier_id)
            if s:
                s.name = name
                save_supplier(s)
                sid = s.id
            else:
                sid = None
        else:
            s = Supplier(name)
            s = save_supplier(s)
            sid = s.id
            self._supplier_id = sid
            self.manager.supplier_edit_id = sid

        if sid:
            save_supplier_prices(sid, self._collect_prices_from_form())
        self.manager.current = "suppliers"

    def _confirm_delete(self, *_):
        if not self._supplier_id:
            self.manager.current = "suppliers"
            return
        delete_supplier(self._supplier_id)
        self.manager.current = "suppliers"
