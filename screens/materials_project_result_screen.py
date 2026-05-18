from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.image import Image
from kivy.uix.scrollview import ScrollView
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.app import App

from models import CeilingLayout
from materials_calculator import (
    calculate_materials,
    room_perimeter_cm,
    room_area_m2,
    room_length_for_rows_cm,
    grilyato_cassette_count,
)
from ui_style import COLORS, apply_btn_style, style_title, wrap_button_text
from widgets.ui_components import RoundedButton, RoundedLabel, SegmentedControl
from database import update_project_materials_config
from app_access import is_admin
import theme


class MaterialsProjectResultScreen(Screen):
    """
    Суммарный расчёт материалов по всему проекту.
    Конфигурация (тип потолка/подвес/ячейка) хранится в проекте и является приоритетной,
    но для комнат с materials_override учитываем их индивидуальный конфиг.
    """

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._calc_trigger = None
        self._loading_config = False

        root = FloatLayout()
        self._root = root
        self.bg_photo = Image(source="assets/bg_light.png", allow_stretch=True, keep_ratio=True)
        self.bg_photo.size_hint = (None, None)
        self.bg_photo.pos = (0, 0)
        self.bg_photo.size = root.size
        self.bg_photo.opacity = 0
        root.add_widget(self.bg_photo)
        root.bind(pos=lambda *_: self._layout_bg_cover(), size=lambda *_: self._layout_bg_cover())

        # Маска над фоном (как на экране расчёта комнаты) — нужна только в тёмной теме.
        from kivy.uix.widget import Widget
        from kivy.graphics import Color, Rectangle

        self._bg_mask = Widget(size_hint=(1, 1))
        with self._bg_mask.canvas.before:
            self._mask_color = Color(0, 0, 0, 0)
            self._mask_rect = Rectangle(pos=self._bg_mask.pos, size=self._bg_mask.size)
        self._bg_mask.bind(
            pos=lambda *_: setattr(self._mask_rect, "pos", self._bg_mask.pos),
            size=lambda *_: setattr(self._mask_rect, "size", self._bg_mask.size),
        )
        self._bg_mask._theme_redraw = lambda *_: self._apply_bg()
        root.add_widget(self._bg_mask)

        main = BoxLayout(orientation="vertical", spacing=dp(2), size_hint=(1, 1))

        toolbar = BoxLayout(size_hint=(1, None), height=dp(72), padding=(dp(12), dp(6)), spacing=dp(10))
        btn_back = RoundedButton(text="Назад", size_hint=(0.30, 1), font_size=dp(14))
        btn_back.corner_radius = dp(12)
        apply_btn_style(btn_back, role="secondary")
        wrap_button_text(btn_back)
        btn_back.bind(on_press=lambda *_: setattr(self.manager, "current", "materials_rooms"))

        self.title = RoundedLabel(
            text="",
            size_hint=(0.40, 1),
            color=COLORS["text"],
            halign="center",
            valign="middle",
        )
        self.title.corner_radius = dp(12)
        style_title(self.title)
        self.title.bind(size=self._update_title_text_size)

        self.btn_cost = RoundedButton(text="Стоимость", size_hint=(0.30, 1), font_size=dp(14))
        self.btn_cost.corner_radius = dp(12)
        apply_btn_style(self.btn_cost, role="secondary")
        wrap_button_text(self.btn_cost)
        self.btn_cost.bind(on_press=self._on_cost_press)

        toolbar.add_widget(btn_back)
        toolbar.add_widget(self.title)
        toolbar.add_widget(self.btn_cost)

        controls = BoxLayout(orientation="vertical", size_hint=(1, None), spacing=dp(10), padding=(dp(8), dp(10), dp(8), dp(8)))
        controls.bind(minimum_height=controls.setter("height"))

        self.ceiling_tabs = SegmentedControl(values=["Армстронг", "Грильято", "GL"], selected="Армстронг", size_hint=(1, None), height=dp(48))
        self.susp_tabs = SegmentedControl(values=["Подвес 0,5", "Подвес 1", "Подвес 1,5"], selected="Подвес 0,5", size_hint=(1, None), height=dp(48))
        self.cell_tabs = SegmentedControl(values=["50x50", "75x75", "100x100"], selected="50x50", size_hint=(1, None), height=dp(48))

        self.ceiling_tabs.on_change = lambda *_: self._on_ceiling_tab_change()
        self.susp_tabs.on_change = lambda *_: (self._persist_project_config(), self.request_calculate())
        self.cell_tabs.on_change = lambda *_: (self._persist_project_config(), self.request_calculate())

        controls.add_widget(self.ceiling_tabs)
        controls.add_widget(self.susp_tabs)
        controls.add_widget(self.cell_tabs)

        self.result_label = Label(
            text="",
            color=COLORS["text"],
            halign="left",
            valign="top",
            text_size=(dp(295), None),
            size_hint_y=None,
        )
        self.result_label._theme_slot = "text"
        self.result_label.bind(texture_size=lambda inst, size: setattr(inst, "height", size[1] + dp(20)))

        content = BoxLayout(orientation="vertical", padding=dp(8), spacing=dp(8), size_hint_y=None)
        content.bind(minimum_height=content.setter("height"))
        content.add_widget(self.result_label)

        scroll = ScrollView(size_hint=(1, 1))
        scroll.add_widget(content)

        main.add_widget(toolbar)
        main.add_widget(controls)
        main.add_widget(scroll)
        root.add_widget(main)
        self.add_widget(root)

    def _update_title_text_size(self, *_):
        self.title.text_size = (self.title.width - dp(10), self.title.height)

    def _apply_bg(self):
        app = App.get_running_app()
        mode = getattr(app, "theme_mode", theme.THEME_LIGHT)
        effective_dark = theme.resolve_effective_dark(mode)
        tex = None
        try:
            tex = getattr(app, "bg_textures", {}).get(mode)
        except Exception:
            tex = None
        if tex is not None:
            self.bg_photo.texture = tex
        self.bg_photo.opacity = 1.0
        self._layout_bg_cover()
        try:
            if hasattr(self, "_mask_color"):
                self._mask_color.rgba = (0, 0, 0, 0.9) if effective_dark else (0, 0, 0, 0.0)
        except Exception:
            pass

    def _layout_bg_cover(self):
        tex = getattr(self.bg_photo, "texture", None)
        if tex is None or tex.width <= 0 or tex.height <= 0:
            self.bg_photo.pos = self._root.pos
            self.bg_photo.size = self._root.size
            return
        cw, ch = self._root.size
        if cw <= 0 or ch <= 0:
            return
        vw, vh = float(tex.width), float(tex.height)
        scale = max(cw / vw, ch / vh)
        w = vw * scale
        h = vh * scale
        x = self._root.x + (cw - w) / 2.0
        y = self._root.y + (ch - h) / 2.0
        self.bg_photo.pos = (x, y)
        self.bg_photo.size = (w, h)

    def _project_config(self):
        project = getattr(self.manager, "current_project", None)
        ceiling = getattr(project, "materials_ceiling", None) or "Армстронг"
        susp = getattr(project, "materials_susp", None) or "Подвес 0,5"
        cell = getattr(project, "materials_cell", None) or "50x50"
        return ceiling, susp, cell

    def _apply_config_to_ui(self, ceiling: str, susp: str, cell: str):
        self._loading_config = True
        try:
            self.ceiling_tabs.begin_batch()
            self.susp_tabs.begin_batch()
            self.cell_tabs.begin_batch()
            self.ceiling_tabs.set_selected(ceiling, animate=False)
            self.susp_tabs.set_selected(susp, animate=False)
            self.cell_tabs.set_selected(cell, animate=False)
            self.ceiling_tabs.end_batch()
            self.susp_tabs.end_batch()
            self.cell_tabs.end_batch()
            self._toggle_cell_row()
        finally:
            self._loading_config = False

    def _persist_project_config(self):
        if self._loading_config:
            return
        project = getattr(self.manager, "current_project", None)
        if not project:
            return
        ceiling = getattr(self.ceiling_tabs, "selected", None)
        susp = getattr(self.susp_tabs, "selected", None)
        cell = getattr(self.cell_tabs, "selected", None)
        project.materials_ceiling = ceiling
        project.materials_susp = susp
        project.materials_cell = cell
        if getattr(project, "id", None):
            update_project_materials_config(project.id, ceiling=ceiling, susp=susp, cell=cell)

    def _on_ceiling_tab_change(self):
        self.susp_tabs.begin_batch()
        self.cell_tabs.begin_batch()
        if self.ceiling_tabs.selected == "Армстронг":
            self.susp_tabs.set_selected("Подвес 0,5", animate=False)
        else:
            self.cell_tabs.set_selected("50x50", animate=False)
        self.susp_tabs.end_batch()
        self.cell_tabs.end_batch()
        self._toggle_cell_row()
        self._persist_project_config()
        self.request_calculate()

    def _toggle_cell_row(self):
        is_gr = self.ceiling_tabs.selected in ("Грильято", "GL")
        self.cell_tabs.disabled = not is_gr
        self.cell_tabs.opacity = 1.0
        self.cell_tabs.height = dp(48)

    def on_pre_enter(self):
        self._apply_bg()
        self._apply_cost_button()
        project = getattr(self.manager, "current_project", None)
        self.title.text = project.name if project else "Проект"
        ceiling, susp, cell = self._project_config()
        self._apply_config_to_ui(ceiling, susp, cell)
        self.calculate()

    def _apply_cost_button(self):
        admin = is_admin()
        self.btn_cost.disabled = not admin
        self.btn_cost.opacity = 0.4 if not admin else 1.0
        apply_btn_style(self.btn_cost, role="secondary" if admin else "surface")

    def _on_cost_press(self, *_):
        if not is_admin():
            return
        self.manager.current = "project_cost"

    def request_calculate(self):
        if self._calc_trigger is not None:
            try:
                Clock.unschedule(self._calc_trigger)
            except Exception:
                pass
        self._calc_trigger = lambda dt: self.calculate()
        Clock.schedule_once(self._calc_trigger, 0)

    def _room_effective_config(self, room):
        """Конфиг для конкретной комнаты с учётом override."""
        p_ceiling, p_susp, p_cell = self._project_config()
        if bool(getattr(room, "materials_override", False)):
            return (
                getattr(room, "materials_ceiling", None) or p_ceiling,
                getattr(room, "materials_susp", None) or p_susp,
                getattr(room, "materials_cell", None) or p_cell,
            )
        return p_ceiling, p_susp, p_cell

    def calculate(self):
        project = getattr(self.manager, "current_project", None)
        if not project or not getattr(project, "rooms", None):
            self.result_label.text = "Нет комнат"
            return

        total_area = 0.0
        total_perimeter_m = 0.0
        totals = {}

        type_map = {"Армстронг": "armstrong", "Грильято": "grilyato_classic", "GL": "grilyato_gl"}

        for room in project.rooms:
            if not getattr(room, "walls", None):
                continue

            ceiling, susp, cell = self._room_effective_config(room)
            calc_type = type_map.get(ceiling, "armstrong")

            layout = CeilingLayout(room)
            layout.calculate_layout()
            cassette_count = layout.full_tiles + layout.cut_tiles
            if calc_type in ("grilyato_gl", "grilyato_classic"):
                cassette_count = grilyato_cassette_count(room.walls, cassette_count)

            light_count = len(getattr(room, "light_fixtures", []) or [])

            result = calculate_materials(
                ceiling_type=calc_type,
                walls=room.walls,
                cassette_count=cassette_count,
                rows_3600=None,
                rows_2400=None,
                cell_size=cell,
                light_count=light_count,
            )

            total_area += room_area_m2(room.walls)
            total_perimeter_m += room_perimeter_cm(room.walls) / 100.0

            # Нормализуем "Подвес" в ключ вида "Подвес (x)"
            size_txt = (susp or "Подвес 0,5").replace("Подвес", "").strip()
            for name, value in result.items():
                key = name
                if name == "Подвес":
                    key = f"Подвес ({size_txt})"
                # Позиции, зависящие от ячейки — нельзя суммировать вместе.
                elif name in ("Профиль Папа", "Профиль Мама", "Заглушки"):
                    key = f"{name} ({cell})"
                # Плиты/кассеты логичнее разделять по типу потолка (армстронг ≠ грильято).
                elif name == "Плиты/кассеты":
                    key = f"{name} ({ceiling})"
                elif name == "Светильники":
                    key = "Светильники"
                totals[key] = int(totals.get(key, 0)) + int(value)

        lines = [
            f"Площадь S: {total_area:.2f} м²",
            f"Периметр P: {total_perimeter_m:.2f} м",
            "",
            "Комплектующие:",
            "",
        ]
        for name in sorted(totals.keys()):
            lines.append(f"{name}: {totals[name]}")
        self.result_label.text = "\n".join(lines)

