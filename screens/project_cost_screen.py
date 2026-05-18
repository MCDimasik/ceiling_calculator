"""Стоимость материалов по проекту для выбранного поставщика."""
from kivy.clock import Clock
from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.scrollview import ScrollView
from kivy.graphics import Color, RoundedRectangle
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
from app_access import is_admin
import theme


class ProjectCostScreen(Screen):
    LONG_PRESS_SEC = 1.0

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._selected_supplier_id = None
        self._supplier_buttons = {}
        self._show_benefit = False
        self._title_press_event = None
        self._last_cost_data = None

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
            size_hint=(1, 1),
            color=COLORS["text"],
            halign="center",
            valign="middle",
        )
        self.title.corner_radius = dp(12)
        style_title(self.title)
        self.title.bind(size=self.title.setter("text_size"))

        self.title_touch = BoxLayout(size_hint=(0.44, 1))
        self.title_touch.add_widget(self.title)
        self.title_touch.bind(on_touch_down=self._on_title_touch_down)
        self.title_touch.bind(on_touch_up=self._on_title_touch_up)

        spacer = Label(size_hint=(0.28, 1))
        toolbar.add_widget(btn_back)
        toolbar.add_widget(self.title_touch)
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
            height=dp(44),
            font_size=dp(13),
            color=COLORS["text"],
            halign="left",
            valign="top",
        )
        bind_label_autosize(self.summary_label, min_height_dp=36, pad_dp=8)

        self.lines_box = BoxLayout(orientation="vertical", spacing=dp(8), size_hint_y=None, padding=(0, dp(4)))
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
        if not is_admin():
            self.manager.current = "materials_project_result"
            return
        self._root.apply_bg()
        self._show_benefit = False
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

    def _on_title_touch_down(self, widget, touch):
        if not widget.collide_point(*touch.pos):
            return False
        if self._title_press_event is not None:
            Clock.unschedule(self._title_press_event)
        self._title_press_event = Clock.schedule_once(self._reveal_benefit, self.LONG_PRESS_SEC)
        return True

    def _on_title_touch_up(self, widget, touch):
        if not widget.collide_point(*touch.pos):
            return False
        if self._title_press_event is not None:
            Clock.unschedule(self._title_press_event)
            self._title_press_event = None
        return True

    def _reveal_benefit(self, *_dt):
        self._title_press_event = None
        if self._show_benefit:
            return
        self._show_benefit = True
        self._render_lines()

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

        self._last_cost_data = calculate_project_cost(project, self._selected_supplier_id)
        data = self._last_cost_data

        miss = data["missing_count"]
        miss_txt = f"  |  Без цены: {miss} поз." if miss else ""
        self.summary_label.text = (
            f"S = {format_number_ru(data['area_m2'], 2)} м²  |  "
            f"P = {format_number_ru(data['perimeter_m'], 2)} м{miss_txt}"
        )
        self._render_lines()

    def _render_lines(self):
        data = self._last_cost_data
        if not data:
            return

        self.lines_box.clear_widgets()
        self.lines_box.add_widget(self._table_header())

        for line in data["lines"]:
            self.lines_box.add_widget(self._line_card(line))

        self.lines_box.add_widget(self._total_row(data["total"]))

        if self._show_benefit:
            benefit = data.get("benefit")
            if benefit is not None:
                self.lines_box.add_widget(self._benefit_row(benefit))
            else:
                self.lines_box.add_widget(
                    self._benefit_row(None, hint="Нет наших цен у поставщика")
                )

    def _bind_box_height(self, box):
        box.bind(minimum_height=box.setter("height"))

    def _surface_band(self, height_dp):
        band = BoxLayout(orientation="vertical", size_hint_y=None, height=dp(height_dp), padding=(dp(10), dp(6)))
        with band.canvas.before:
            Color(*COLORS.get("surface", (0.94, 0.96, 0.99, 1)))
            band._bg = RoundedRectangle(
                pos=band.pos,
                size=band.size,
                radius=[(dp(10), dp(10))] * 4,
            )
        band.bind(
            pos=lambda inst, val: setattr(inst._bg, "pos", inst.pos),
            size=lambda inst, val: setattr(inst._bg, "size", inst.size),
        )
        return band

    def _table_header(self):
        row = BoxLayout(orientation="vertical", size_hint_y=None, spacing=dp(2))
        lbl = Label(
            text="Позиции",
            font_size=dp(13),
            color=COLORS["text"],
            bold=True,
            halign="left",
            valign="middle",
            size_hint_y=None,
            height=dp(24),
        )
        lbl.bind(size=lambda inst, val: setattr(inst, "text_size", (inst.width, None)))
        row.add_widget(lbl)
        row.height = dp(24)
        return row

    def _line_card(self, line):
        name = line["name"]
        if not line["has_price"]:
            name = f"{name} *"

        card = BoxLayout(orientation="vertical", size_hint_y=None, spacing=dp(4))
        self._bind_box_height(card)

        title_band = self._surface_band(36)
        title = Label(
            text=name,
            font_size=dp(14),
            color=COLORS["text"],
            halign="left",
            valign="middle",
            bold=True,
            size_hint_y=None,
            height=dp(28),
        )
        title.bind(size=lambda inst, val: setattr(inst, "text_size", (inst.width - dp(8), None)))
        title_band.add_widget(title)

        nums = BoxLayout(size_hint_y=None, height=dp(28), spacing=dp(6), padding=(dp(4), 0))
        if line.get("by_pack") and line["has_price"]:
            qty_txt = (
                f"Кол-во: {format_number_ru(line['bill_qty'], 0)} уп "
                f"({format_number_ru(line['qty'], 0)} шт)"
            )
            price_txt = f"Цена: {format_money_ru(line['unit_price'])}/уп"
        else:
            qty_txt = f"Кол-во: {format_number_ru(line['qty'], 0)} шт"
            if line["has_price"]:
                price_txt = f"Цена: {format_money_ru(line['unit_price'])}"
            else:
                price_txt = "Цена: —"
        sum_txt = (
            f"Сумма: {format_money_ru(line['line_total'])}"
            if line["has_price"]
            else "Сумма: —"
        )

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

        card.add_widget(title_band)
        card.add_widget(nums)
        return card

    def _total_row(self, total):
        row = BoxLayout(orientation="horizontal", size_hint_y=None, height=dp(44), spacing=dp(8))
        with row.canvas.before:
            Color(*COLORS.get("primary", (0.22, 0.52, 0.96, 1)))
            row._bg = RoundedRectangle(
                pos=row.pos,
                size=row.size,
                radius=[(dp(12), dp(12))] * 4,
            )
        row.bind(
            pos=lambda inst, val: setattr(inst._bg, "pos", inst.pos),
            size=lambda inst, val: setattr(inst._bg, "size", inst.size),
        )

        lbl = Label(
            text="Итого",
            font_size=dp(16),
            bold=True,
            color=(1, 1, 1, 1),
            halign="left",
            valign="middle",
            size_hint_x=0.4,
        )
        lbl.bind(size=lambda inst, val: setattr(inst, "text_size", (inst.width, None)))

        val = Label(
            text=format_money_ru(total),
            font_size=dp(16),
            bold=True,
            color=(1, 1, 1, 1),
            halign="right",
            valign="middle",
            size_hint_x=0.6,
        )
        val.bind(size=lambda inst, val: setattr(inst, "text_size", (inst.width, None)))
        row.add_widget(lbl)
        row.add_widget(val)
        return row

    def _benefit_row(self, benefit, hint=None):
        row = BoxLayout(orientation="horizontal", size_hint_y=None, height=dp(40), spacing=dp(8), padding=(dp(10), 0))
        with row.canvas.before:
            Color(*COLORS.get("surface_alt", (0.97, 0.97, 0.98, 1)))
            row._bg = RoundedRectangle(
                pos=row.pos,
                size=row.size,
                radius=[(dp(10), dp(10))] * 4,
            )
        row.bind(
            pos=lambda inst, val: setattr(inst._bg, "pos", inst.pos),
            size=lambda inst, val: setattr(inst._bg, "size", inst.size),
        )

        lbl = Label(
            text="Выгода",
            font_size=dp(15),
            bold=True,
            color=COLORS["text"],
            halign="left",
            valign="middle",
            size_hint_x=0.4,
        )
        lbl.bind(size=lambda inst, val: setattr(inst, "text_size", (inst.width, None)))

        if benefit is not None:
            val_text = format_money_ru(benefit)
            val_color = COLORS["text"]
        else:
            val_text = hint or "—"
            val_color = COLORS.get("muted", (0.5, 0.5, 0.5, 1))

        val = Label(
            text=val_text,
            font_size=dp(15),
            bold=True,
            color=val_color,
            halign="right",
            valign="middle",
            size_hint_x=0.6,
        )
        val.bind(size=lambda inst, val: setattr(inst, "text_size", (inst.width, None)))
        row.add_widget(lbl)
        row.add_widget(val)
        return row
