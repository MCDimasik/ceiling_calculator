from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.image import Image
from kivy.uix.scrollview import ScrollView
from kivy.uix.spinner import Spinner
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.app import App
from kivy.utils import platform
from models import CeilingLayout
from materials_calculator import (
    calculate_materials,
    room_perimeter_cm,
    room_area_m2,
    room_length_for_rows_cm,
    auto_rows_for_armstrong,
    auto_rows_for_grilyato_classic,
    grilyato_cassette_count,
)
from ui_style import COLORS, apply_btn_style, style_title, wrap_button_text
from ui_style import style_popup_card
from widgets.ui_components import RoundedButton, RoundedLabel, StyledSpinnerOption, SegmentedControl, SwitchRow
from database import update_project_materials_config, update_room_materials_config
import theme


class MaterialsResultScreen(Screen):
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

        main = BoxLayout(orientation="vertical", spacing=dp(2), size_hint=(1, 1))

        # Хедер на экране расчёта материалов: как везде по высоте, но с другими пропорциями по ширине.
        toolbar = BoxLayout(size_hint=(1, None), height=dp(72), padding=(dp(12), dp(6)), spacing=dp(10))
        btn_back = RoundedButton(text="Назад", size_hint=(0.30, 1), font_size=dp(14))
        btn_back.corner_radius = dp(12)
        apply_btn_style(btn_back, role="secondary")
        wrap_button_text(btn_back)
        btn_back.bind(on_press=lambda *_: setattr(self.manager, "current", "materials_rooms"))
        btn_to_layout = RoundedButton(text="Раскладка", size_hint=(0.30, 1), font_size=dp(14))
        btn_to_layout.corner_radius = dp(12)
        apply_btn_style(btn_to_layout, role="secondary")
        wrap_button_text(btn_to_layout)
        btn_to_layout.bind(on_press=lambda *_: setattr(self.manager, "current", "layout"))
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
        toolbar.add_widget(btn_back)
        toolbar.add_widget(btn_to_layout)
        toolbar.add_widget(self.title)

        # Контролы выносим ВНЕ ScrollView, чтобы их не "подбрасывало" по Y
        # при изменении высоты результата/формул.
        controls = BoxLayout(orientation="vertical", size_hint=(1, None), spacing=dp(10), padding=(dp(8), dp(10), dp(8), dp(8)))
        controls.bind(minimum_height=controls.setter("height"))
        # Сегментированный выбор типа потолка
        self.ceiling_tabs = SegmentedControl(
            values=["Армстронг", "Грильято", "GL"],
            selected="Армстронг",
            size_hint=(1, None),
            height=dp(48),
        )
        self.ceiling_tabs.on_change = lambda *_: self._on_ceiling_tab_change()

        # Сегменты для подвеса и ячейки
        self.susp_tabs = SegmentedControl(
            values=["Подвес 0,5", "Подвес 1", "Подвес 1,5"],
            selected="Подвес 0,5",
            size_hint=(1, None),
            height=dp(48),
        )
        self.susp_tabs.on_change = lambda *_: (self._persist_current_config(), self.request_calculate())

        self.cell_tabs = SegmentedControl(
            values=["50x50", "75x75", "100x100"],
            selected="50x50",
            size_hint=(1, None),
            height=dp(48),
        )
        self.cell_tabs.on_change = lambda *_: (self._persist_current_config(), self.request_calculate())

        controls.add_widget(self.ceiling_tabs)
        controls.add_widget(self.susp_tabs)
        controls.add_widget(self.cell_tabs)

        # Пер-комнатный оверрайд конфигурации
        self.override_row = SwitchRow("Индивидуальная конфигурация", size_hint=(1, None), height=dp(40))
        self.override_row.on_toggle = lambda is_on: self._on_override_toggle(is_on)
        controls.add_widget(self.override_row)

        # Вместо "карточек", которые влияют на лейаут и дают съезды/наложения,
        # делаем общий полупрозрачный слой поверх фоновой картинки и под всем UI.
        from kivy.uix.widget import Widget
        from kivy.graphics import Color, Rectangle

        self._bg_mask = Widget(size_hint=(1, 1))
        # Рисуем в canvas.before. Важно: сам виджет-маска должен быть ВЫШЕ фоновой картинки в дереве.
        with self._bg_mask.canvas.before:
            self._mask_color = Color(0, 0, 0, 0)
            self._mask_rect = Rectangle(pos=self._bg_mask.pos, size=self._bg_mask.size)
        self._bg_mask.bind(
            pos=lambda *_: setattr(self._mask_rect, "pos", self._bg_mask.pos),
            size=lambda *_: setattr(self._mask_rect, "size", self._bg_mask.size),
        )
        self._bg_mask._theme_redraw = lambda *_: self._apply_bg()

        # Важно: слой должен быть выше картинки и ниже main
        # Добавляем обычным способом: bg_photo уже добавлена, main добавится позже.
        root.add_widget(self._bg_mask)

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
        self.formulas_visible = False
        footer_btns = BoxLayout(size_hint=(1, None), height=dp(42), spacing=dp(8))
        self.formulas_button = RoundedButton(text="Показать формулы", size_hint=(1, 1), color=COLORS["text"])
        self.formulas_button.corner_radius = dp(14)
        apply_btn_style(self.formulas_button, role="surface")
        wrap_button_text(self.formulas_button)
        self.formulas_button.bind(on_press=lambda *_: self.toggle_formulas())
        self.share_button = RoundedButton(text="Поделиться", size_hint=(None, 1), width=dp(130), color=COLORS["text"])
        self.share_button.corner_radius = dp(14)
        apply_btn_style(self.share_button, role="surface")
        wrap_button_text(self.share_button)
        self.share_button.bind(on_press=lambda *_: self.share_results())
        footer_btns.add_widget(self.formulas_button)
        footer_btns.add_widget(self.share_button)
        self.formulas_label = Label(
            text="",
            color=COLORS["muted"],
            halign="left",
            valign="top",
            text_size=(dp(295), None),
            size_hint_y=None,
            opacity=0,
            height=0,
        )
        self.formulas_label._theme_slot = "muted"
        self.formulas_label.bind(texture_size=lambda inst, size: setattr(inst, "height", size[1] + dp(20) if self.formulas_visible else 0))
        content = BoxLayout(orientation="vertical", padding=dp(8), spacing=dp(8), size_hint_y=None)
        content.bind(minimum_height=content.setter("height"))
        content.add_widget(self.result_label)
        content.add_widget(footer_btns)
        content.add_widget(self.formulas_label)
        scroll = ScrollView(size_hint=(1, 1))
        scroll.add_widget(content)

        main.add_widget(toolbar)
        main.add_widget(controls)
        main.add_widget(scroll)
        root.add_widget(main)
        self.add_widget(root)
        self._toggle_cell_row()

    def _update_title_text_size(self, *_):
        self.title.text_size = (self.title.width - dp(10), self.title.height)

    def _style_spinner(self, spinner):
        spinner.background_normal = ''
        spinner.background_color = COLORS["surface"]
        spinner.color = COLORS["text"]
        spinner.option_cls = StyledSpinnerOption

    def _share_text(self) -> str:
        room = getattr(self.manager, "current_room", None)
        title = room.name if room else "Комната"
        ceiling = getattr(self.ceiling_tabs, "selected", "")
        cell = getattr(self.cell_tabs, "selected", "")

        # Берем то, что уже видит пользователь (включая порядок и форматирование).
        body = (self.result_label.text or "").strip()
        if not body:
            # если еще не рассчитали — попробуем посчитать
            try:
                self.calculate()
                body = (self.result_label.text or "").strip()
            except Exception:
                body = ""

        header_lines = [f"{title}", f"{ceiling}"]
        if cell and ceiling in ("Грильято", "GL"):
            header_lines.append(f"Ячейка {cell}")

        header = "\n".join([x for x in header_lines if x])
        if body:
            return f"{header}\n\n{body}"
        return header

    def share_results(self):
        text = self._share_text()
        if not text:
            return

        # Android: системный chooser "Поделиться"
        if platform == "android":
            try:
                from jnius import autoclass

                Intent = autoclass("android.content.Intent")
                PythonActivity = autoclass("org.kivy.android.PythonActivity")

                intent = Intent()
                intent.setAction(Intent.ACTION_SEND)
                intent.setType("text/plain")
                intent.putExtra(Intent.EXTRA_TEXT, text)

                chooser = Intent.createChooser(intent, "Поделиться")
                PythonActivity.mActivity.startActivity(chooser)
                return
            except Exception:
                # если что-то пошло не так — упадем на fallback ниже
                pass

        # Fallback: копируем в буфер обмена и показываем уведомление
        try:
            from kivy.core.clipboard import Clipboard

            Clipboard.copy(text)
        except Exception:
            pass

        try:
            from kivy.uix.boxlayout import BoxLayout
            from kivy.uix.label import Label
            from widgets.ui_modal import RoundedModal

            card = BoxLayout(orientation="vertical", padding=dp(16), spacing=dp(12))
            msg = Label(
                text="Текст расчёта скопирован в буфер обмена.",
                color=COLORS["text"],
                halign="center",
                valign="middle",
            )
            msg.bind(size=lambda inst, _: setattr(inst, "text_size", (inst.width, None)))
            btn = RoundedButton(text="OK", size_hint=(1, None), height=dp(44))
            btn.corner_radius = dp(14)
            apply_btn_style(btn, role="primary")
            card.add_widget(msg)
            card.add_widget(btn)
            modal = RoundedModal(card, card_size_hint=(0.86, None), card_height_dp=170)
            btn.bind(on_press=lambda *_: modal.dismiss())
            modal.open()
        except Exception:
            pass

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
        self._persist_current_config()
        self.request_calculate()

    def request_calculate(self):
        """
        Автопересчет при изменении конфигурации.
        Делаем debounce на следующий кадр, чтобы:
        - не дергать расчет несколько раз подряд
        - не мешать анимациям/лейауту сегментов
        """
        if self._calc_trigger is not None:
            try:
                Clock.unschedule(self._calc_trigger)
            except Exception:
                pass
        self._calc_trigger = lambda dt: self.calculate()
        Clock.schedule_once(self._calc_trigger, 0)

    def _effective_project_config(self):
        project = getattr(self.manager, "current_project", None)
        ceiling = getattr(project, "materials_ceiling", None) or "Армстронг"
        susp = getattr(project, "materials_susp", None) or "Подвес 0,5"
        cell = getattr(project, "materials_cell", None) or "50x50"
        return ceiling, susp, cell

    def _effective_room_config(self):
        """
        Конфиг, который должен применяться для этой комнаты:
        - если override выключен: берём проектный (и UI тоже управляет проектным)
        - если override включен: берём комнатный, с фолбэком на проектный
        """
        room = getattr(self.manager, "current_room", None)
        p_ceiling, p_susp, p_cell = self._effective_project_config()
        if not room:
            return False, p_ceiling, p_susp, p_cell
        is_override = bool(getattr(room, "materials_override", False))
        if not is_override:
            return False, p_ceiling, p_susp, p_cell
        r_ceiling = getattr(room, "materials_ceiling", None) or p_ceiling
        r_susp = getattr(room, "materials_susp", None) or p_susp
        r_cell = getattr(room, "materials_cell", None) or p_cell
        return True, r_ceiling, r_susp, r_cell

    def _apply_config_to_ui(self, *, override: bool, ceiling: str, susp: str, cell: str):
        self._loading_config = True
        try:
            self.override_row.active = bool(override)
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

    def _persist_current_config(self):
        """Сохранить текущий выбор либо в проект, либо в комнату (если override)."""
        if self._loading_config:
            return
        room = getattr(self.manager, "current_room", None)
        project = getattr(self.manager, "current_project", None)
        ceiling = getattr(self.ceiling_tabs, "selected", None)
        susp = getattr(self.susp_tabs, "selected", None)
        cell = getattr(self.cell_tabs, "selected", None)

        if room and bool(getattr(room, "materials_override", False)):
            room.materials_ceiling = ceiling
            room.materials_susp = susp
            room.materials_cell = cell
            if getattr(room, "id", None):
                update_room_materials_config(room.id, override=True, ceiling=ceiling, susp=susp, cell=cell)
        else:
            if project:
                project.materials_ceiling = ceiling
                project.materials_susp = susp
                project.materials_cell = cell
                if getattr(project, "id", None):
                    update_project_materials_config(project.id, ceiling=ceiling, susp=susp, cell=cell)

    def _on_override_toggle(self, is_on: bool):
        if self._loading_config:
            return
        room = getattr(self.manager, "current_room", None)
        if not room:
            return
        room.materials_override = bool(is_on)
        p_ceiling, p_susp, p_cell = self._effective_project_config()
        if not room.materials_override:
            # При выключении — UI переходит на проектный конфиг, а комнатный конфиг можно сохранить как есть (на будущее).
            if getattr(room, "id", None):
                update_room_materials_config(room.id, override=False, ceiling=getattr(room, "materials_ceiling", None),
                                             susp=getattr(room, "materials_susp", None), cell=getattr(room, "materials_cell", None))
            self._apply_config_to_ui(override=False, ceiling=p_ceiling, susp=p_susp, cell=p_cell)
        else:
            # При включении — стартуем с текущего проектного (чтобы пользователь не начинал с "пустого").
            room.materials_ceiling = getattr(room, "materials_ceiling", None) or p_ceiling
            room.materials_susp = getattr(room, "materials_susp", None) or p_susp
            room.materials_cell = getattr(room, "materials_cell", None) or p_cell
            if getattr(room, "id", None):
                update_room_materials_config(room.id, override=True, ceiling=room.materials_ceiling,
                                             susp=room.materials_susp, cell=room.materials_cell)
            self._apply_config_to_ui(override=True, ceiling=room.materials_ceiling, susp=room.materials_susp, cell=room.materials_cell)
        self.request_calculate()

    def _toggle_cell_row(self):
        is_gr = self.ceiling_tabs.selected in ("Грильято", "GL")
        # Строка всегда на месте (иначе интерфейс "прыгает"), но для Армстронга недоступна и чуть затемнена
        self.cell_tabs.disabled = not is_gr
        self.cell_tabs.opacity = 1.0
        self.cell_tabs.height = dp(48)

    def on_pre_enter(self):
        self._apply_bg()
        room = getattr(self.manager, "current_room", None)
        self.title.text = room.name if room else "Комната не выбрана"
        override, ceiling, susp, cell = self._effective_room_config()
        self._apply_config_to_ui(override=override, ceiling=ceiling, susp=susp, cell=cell)
        self.calculate()

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
        # Общая маска над фоном: в тёмной теме усиливаем читаемость поверх тёмного фото.
        try:
            if hasattr(self, "_mask_color"):
                # Маска нужна только для тёмной темы.
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

    def toggle_formulas(self):
        # Чтобы при изменении высоты блока формул не было даже краткого "мигания" подсветок сегментов
        self.ceiling_tabs.begin_batch()
        self.susp_tabs.begin_batch()
        self.cell_tabs.begin_batch()
        self.formulas_visible = not self.formulas_visible
        self.formulas_button.text = "Скрыть формулы" if self.formulas_visible else "Показать формулы"
        self.formulas_label.opacity = 1 if self.formulas_visible else 0
        self.formulas_label.height = self.formulas_label.texture_size[1] + dp(20) if self.formulas_visible else 0
        self.ceiling_tabs.end_batch()
        self.susp_tabs.end_batch()
        self.cell_tabs.end_batch()

    def calculate(self):
        room = getattr(self.manager, "current_room", None)
        if not room:
            self.result_label.text = "Комната не выбрана"
            return

        layout = CeilingLayout(room)
        layout.calculate_layout()
        type_map = {"Армстронг": "armstrong", "Грильято": "grilyato_classic", "GL": "grilyato_gl"}
        cassette_count = layout.full_tiles + layout.cut_tiles
        calc_type = type_map.get(self.ceiling_tabs.selected, "armstrong")
        if calc_type in ("grilyato_gl", "grilyato_classic"):
            cassette_count = grilyato_cassette_count(room.walls, cassette_count)

        light_count = len(getattr(room, "light_fixtures", []) or [])

        result = calculate_materials(
            ceiling_type=type_map.get(self.ceiling_tabs.selected, "armstrong"),
            walls=room.walls,
            cassette_count=cassette_count,
            rows_3600=None,
            rows_2400=None,
            cell_size=self.cell_tabs.selected,
            light_count=light_count,
        )

        calc_type = type_map.get(self.ceiling_tabs.selected, "armstrong")
        perimeter_m = room_perimeter_cm(room.walls) / 100.0
        area_m2 = room_area_m2(room.walls)
        row_length_m = room_length_for_rows_cm(room.walls) / 100.0
        # Ряды больше не выводим в UI результатов
        rows_3600, rows_2400 = 0, 0

        lines = [
            f"Площадь S: {area_m2:.2f} м²",
            f"Периметр P: {perimeter_m:.2f} м",
            "",
            "Комплектующие:",
            "",
        ]
        # Всё одним списком, без разрывов, в порядке словаря из калькулятора
        for name, value in result.items():
            if name == "Подвес":
                # self.susp_tabs.selected: "Подвес 0,5" -> нужно только число в скобках
                size_txt = self.susp_tabs.selected.replace("Подвес", "").strip()
                lines.append(f"Подвес ({size_txt}): {value}")
            else:
                lines.append(f"{name}: {value}")
        self.result_label.text = "\n".join(lines)

        formula_lines = [
            "Формулы расчета:",
            f"Уголок = ceil(P/3) = ceil({perimeter_m:.2f}/3)",
            "",
        ]
        if calc_type in ("armstrong", "grilyato_gl"):
            formula_lines.extend([
                "Направляющая 3600 = ceil((S * 0.84) / 3.6)",
                "Направляющая 1200 = ceil((S * 1.68) / 1.2)",
                "Направляющая 600 = ceil((S * 0.85) / 0.6)",
                "Подвес = Направляющая 3600 * 4",
            ])
        else:
            formula_lines.extend([
                "Направляющая 2400 = ceil(S * 0.7)",
                "Направляющая 600 = ceil((S * 1.7) / 0.6)",
                "Соединитель = Направляющая 2400",
                "Подвес = Направляющая 2400 * 4",
            ])
        if calc_type in ("grilyato_gl", "grilyato_classic"):
            formula_lines.extend([
                "",
                "Кассеты/решетки (для прямоугольной комнаты):",
                "N = ceil(L/0.6) * ceil(W/0.6) (с центрированием, с учетом подрезки)",
                "",
                "Для ячейки:",
                "50x50  -> Папа/Мама = ceil((S/0.34) * 11)",
                "75x75  -> Папа/Мама = ceil((S/0.34) * 7)",
                "100x100 -> Папа/Мама = ceil((S/0.34) * 5)",
            ])
            if calc_type == "grilyato_gl":
                formula_lines.extend([
                    "Заглушки (GL):",
                    "50x50  -> ceil((Профиль/11) * 4)",
                    "75x75  -> ceil((Профиль/7) * 4)",
                    "100x100 -> ceil((Профиль/5) * 4)",
                ])
        formula_lines.extend([
            "",
            "Светильники (на раскладке):",
            "Армстронг: −1 плита на светильник",
            "Грильято: −k профилей Папа/Мама (50→11, 75→7, 100→5)",
        ])

        self.formulas_label.text = "\n".join(formula_lines)
        if self.formulas_visible:
            self.formulas_label.height = self.formulas_label.texture_size[1] + dp(20)

        # После успешного расчёта фиксируем выбор в БД (если пользователь менял конфиг).
        self._persist_current_config()
