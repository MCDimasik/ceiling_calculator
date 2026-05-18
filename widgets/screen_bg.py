"""Общий фон экрана (как на экранах материалов)."""
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.image import Image
from kivy.app import App

import theme


def make_bg_root(dim_mask=False):
    """
    Фон с cover-картинкой по теме.
    dim_mask=True — полупрозрачное затемнение поверх фото (как на расчёте материалов).
    """
    root = FloatLayout()
    bg = Image(source="assets/bg_light.png", allow_stretch=True, keep_ratio=True)
    bg.size_hint = (None, None)
    bg.pos = (0, 0)
    bg.size = root.size
    bg.opacity = 0
    root.add_widget(bg)
    root.bind(pos=lambda *_: _layout_cover(bg, root), size=lambda *_: _layout_cover(bg, root))

    mask_color = None
    if dim_mask:
        from kivy.uix.widget import Widget
        from kivy.graphics import Color, Rectangle

        mask_widget = Widget(size_hint=(1, 1))
        with mask_widget.canvas.before:
            mask_color = Color(0, 0, 0, 0)
            mask_rect = Rectangle(pos=mask_widget.pos, size=mask_widget.size)
        mask_widget.bind(
            pos=lambda *_: setattr(mask_rect, "pos", mask_widget.pos),
            size=lambda *_: setattr(mask_rect, "size", mask_widget.size),
        )
        root.add_widget(mask_widget)

    def apply():
        app = App.get_running_app()
        mode = getattr(app, "theme_mode", theme.THEME_LIGHT)
        tex = getattr(app, "bg_textures", {}).get(mode)
        if tex is not None:
            bg.texture = tex
        bg.opacity = 1.0
        _layout_cover(bg, root)
        if mask_color is not None:
            effective_dark = theme.resolve_effective_dark(mode)
            mask_color.rgba = (0, 0, 0, 0.9) if effective_dark else (0, 0, 0, 0.0)

    root.apply_bg = apply
    if dim_mask:
        mask_widget._theme_redraw = lambda *_: apply()
    return root, bg


def _layout_cover(bg, root):
    tex = getattr(bg, "texture", None)
    if tex is None or tex.width <= 0 or tex.height <= 0:
        bg.pos = root.pos
        bg.size = root.size
        return
    cw, ch = root.size
    if cw <= 0 or ch <= 0:
        return
    vw, vh = float(tex.width), float(tex.height)
    scale = max(cw / vw, ch / vh)
    w = vw * scale
    h = vh * scale
    bg.pos = (root.x + (cw - w) / 2.0, root.y + (ch - h) / 2.0)
    bg.size = (w, h)
