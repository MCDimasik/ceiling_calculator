from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.spinner import SpinnerOption
from kivy.uix.widget import Widget
from kivy.uix.boxlayout import BoxLayout
from kivy.properties import ListProperty, NumericProperty, StringProperty, BooleanProperty, ObjectProperty
from kivy.graphics import Color, RoundedRectangle, Line, Ellipse
from kivy.graphics.instructions import InstructionGroup


class SegmentedControl(BoxLayout):
    """
    Сегментированный контрол на 3 пункта с анимированной подсветкой.
    Используется на экране материалов: Armstrong / Grilyato / GL.
    """

    values = ListProperty([])
    selected = StringProperty("")
    on_change = ObjectProperty(None, allownone=True)
    disabled = BooleanProperty(False)
    height_dp = NumericProperty(48.0)
    corner_radius_dp = NumericProperty(16.0)

    def __init__(self, **kwargs):
        from kivy.metrics import dp
        from ui_style import COLORS, apply_btn_style, wrap_button_text
        from kivy.animation import Animation

        super().__init__(orientation="horizontal", spacing=0, **kwargs)
        self.size_hint = kwargs.get("size_hint", (1, None))
        self.height = dp(kwargs.get("height_dp", self.height_dp))
        self.padding = (0, 0, 0, 0)

        self._highlight = RoundedRectangle(pos=self.pos, size=(0, 0), radius=[(dp(self.corner_radius_dp), dp(self.corner_radius_dp))] * 4)
        self._highlight_color = Color(0, 0, 0, 0)

        with self.canvas.before:
            # background
            self._bg_color = Color(*COLORS["surface"])
            self._bg_rect = RoundedRectangle(pos=self.pos, size=self.size, radius=[(dp(self.corner_radius_dp), dp(self.corner_radius_dp))] * 4)
            # highlight (drawn above bg)
            self._highlight_color = Color(COLORS["primary"][0], COLORS["primary"][1], COLORS["primary"][2], 0.16)
            self._highlight = RoundedRectangle(pos=self.pos, size=(0, 0), radius=[(dp(self.corner_radius_dp), dp(self.corner_radius_dp))] * 4)

        self._anim = None
        self._Animation = Animation
        self._btns = []
        self._animate_next = False
        self._suppress_highlight = False
        self._needs_layout_sync = True
        self._theme_redraw = self._apply_theme

        self.bind(pos=self._redraw, size=self._redraw, values=self._rebuild, selected=self._sync_highlight, disabled=self._sync_disabled)
        self._rebuild()

    def _apply_theme(self, *_):
        """Обновить цвета при смене темы (COLORS меняется глобально)."""
        from ui_style import COLORS

        self._bg_color.rgba = COLORS["surface"]
        self._highlight_color.rgba = (COLORS["primary"][0], COLORS["primary"][1], COLORS["primary"][2], 0.16)
        for b in getattr(self, "_btns", []):
            try:
                b.color = COLORS["muted"] if self.disabled else COLORS["text"]
            except Exception:
                pass
        try:
            self._trigger_layout()
        except Exception:
            pass

    def _rebuild(self, *_):
        from ui_style import apply_btn_style, wrap_button_text, COLORS
        from kivy.metrics import dp

        self.clear_widgets()
        self._btns = []

        vals = list(self.values) if self.values else []
        if not vals:
            return

        if not self.selected:
            self.selected = vals[0]

        for v in vals:
            b = RoundedButton(text=v, size_hint=(1, 1), font_size=dp(15))
            b.corner_radius = dp(0)  # corners handled by container/highlight
            # Внутренний сегмент: прозрачный, без бордера (иначе после смены темы refresh_widget_tree
            # снова проставляет бордеры и "прямоугольные" рамки возвращаются).
            apply_btn_style(b, role="seg")
            wrap_button_text(b, horizontal_padding_dp=6)
            b.bind(on_press=lambda inst, vv=v: self._select(vv))
            # При любых ре-лейаутах (например, разворачивание "формул") подсветка должна оставаться под выбранным сегментом.
            b.bind(pos=self._sync_highlight, size=self._sync_highlight)
            b.disabled = bool(self.disabled)
            self._btns.append(b)
            self.add_widget(b)

        self._redraw()
        # После первой реальной раскладки поставим подсветку без анимации.
        self._highlight.size = (0, 0)
        self._sync_disabled()
        self._needs_layout_sync = True
        self._sync_highlight(initial=True)

    def _select(self, value: str):
        if self.disabled:
            return
        if value == self.selected:
            return
        self._animate_next = True
        self.selected = value
        cb = self.on_change
        if cb:
            cb(value)

    def set_selected(self, value: str, *, animate: bool = False):
        """
        Программно выбрать сегмент.
        По умолчанию без анимации (чтобы не было "миганий" при переразметке экрана).
        """
        if value == self.selected:
            return
        self._animate_next = bool(animate)
        self.selected = value

    def begin_batch(self):
        """Отключить дерганья подсветки на время серии обновлений UI."""
        self._suppress_highlight = True

    def end_batch(self):
        """Включить подсветку и принудительно поставить её на выбранный сегмент."""
        self._suppress_highlight = False
        # Не двигаем подсветку сразу: дожидаемся следующего do_layout(),
        # чтобы брать финальные pos/size после всех перестроений экрана.
        self._needs_layout_sync = True
        try:
            self._trigger_layout()
        except Exception:
            pass

    def _redraw(self, *_):
        from kivy.metrics import dp
        from ui_style import COLORS

        # Каплевидная форма: радиус = половина высоты (но не меньше заданного corner_radius_dp)
        r = max(dp(self.corner_radius_dp), self.height / 2.0)
        self._bg_rect.pos = self.pos
        self._bg_rect.size = self.size
        self._bg_rect.radius = [(r, r)] * 4
        self._bg_color.rgba = COLORS["surface"]
        self._highlight.radius = [(r, r)] * 4
        self._highlight_color.rgba = (COLORS["primary"][0], COLORS["primary"][1], COLORS["primary"][2], 0.16)

    def _sync_highlight(self, *_, initial: bool = False):
        if getattr(self, "_suppress_highlight", False):
            return
        # Не двигаем подсветку прямо здесь: дождемся do_layout(), чтобы избежать "миганий"
        # из-за промежуточных размеров/позиций детей при переразметке экрана.
        self._needs_layout_sync = True
        # Важно: если больше ничего на экране не меняется, do_layout может не вызваться сразу.
        # Запрашиваем переразметку, чтобы подсветка среагировала на клик моментально.
        try:
            self._trigger_layout()
        except Exception:
            pass

    def _move_highlight(self, *, animated: bool):
        if not self._btns:
            return
        idx = 0
        for i, b in enumerate(self._btns):
            if b.text == self.selected:
                idx = i
                break
        b = self._btns[idx]
        target_pos = b.pos
        target_size = b.size
        if target_size[0] <= 0 or target_size[1] <= 0:
            return

        if not animated:
            self._highlight.pos = target_pos
            self._highlight.size = target_size
            return

        if self._anim is not None:
            try:
                self._anim.cancel(self._highlight)
            except Exception:
                pass
        # Чуть более "жидкое" перетекание
        self._anim = self._Animation(pos=target_pos, size=target_size, duration=0.22, t="out_cubic")
        self._anim.start(self._highlight)

    def _sync_disabled(self, *_):
        from ui_style import COLORS
        # В неактивном состоянии слегка "гасим" сегменты и подсветку
        for b in getattr(self, "_btns", []):
            b.disabled = bool(self.disabled)
            b.color = COLORS["muted"] if self.disabled else COLORS["text"]
        if self.disabled:
            self._highlight_color.rgba = (COLORS["primary"][0], COLORS["primary"][1], COLORS["primary"][2], 0.08)
        else:
            self._highlight_color.rgba = (COLORS["primary"][0], COLORS["primary"][1], COLORS["primary"][2], 0.16)

    def on_touch_down(self, touch):
        # Блокируем тапы по сегментам, когда disabled, чтобы не "прыгало" состояние.
        if self.disabled and self.collide_point(*touch.pos):
            return True
        return super().on_touch_down(touch)

    def do_layout(self, *largs):
        super().do_layout(*largs)
        if getattr(self, "_suppress_highlight", False):
            return

        # Во время анимации (особенно внутри ScrollView) контент может сдвигаться по Y,
        # из-за чего подсветка визуально "прыгает" вверх-вниз. Прибиваем Y/высоту подсветки
        # к выбранной кнопке на каждом layout-проходе, оставляя анимацию только по X/ширине.
        if self._anim is not None and self._btns:
            idx = 0
            for i, b in enumerate(self._btns):
                if b.text == self.selected:
                    idx = i
                    break
            b = self._btns[idx]
            try:
                self._highlight.pos = (self._highlight.pos[0], b.pos[1])
                self._highlight.size = (self._highlight.size[0], b.size[1])
            except Exception:
                pass

        if not getattr(self, "_needs_layout_sync", False):
            return

        # Анимируем только реальный тап по этому контролу
        animated = bool(self._animate_next)
        # если подсветка еще не установлена — ставим без анимации
        if self._highlight.size == (0, 0):
            animated = False
        self._animate_next = False
        self._needs_layout_sync = False
        self._move_highlight(animated=animated)


class RoundedButton(Button):
    bg_color = ListProperty([0.84, 0.88, 0.94, 1])
    border_color = ListProperty([0, 0, 0, 0])
    border_width = NumericProperty(0.0)
    corner_radius = NumericProperty(16.0)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.background_normal = ""
        self.background_down = ""
        self.background_color = (0, 0, 0, 0)
        self.bind(
            pos=self._redraw,
            size=self._redraw,
            bg_color=self._redraw,
            border_color=self._redraw,
            border_width=self._redraw,
            corner_radius=self._redraw,
        )
        self._redraw()

    def _redraw(self, *args):
        self.canvas.before.clear()
        self.canvas.after.clear()
        r = float(self.corner_radius)
        radius = [(r, r), (r, r), (r, r), (r, r)]
        with self.canvas.before:
            Color(*self.bg_color)
            RoundedRectangle(pos=self.pos, size=self.size, radius=radius)
        if self.border_width > 0:
            with self.canvas.after:
                Color(*self.border_color)
                Line(
                    rounded_rectangle=(self.x, self.y, self.width, self.height, self.corner_radius),
                    width=self.border_width,
                )


class RoundedLabel(Label):
    bg_color = ListProperty([0.94, 0.96, 0.99, 1])
    corner_radius = NumericProperty(14.0)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.bind(pos=self._redraw, size=self._redraw, bg_color=self._redraw, corner_radius=self._redraw)
        self.bind(color=lambda *a: self.texture_update())
        self._redraw()

    def _redraw(self, *args):
        self.canvas.before.clear()
        r = float(self.corner_radius)
        radius = [(r, r), (r, r), (r, r), (r, r)]
        with self.canvas.before:
            Color(*self.bg_color)
            RoundedRectangle(pos=self.pos, size=self.size, radius=radius)


class StyledSpinnerOption(SpinnerOption):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.background_normal = ""
        self.background_down = ""
        self.background_color = (0, 0, 0, 0)
        self.color = (0.1, 0.14, 0.2, 1)
        self.halign = "left"
        self.valign = "middle"
        self.padding = [12, 10, 12, 10]
        self.bind(
            pos=self._redraw,
            size=self._redraw,
            state=self._redraw,
        )
        self._redraw()

    def _redraw(self, *args):
        from ui_style import COLORS

        self.canvas.before.clear()
        # Небольшие внутренние отступы дают "разделенность" пунктов списка
        x = self.x + 3
        y = self.y + 3
        w = max(0, self.width - 6)
        h = max(0, self.height - 6)
        if self.state != "down":
            fill = COLORS["surface"]
        else:
            fill = COLORS.get("spinner_option_down", (0.86, 0.91, 0.98, 1))
        with self.canvas.before:
            Color(*fill)
            RoundedRectangle(pos=(x, y), size=(w, h), radius=[(10, 10)] * 4)

from kivy.uix.behaviors import ButtonBehavior
from kivy.uix.image import Image

class ImageButton(ButtonBehavior, Image):
    def on_state(self, instance, value):
        if value == 'down':
            self.opacity = 0.7
        else:
            self.opacity = 1.0


class IconRoundedButton(RoundedButton):
    icon_type = StringProperty("plus")  # plus, minus, left, right, up, down
    icon_color = ListProperty([0.05, 0.2, 0.45, 1])
    icon_width = NumericProperty(3.2)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.text = ""
        self._icon_group = InstructionGroup()
        self.canvas.add(self._icon_group)
        self.bind(
            pos=self._redraw_icon,
            size=self._redraw_icon,
            icon_type=self._redraw_icon,
            icon_color=self._redraw_icon,
            icon_width=self._redraw_icon,
            bg_color=self._redraw_icon,
            corner_radius=self._redraw_icon,
        )
        self._redraw_icon()

    def _redraw_icon(self, *args):
        self._icon_group.clear()
        cx = self.x + self.width / 2.0
        cy = self.y + self.height / 2.0
        w = self.width
        h = self.height
        s = min(w, h) * 0.28
        self._icon_group.add(Color(*self.icon_color))
        if self.icon_type == "plus":
            self._icon_group.add(Line(points=[cx - s, cy, cx + s, cy], width=self.icon_width))
            self._icon_group.add(Line(points=[cx, cy - s, cx, cy + s], width=self.icon_width))
        elif self.icon_type == "minus":
            self._icon_group.add(Line(points=[cx - s, cy, cx + s, cy], width=self.icon_width))
        elif self.icon_type == "left":
            # Сильно вытянутая по горизонтали стрелка влево
            self._icon_group.add(Line(points=[cx + s * 1.65, cy, cx - s * 1.55, cy], width=self.icon_width))
            self._icon_group.add(Line(points=[cx - s * 1.55, cy, cx - s * 0.55, cy + s * 0.75], width=self.icon_width))
            self._icon_group.add(Line(points=[cx - s * 1.55, cy, cx - s * 0.55, cy - s * 0.75], width=self.icon_width))
        elif self.icon_type == "right":
            # Сильно вытянутая по горизонтали стрелка вправо
            self._icon_group.add(Line(points=[cx - s * 1.65, cy, cx + s * 1.55, cy], width=self.icon_width))
            self._icon_group.add(Line(points=[cx + s * 1.55, cy, cx + s * 0.55, cy + s * 0.75], width=self.icon_width))
            self._icon_group.add(Line(points=[cx + s * 1.55, cy, cx + s * 0.55, cy - s * 0.75], width=self.icon_width))
        elif self.icon_type == "up":
            self._icon_group.add(Line(points=[cx, cy - s * 0.8, cx, cy + s * 0.8], width=self.icon_width))
            self._icon_group.add(Line(points=[cx, cy + s * 0.8, cx - s * 0.65, cy + s * 0.15], width=self.icon_width))
            self._icon_group.add(Line(points=[cx, cy + s * 0.8, cx + s * 0.65, cy + s * 0.15], width=self.icon_width))
        elif self.icon_type == "down":
            self._icon_group.add(Line(points=[cx, cy + s * 0.8, cx, cy - s * 0.8], width=self.icon_width))
            self._icon_group.add(Line(points=[cx, cy - s * 0.8, cx - s * 0.65, cy - s * 0.15], width=self.icon_width))
            self._icon_group.add(Line(points=[cx, cy - s * 0.8, cx + s * 0.65, cy - s * 0.15], width=self.icon_width))


class CeilingLogo(Widget):
    """
    Временный векторный логотип (без картинок):
    - карточка со скруглением
    - «сеточка потолка» линиями
    - акцентная вертикальная планка
    """

    corner_radius = NumericProperty(18.0)
    stroke_width = NumericProperty(2.2)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.bind(pos=self._redraw, size=self._redraw, corner_radius=self._redraw, stroke_width=self._redraw)
        # Для Theme.refresh_widget_tree — перерисовать при смене COLORS
        self._theme_redraw = self._redraw
        self._redraw()

    def _redraw(self, *_):
        from kivy.metrics import dp
        from ui_style import COLORS

        self.canvas.before.clear()
        self.canvas.after.clear()

        r = float(self.corner_radius)
        radius = [(r, r), (r, r), (r, r), (r, r)]

        pad = dp(8)
        x = self.x + pad
        y = self.y + pad
        w = max(0, self.width - pad * 2)
        h = max(0, self.height - pad * 2)

        with self.canvas.before:
            Color(*COLORS["surface"])
            RoundedRectangle(pos=(x, y), size=(w, h), radius=radius)

        # Рисуем «сетку» и акцент поверх
        with self.canvas.after:
            Color(*COLORS["muted"])
            sw = float(self.stroke_width)

            # Внутренний прямоугольник с небольшими полями
            ix = x + dp(10)
            iy = y + dp(10)
            iw = max(0, w - dp(20))
            ih = max(0, h - dp(20))

            # Горизонтальные линии
            for t in (0.30, 0.55, 0.78):
                yy = iy + ih * t
                Line(points=[ix, yy, ix + iw, yy], width=sw)

            # Вертикальные линии
            for t in (0.25, 0.50, 0.75):
                xx = ix + iw * t
                Line(points=[xx, iy, xx, iy + ih], width=sw)

            # Акцентная «несущая» планка
            Color(*COLORS["primary"])
            ax = ix + iw * 0.12
            Line(points=[ax, iy, ax, iy + ih], width=max(sw * 1.6, 3.0))


class ThemeSwitch(Widget):
    """Кастомный переключатель (как в Figma): трек + бегунок."""

    active = BooleanProperty(False)
    on_toggle = ObjectProperty(None, allownone=True)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.size_hint = kwargs.get("size_hint", (None, None))
        self.size = kwargs.get("size", (36, 20))
        self.bind(pos=self._redraw, size=self._redraw, active=self._redraw)
        self._theme_redraw = self._redraw
        self._redraw()

    def _redraw(self, *_):
        from kivy.metrics import dp
        from ui_style import COLORS

        self.canvas.clear()
        # Рисуем по "целым" пикселям, чтобы не было мыла/неровностей на Windows.
        def px(v: float) -> float:
            return float(int(v + 0.5))

        x, y = self.pos
        w, h = self.size
        x = px(x)
        y = px(y)
        w = px(w)
        h = px(h)

        # Радиусы и размеры — строго от h
        pad = px(dp(2))
        track_r = px(h / 2.0)
        knob_d = px(max(0.0, h - pad * 2))
        knob_r = px(knob_d / 2.0)

        track = COLORS["primary"] if self.active else (0.85, 0.85, 0.85, 1)
        with self.canvas:
            Color(*track)
            RoundedRectangle(pos=(x, y), size=(w, h), radius=[(track_r, track_r)] * 4)
            Color(1, 1, 1, 1)
            if not self.active:
                kx = x + pad
            else:
                kx = x + w - pad - knob_d
            ky = y + (h - knob_d) / 2.0
            kx = px(kx)
            ky = px(ky)
            Ellipse(pos=(kx, ky), size=(knob_d, knob_d))

    def on_touch_down(self, touch):
        if not self.collide_point(*touch.pos):
            return super().on_touch_down(touch)
        self.active = not self.active
        cb = self.on_toggle
        if cb:
            cb(self.active)
        return True


class SwitchRow(BoxLayout):
    """Строка настройки: текст слева, ThemeSwitch справа."""

    active = BooleanProperty(False)
    on_toggle = ObjectProperty(None, allownone=True)

    def __init__(self, text: str, **kwargs):
        from kivy.metrics import dp
        from ui_style import COLORS

        super().__init__(orientation="horizontal", spacing=dp(12), **kwargs)
        self.size_hint = kwargs.get("size_hint", (1, None))
        self.height = kwargs.get("height", dp(40))

        self._label = Label(
            text=text,
            color=COLORS["text"],
            font_size=dp(16),
            halign="left",
            valign="middle",
            size_hint=(1, 1),
        )
        self._label.bind(size=lambda inst, _: setattr(inst, "text_size", (inst.width, None)))
        self.add_widget(self._label)

        self._switch = ThemeSwitch(size=(dp(36), dp(20)), size_hint=(None, None))
        self._switch.on_toggle = self._on_switch
        wrap = BoxLayout(orientation="vertical", size_hint=(None, 1), width=dp(36))
        wrap.add_widget(Widget(size_hint=(1, None), height=(self.height - dp(20)) / 2.0))
        wrap.add_widget(self._switch)
        wrap.add_widget(Widget(size_hint=(1, None), height=(self.height - dp(20)) / 2.0))
        self.add_widget(wrap)

        self.bind(active=self._sync)
        self._sync()

    def _sync(self, *_):
        self._switch.active = bool(self.active)

    def _on_switch(self, is_active: bool):
        self.active = bool(is_active)
        cb = self.on_toggle
        if cb:
            cb(self.active)


class ThemeToggleRow(BoxLayout):
    """
    Ряд «Dark Mood»: слева иконка луны в кружке + текст, справа ThemeSwitch.
    Сделано как готовый компонент, чтобы легко использовать в SettingsScreen.
    """

    active = BooleanProperty(False)
    on_toggle = ObjectProperty(None, allownone=True)

    def __init__(self, text="Тёмная тема", **kwargs):
        from kivy.metrics import dp
        from ui_style import COLORS

        super().__init__(orientation="horizontal", spacing=dp(12), **kwargs)
        self.size_hint = kwargs.get("size_hint", (1, None))
        self.height = kwargs.get("height", dp(40))
        self.padding = (0, 0, 0, 0)

        # Left group: icon + label
        left = BoxLayout(orientation="horizontal", spacing=dp(12), size_hint=(1, 1))
        self.add_widget(left)

        self._icon_wrap = Widget(size_hint=(None, None), size=(dp(40), dp(40)))
        self._icon_wrap._theme_redraw = lambda *_: self._redraw_icon(self._icon_wrap)
        self._icon_wrap.bind(pos=lambda *_: self._redraw_icon(self._icon_wrap), size=lambda *_: self._redraw_icon(self._icon_wrap))
        left.add_widget(self._icon_wrap)

        self._label = Label(
            text=text,
            color=COLORS["text"],
            font_size=dp(16),
            halign="left",
            valign="middle",
            size_hint=(1, 1),
        )
        self._label.bind(size=lambda inst, _: setattr(inst, "text_size", (inst.width, None)))
        left.add_widget(self._label)

        # Right: switch
        self._switch = ThemeSwitch(size=(dp(36), dp(20)), size_hint=(None, None))
        self._switch.on_toggle = self._on_switch
        # vertically center
        wrap = BoxLayout(orientation="vertical", size_hint=(None, 1), width=dp(36))
        wrap.add_widget(Widget(size_hint=(1, None), height=(self.height - dp(20)) / 2.0))
        wrap.add_widget(self._switch)
        wrap.add_widget(Widget(size_hint=(1, None), height=(self.height - dp(20)) / 2.0))
        self.add_widget(wrap)

        self._theme_redraw = self._sync
        self.bind(active=self._sync)
        self._sync()

    def _sync(self, *_):
        self._switch.active = bool(self.active)
        if hasattr(self, "_icon_wrap") and self._icon_wrap is not None:
            self._redraw_icon(self._icon_wrap)

    def _on_switch(self, is_active: bool):
        self.active = bool(is_active)
        cb = self.on_toggle
        if cb:
            cb(self.active)

    def _redraw_icon(self, wrap: Widget):
        from kivy.metrics import dp
        from ui_style import COLORS

        wrap.canvas.clear()
        x, y = wrap.pos
        w, h = wrap.size

        # background circle
        # В тёмной теме: светлая заливка, тёмная луна (как просили).
        is_dark = COLORS.get("bg", (1, 1, 1, 1))[0] < 0.2
        bg = (0.95, 0.96, 0.98, 0.85) if is_dark else (COLORS["primary"][0], COLORS["primary"][1], COLORS["primary"][2], 0.15)
        with wrap.canvas:
            Color(*bg)
            Ellipse(pos=(x, y), size=(w, h))

            # Рисуем ИСХОДНЫЙ PNG-значок луны без искажений цвета.
            try:
                from kivy.resources import resource_find
                from kivy.core.image import Image as CoreImage
                from kivy.graphics import Rectangle

                png_path = resource_find("assets/moon.png")
                if not png_path:
                    raise RuntimeError("moon.png not found")

                target = float(dp(24))
                ix = x + (w - target) / 2.0
                iy = y + (h - target) / 2.0
                img = CoreImage(png_path)
                # В тёмной теме делаем контур луны тёмным.
                (Color(0, 0, 0, 0.82) if is_dark else Color(*COLORS["text"]))
                Rectangle(pos=(ix, iy), size=(target, target), texture=img.texture)
            except Exception:
                # fallback crescent (на случай если png не найден)
                (Color(0, 0, 0, 0.82) if is_dark else Color(*COLORS["text"]))
                cx = x + w / 2.0
                cy = y + h / 2.0
                ro = min(w, h) * 0.32
                ri = ro * 0.78
                dx = ro * 0.38

                def arc_points(cax, cay, r, a0, a1, steps=32):
                    import math
                    pts = []
                    for i in range(steps + 1):
                        t = i / float(steps)
                        a = a0 + (a1 - a0) * t
                        pts.extend([cax + math.cos(a) * r, cay + math.sin(a) * r])
                    return pts

                import math
                a0 = math.radians(-135)
                a1 = math.radians(135)
                outer = arc_points(cx, cy, ro, a0, a1, steps=40)
                inner = arc_points(cx + dx, cy, ri, a1, a0, steps=40)
                Line(points=outer + inner, width=dp(1.5), close=True, cap="round", joint="round")

