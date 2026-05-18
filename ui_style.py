from kivy.metrics import dp

# Высота строки ввода в модалках и высота кнопок «Отмена» / «Подтвердить» (одинаковые).
MODAL_INPUT_ROW_HEIGHT_DP = 48
MODAL_ACTION_BTN_HEIGHT_DP = MODAL_INPUT_ROW_HEIGHT_DP

# Единый хедер по всему приложению
TOOLBAR_HEIGHT_DP = 52
TOOLBAR_PADDING_DP = 10
TOOLBAR_SPACING_DP = 10
TOOLBAR_BTN_RADIUS_DP = 14
TOOLBAR_BTN_FONT_DP = 14
TOOLBAR_TITLE_FONT_DP = 16


COLORS = {
    "bg": (0.97, 0.98, 1.0, 1),
    "text": (0.1, 0.14, 0.2, 1),
    "muted": (0.45, 0.5, 0.6, 1),
    "surface": (0.94, 0.96, 0.99, 1),
    "surface_alt": (0.97, 0.97, 0.98, 1),
    "border": (0.85, 0.84, 0.85, 1),
    "primary": (0.22, 0.52, 0.96, 1),
    "primary_alt": (0.3, 0.62, 0.98, 1),
    "danger": (0.87, 0.33, 0.33, 1),
    "secondary_fill": (0.84, 0.88, 0.94, 1),
    "title_bar": (0.94, 0.96, 0.99, 1),
    "spinner_option_down": (0.86, 0.91, 0.98, 1),
    "selection": (0.22, 0.52, 0.96, 0.35),
    "overlay": (0, 0, 0, 0.18),
}


def apply_btn_style(btn, *, role="secondary"):
    btn._ui_btn_role = role
    btn.background_normal = ""
    btn.background_down = ""
    if role == "seg":
        # Сегменты внутри SegmentedControl: прозрачные, без бордера (капля рисуется контейнером).
        btn.color = COLORS["text"]
        if hasattr(btn, "border_width") and hasattr(btn, "border_color"):
            btn.border_width = 0.0
            btn.border_color = (0, 0, 0, 0)
        if hasattr(btn, "bg_color"):
            btn.bg_color = (0, 0, 0, 0)
            btn.background_color = (0, 0, 0, 0)
        else:
            btn.background_color = (0, 0, 0, 0)
        return

    btn.color = COLORS["text"] if role in ("secondary", "surface") else (1, 1, 1, 1)
    if role == "primary":
        fill = COLORS["primary"]
    elif role == "danger":
        fill = COLORS["danger"]
    elif role == "surface":
        fill = COLORS["surface"]
    else:
        fill = COLORS.get("secondary_fill", COLORS["surface_alt"])

    # Light theme: secondary buttons should never look "dark"
    if role == "secondary" and COLORS.get("bg", (1, 1, 1, 1))[0] > 0.5:
        fill = COLORS.get("secondary_fill", COLORS["surface_alt"])

    # Borders: secondary/surface look better on photo backgrounds with a thin border
    if hasattr(btn, "border_width") and hasattr(btn, "border_color"):
        if role in ("secondary", "surface"):
            btn.border_width = dp(1.2)
            btn.border_color = COLORS.get("border", (0, 0, 0, 0))
        else:
            btn.border_width = 0.0
            btn.border_color = (0, 0, 0, 0)

    # Для кастомных круглых кнопок рисуем цвет через bg_color,
    # а стандартный фон Button оставляем прозрачным.
    if hasattr(btn, "bg_color"):
        btn.bg_color = fill
        btn.background_color = (0, 0, 0, 0)
    else:
        btn.background_color = fill


def style_title(label):
    label.color = COLORS["text"]
    if hasattr(label, "bg_color"):
        label.bg_color = list(COLORS.get("surface", (1, 1, 1, 1)))


def screen_padding():
    return dp(10)


def wrap_button_text(btn, horizontal_padding_dp=10):
    btn.halign = "center"
    btn.valign = "middle"
    btn.bind(size=lambda inst, size: setattr(inst, "text_size", (max(0, size[0] - dp(horizontal_padding_dp)), size[1])))


def fit_button_font(btn, *, max_font_dp=14, min_font_dp=11, horizontal_padding_dp=10):
    """
    Подгоняет font_size под текущую ширину кнопки, чтобы текст не выглядел "сжатым".
    Работает лучше всего для коротких надписей в одну строку (хедеры).
    """

    def _fit(*_):
        try:
            w = float(btn.width)
            if w <= 0:
                return
            txt = (btn.text or "").replace("\n", " ").strip()
            if not txt:
                return
            # грубая оценка: средняя ширина символа ~0.58*font_size
            avail = max(1.0, w - dp(horizontal_padding_dp) * 2)
            target = avail / (max(1, len(txt)) * 0.58)
            fs = max(dp(min_font_dp), min(dp(max_font_dp), target))
            btn.font_size = fs
            btn.text_size = (avail, btn.height)
        except Exception:
            pass

    btn.bind(size=_fit, text=_fit)
    _fit()


def style_text_input(text_input):
    text_input.background_normal = ""
    text_input.background_active = ""
    text_input.background_color = COLORS.get("surface_alt", COLORS["surface"])
    text_input.foreground_color = COLORS["text"]
    text_input.hint_text_color = COLORS["muted"]
    text_input.selection_color = COLORS.get("selection", (0.22, 0.52, 0.96, 0.35))
    text_input.cursor_color = COLORS["text"]
    text_input.padding = (dp(10), dp(10))


def format_number_ru(value, decimals=0):
    """Разделитель тысяч — пробел; дробная часть — запятая (45 865,50)."""
    try:
        n = float(value)
    except (TypeError, ValueError):
        return str(value)
    negative = n < 0
    n = abs(n)
    if decimals > 0:
        scale = 10**decimals
        int_part = int(n)
        frac = int(round((n - int_part) * scale + 1e-9))
        if frac >= scale:
            int_part += 1
            frac = 0
        int_s = f"{int_part:,}".replace(",", " ")
        body = f"{int_s},{frac:0{decimals}d}"
    else:
        body = f"{int(round(n)):,}".replace(",", " ")
    return f"-{body}" if negative else body


def format_money_ru(value):
    return f"{format_number_ru(value, 2)} ₽"


def bind_label_autosize(label, min_height_dp=22, pad_dp=8):
    """Подгоняет высоту Label под перенос строк (без наезда на соседей)."""
    label.size_hint_y = None

    def _refresh(*_):
        if label.width < dp(8):
            return
        label.text_size = (label.width - dp(4), None)
        label.texture_update()
        th = label.texture_size[1] if label.texture_size else 0
        label.height = max(dp(min_height_dp), th + dp(pad_dp))

    label.bind(size=_refresh, text=_refresh)
    from kivy.clock import Clock

    Clock.schedule_once(lambda *_: _refresh(), 0)
    return _refresh


def make_price_input(hint_text="", font_size_dp=14, height_dp=42):
    """Поле цены с достаточной высотой, чтобы цифры не обрезались."""
    from kivy.uix.textinput import TextInput

    field = TextInput(
        multiline=False,
        hint_text=hint_text,
        font_size=dp(font_size_dp),
        input_filter="float",
        size_hint_y=None,
        height=dp(height_dp),
    )
    style_text_input(field)
    field.padding = (dp(10), dp(11))
    return field


def make_input_row(text_input, height_dp=None, radius_dp=14, border_rgba=None):
    """
    Обертка для TextInput, чтобы поле ввода было визуально заметно:
    скругление + тонкая обводка.
    """
    from kivy.uix.floatlayout import FloatLayout
    from kivy.graphics import Color, RoundedRectangle, Line

    if height_dp is None:
        height_dp = MODAL_INPUT_ROW_HEIGHT_DP
    wrapper = FloatLayout(size_hint=(1, None), height=dp(height_dp))
    r = dp(radius_dp)

    def redraw(*_):
        wrapper.canvas.before.clear()
        with wrapper.canvas.before:
            Color(*COLORS.get("surface_alt", COLORS["surface"]))
            RoundedRectangle(pos=wrapper.pos, size=wrapper.size, radius=[(r, r)] * 4)
            br = border_rgba if border_rgba is not None else COLORS.get("border", (0.22, 0.52, 0.96, 0.55))
            Color(*br)
            Line(rounded_rectangle=(wrapper.x, wrapper.y, wrapper.width, wrapper.height, r), width=1.2)

    wrapper.bind(pos=redraw, size=redraw)
    redraw()
    wrapper._theme_redraw = redraw

    # Fit input inside wrapper with padding; фон поля прозрачный — заливка и обводка от обёртки.
    text_input.size_hint = (1, 1)
    text_input.pos_hint = {"x": 0, "y": 0}
    text_input.background_color = (0, 0, 0, 0)
    wrapper.add_widget(text_input)
    return wrapper


def style_popup(popup):
    popup.separator_color = COLORS["primary"]
    popup.background = ""
    # Делаем фон popup прозрачным и рисуем "карточку" внутри контента.
    popup.background_color = (0, 0, 0, 0)


def configure_modal_footer_buttons(btn_layout, *buttons):
    """
    Ряд кнопок внизу модалки: та же высота, что у строки ввода (MODAL_INPUT_ROW_HEIGHT_DP).
    """
    h = dp(MODAL_ACTION_BTN_HEIGHT_DP)
    btn_layout.size_hint = (1, None)
    btn_layout.height = h
    n = max(len(buttons), 1)
    w = 1.0 / n
    fs = dp(15)
    for btn in buttons:
        btn.size_hint = (w, None)
        btn.height = h
        btn.font_size = fs
        if hasattr(btn, "corner_radius"):
            btn.corner_radius = dp(12)


def style_popup_card(container, radius_dp=16):
    from kivy.graphics import Color, RoundedRectangle
    r = dp(radius_dp)

    def redraw(*_):
        container.canvas.before.clear()
        with container.canvas.before:
            Color(*COLORS["surface"])
            RoundedRectangle(pos=container.pos, size=container.size, radius=[(r, r)] * 4)

    container.bind(pos=redraw, size=redraw)
    redraw()
    container._theme_redraw = redraw
