"""Стоимость материалов по проекту для выбранного поставщика."""
from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.scrollview import ScrollView
from kivy.metrics import dp

from database import load_project
from ui_style import (
    COLORS,
    apply_btn_style,
    wrap_button_text,
    style_title,
    bind_label_autosize,
    format_money_ru,
    format_number_ru,
)
from widgets.ui_components import RoundedButton, RoundedLabel
from widgets.screen_bg import make_bg_root
from supplier_db import list_suppliers, init_supplier_tables
from cost_calculator import calculate_project_cost
import theme


class ProjectCostScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._selected_supplier_id = None
        self._supplier_buttons = {}

        self._root, _ = make_bg_root(dim_mask=True)
        main = BoxLayout(orientation="vertical", spacing=dp(8), padding=dp(10), size_hint=(1, 1))

        toolbar = BoxLayout(size_hint=(1, None), height=dp(72), spacing=dp(6))
        btn_back = RoundedButton(text="Назад", size_hint=(0.28, 1), font_size=dp(14))
        btn_back.corner_radius = dp(12)
        apply_btn_style(btn_back, role="secondary")
        wrap_button_text(btn_back)
        btn_back.bind(on_press=lambda *_: setattr(self.manager, "current", "materials_project_result"))

        self.title = RoundedLabel(
            text="Стоимость",
            size_hint=(0.44, 1),
            color=COLORS["text"],
            halign="center",
            valign="middle",
        )
        self.title.corner_radius = dp(12)
        style_title(self.title)
        self.title.bind(size=self.title.setter("text_size"))

        spacer = Label(size_hint=(0.28, 1))
        toolbar.add_widget(btn_back)
        toolbar.add_widget(self.title)
        toolbar.add_widget(spacer)

        self.supplier_bar = BoxLayout(size_hint=(1, None), height=dp(52), spacing=dp(6))
        sup_scroll = ScrollView(size_hint=(1, 1), do_scroll_x=True, do_scroll_y=False)
        self.supplier_inner = BoxLayout(size_hint=(None, 1), spacing=dp(6))
        self.supplier_inner.bind(minimum_width=self.supplier_inner.setter("width"))
        sup_scroll.add_widget(self.supplier_inner)
        self.supplier_bar.add_widget(sup_scroll)

        self.summary_label = Label(
            text="",
            size_hint_y=None,
            height=dp(64),
            font_size=dp(13),
            color=COLORS["text"],
            halign="left",
            valign="top",
        )
        bind_label_autosize(self.summary_label, min_height_dp=48, pad_dp=10)

        self.lines_box = BoxLayout(orientation="vertical", spacing=dp(10), size_hint_y=None, padding=(0, dp(4)))
        self.lines_box.bind(minimum_height=self.lines_box.setter("height"))

        table_scroll = ScrollView(size_hint=(1, 1))
        table_scroll.add_widget(self.lines_box)

        main.add_widget(toolbar)
        main.add_widget(Label(text="Поставщик:", size_hint_y=None, height=dp(20), font_size=dp(12), color=COLORS["text"]))
        main.add_widget(self.supplier_bar)
        main.add_widget(self.summary_label)
        main.add_widget(table_scroll)

        self._root.add_widget(main)
        self.add_widget(self._root)

    def on_pre_enter(self):
        self._root.apply_bg()
        init_supplier_tables()
        project = getattr(self.manager, "current_project", None)
        if project and project.id:
            loaded = load_project(project.id)
            if loaded:
                self.manager.current_project = loaded
                project = loaded
        if project:
            self.title.text = f"Стоимость\n{project.name}"
        self._build_supplier_bar()
        if self._selected_supplier_id:
            self._recalculate()

    def _build_supplier_bar(self):
        self.supplier_inner.clear_widgets()
        self._supplier_buttons.clear()
        suppliers = list_suppliers()
        if not suppliers:
            lbl = Label(
                text="Нет поставщиков",
                font_size=dp(12),
                color=(0.5, 0.5, 0.5, 1),
                size_hint=(None, 1),
                width=dp(200),
            )
            lbl._theme_slot = "muted"
            self.supplier_inner.add_widget(lbl)
            self.summary_label.text = "Добавьте поставщика в разделе «Поставщики»."
            return

        if self._selected_supplier_id is None:
            self._selected_supplier_id = suppliers[0].id

        for s in suppliers:
            btn = RoundedButton(
                text=s.name,
                size_hint=(None, 1),
                width=dp(max(100, len(s.name) * 9)),
                font_size=dp(12),
            )
            btn.corner_radius = dp(12)
            role = "primary" if s.id == self._selected_supplier_id else "secondary"
            apply_btn_style(btn, role=role)
            sid = s.id
            btn.bind(on_press=lambda _, sid=sid: self._select_supplier(sid))
            self.supplier_inner.add_widget(btn)
            self._supplier_buttons[s.id] = btn

    def _select_supplier(self, supplier_id):
        self._selected_supplier_id = supplier_id
        for sid, btn in self._supplier_buttons.items():
            apply_btn_style(btn, role="primary" if sid == supplier_id else "secondary")
        self._recalculate()

    def _recalculate(self):
        project = getattr(self.manager, "current_project", None)
        if not project or not self._selected_supplier_id:
            return

        data = calculate_project_cost(project, self._selected_supplier_id)
        self.lines_box.clear_widgets()
        self.lines_box.add_widget(self._table_header())

        for line in data["lines"]:
            self.lines_box.add_widget(self._line_card(line))

        miss = data["missing_count"]
        miss_txt = f"\nБез цены: {miss} поз." if miss else ""
        self.summary_label.text = (
            f"S = {format_number_ru(data['area_m2'], 2)} м²  |  P = {format_number_ru(data['perimeter_m'], 2)} м\n"
            f"ИТОГО: {format_money_ru(data['total'])}{miss_txt}"
        )

    def _table_header(self):
        row = BoxLayout(orientation="vertical", size_hint_y=None, spacing=dp(2))
        lbl = Label(
            text="Позиции",
            font_size=dp(13),
            color=COLORS["text"],
            bold=True,
            halign="left",
            valign="middle",
        )
        bind_label_autosize(lbl, min_height_dp=24)
        row.add_widget(lbl)

        def _sync_h(*_):
            row.height = lbl.height

        lbl.bind(height=_sync_h)
        _sync_h()
        return row

    def _line_card(self, line):
        name = line["name"]
        if not line["has_price"]:
            name = f"{name} *"

        card = BoxLayout(
            orientation="vertical",
            size_hint_y=None,
            spacing=dp(6),
            padding=(dp(4), dp(8)),
        )

        title = Label(
            text=name,
            font_size=dp(13),
            color=COLORS["text"],
            halign="left",
            valign="top",
        )
        bind_label_autosize(title, min_height_dp=28, pad_dp=10)
        card.add_widget(title)

        nums = BoxLayout(size_hint_y=None, height=dp(30), spacing=dp(6))
        qty_txt = f"Кол-во: {format_number_ru(line['qty'], 0)}"
        if line["has_price"]:
            price_txt = f"Цена: {format_money_ru(line['unit_price'])}"
            sum_txt = f"Сумма: {format_money_ru(line['line_total'])}"
        else:
            price_txt = "Цена: —"
            sum_txt = "Сумма: —"

        for part in (qty_txt, price_txt, sum_txt):
            cell = Label(
                text=part,
                font_size=dp(12),
                color=COLORS["text"],
                halign="left",
                valign="middle",
                size_hint_x=0.33,
            )
            cell.bind(size=lambda inst, val: setattr(inst, "text_size", (inst.width, None)))
            nums.add_widget(cell)
        card.add_widget(nums)

        def _sync_card_h(*_):
            card.height = title.height + dp(30) + dp(12)

        title.bind(height=_sync_card_h)
        _sync_card_h()
        return card
