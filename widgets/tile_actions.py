"""Плитка проекта/комнаты: долгое нажатие — кнопки внутри карточки с анимацией."""
from kivy.animation import Animation
from kivy.clock import Clock
from kivy.core.window import Window
from kivy.metrics import dp
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.label import Label
from kivy.uix.relativelayout import RelativeLayout


from ui_style import COLORS, apply_btn_style, fit_button_font, wrap_button_text
from widgets.ui_components import RoundedButton

_LONG_PRESS_SEC = 0.55
_MOVE_CANCEL_DP = 14
_FLIP_HALF = 0.15
_FLIP_TOTAL = _FLIP_HALF * 2
_FACE_INSET_DP = 10


class LongPressTile(RelativeLayout):
    """Короткий тап — открыть; долгий — «Поделиться» / «Удалить» внутри плитки."""

    _active_tile = None
    _window_touch_bound = False

    def __init__(
        self,
        tile_width,
        text,
        on_open,
        on_share,
        on_delete,
        font_size_dp=16,
        **kwargs,
    ):
        super().__init__(size_hint=(None, None), size=(tile_width, tile_width), **kwargs)
        self._on_open = on_open
        self._on_share = on_share
        self._on_delete = on_delete
        self._mode = "title"
        self._long_fired = False
        self._lp_event = None
        self._touch_start = None
        self._animating = False
        self._pending_open = False
        self._show_anim = None
        self._hide_anim = None

        self.card = RoundedButton(
            text="",
            size_hint=(1, 1),
            background_normal="",
        )
        self.card.corner_radius = dp(18)
        apply_btn_style(self.card, role="surface")
        self.add_widget(self.card)

        self._flip_host = FloatLayout(size_hint=(1, 1))
        self.add_widget(self._flip_host)

        self._title_face = FloatLayout(size_hint=(None, None))
        self._title_label = Label(
            text=text,
            font_size=dp(font_size_dp),
            color=COLORS["text"],
            halign="center",
            valign="middle",
            pos_hint={"center_x": 0.5, "center_y": 0.5},
            size_hint=(None, None),
        )
        self._title_face.add_widget(self._title_label)

        self._actions_face = RelativeLayout(size_hint=(None, None), opacity=0, disabled=True)
        # Две широкие «полосы» на всю ширину карточки (одна под другой)
        self._actions_box = BoxLayout(
            orientation="vertical",
            spacing=dp(6),
            padding=(dp(6), dp(6)),
            size_hint=(1, 1),
        )
        self._btn_share = RoundedButton(
            text="Поделиться",
            font_size=dp(12),
            size_hint=(1, 0.5),
            halign="center",
            valign="middle",
        )
        self._btn_share.corner_radius = dp(12)
        apply_btn_style(self._btn_share, role="primary")
        wrap_button_text(self._btn_share, horizontal_padding_dp=4)
        fit_button_font(self._btn_share, max_font_dp=11, min_font_dp=9, horizontal_padding_dp=4)
        self._btn_share.bind(on_press=lambda *_: self._do_share())

        self._btn_delete = RoundedButton(
            text="Удалить",
            font_size=dp(12),
            size_hint=(1, 0.5),
            halign="center",
            valign="middle",
        )
        self._btn_delete.corner_radius = dp(12)
        apply_btn_style(self._btn_delete, role="danger")
        wrap_button_text(self._btn_delete, horizontal_padding_dp=4)
        fit_button_font(self._btn_delete, max_font_dp=11, min_font_dp=9, horizontal_padding_dp=4)
        self._btn_delete.bind(on_press=lambda *_: self._do_delete())

        self._actions_box.add_widget(self._btn_share)
        self._actions_box.add_widget(self._btn_delete)
        self._actions_face.add_widget(self._actions_box)

        self._flip_host.add_widget(self._title_face)
        self._flip_host.add_widget(self._actions_face)

        self.bind(size=self._layout_faces)
        Clock.schedule_once(lambda *_: self._layout_faces(), 0)

    def _layout_faces(self, *args):
        w, h = self.size
        if w <= 0 or h <= 0:
            return
        inset = dp(_FACE_INSET_DP)
        face_w = max(w - inset * 2, dp(40))
        face_h = max(h - inset * 2, dp(40))
        pos = (inset, inset)
        size = (face_w, face_h)
        for face in (self._title_face, self._actions_face):
            face.pos = pos
            face.size = size
        text_w = max(face_w - dp(12), dp(20))
        text_h = max(face_h - dp(12), dp(20))
        self._title_label.text_size = (text_w, text_h)
        self._title_label.size = (text_w, text_h)
        spacing_y = self._actions_box.spacing
        if isinstance(spacing_y, (list, tuple)):
            spacing_y = spacing_y[1] if len(spacing_y) > 1 else spacing_y[0]
        pad_y = dp(6) * 2 + float(spacing_y)
        btn_w = max(face_w - dp(12), dp(40))
        btn_h = max((face_h - pad_y) / 2.0, dp(28))
        for btn in (self._btn_share, self._btn_delete):
            btn.text_size = (btn_w, btn_h)
            fit_button_font(btn, max_font_dp=12, min_font_dp=9, horizontal_padding_dp=6)

    def _cancel_running_anims(self):
        for anim in (self._show_anim, self._hide_anim):
            if anim:
                anim.cancel_all(self._title_face)
                anim.cancel_all(self._actions_face)
        self._show_anim = None
        self._hide_anim = None

    def _touch_hits_actions(self, touch):
        if self._mode != "actions" or not self._actions_face.opacity:
            return False
        for btn in (self._btn_share, self._btn_delete):
            local = btn.to_widget(touch.x, touch.y)
            if btn.collide_point(*local):
                return True
        return False

    def on_touch_down(self, touch):
        if self._animating:
            return True

        if self._mode == "actions":
            if self._touch_hits_actions(touch):
                return super().on_touch_down(touch)
            self._hide_actions(animated=True)
            return True

        if not self.collide_point(*touch.pos):
            return super().on_touch_down(touch)

        if LongPressTile._active_tile and LongPressTile._active_tile is not self:
            LongPressTile._active_tile._hide_actions(animated=False)

        self._long_fired = False
        self._pending_open = True
        self._touch_start = touch.pos
        if self._lp_event:
            self._lp_event.cancel()
        self._lp_event = Clock.schedule_once(self._on_long_press, _LONG_PRESS_SEC)
        return False

    def on_touch_move(self, touch):
        if self._mode == "actions" or self._touch_start is None:
            return super().on_touch_move(touch)
        dx = touch.x - self._touch_start[0]
        dy = touch.y - self._touch_start[1]
        if dx * dx + dy * dy > dp(_MOVE_CANCEL_DP) ** 2:
            self._cancel_long_press()
            self._pending_open = False
        return False

    def on_touch_up(self, touch):
        if self._mode == "actions":
            return super().on_touch_up(touch)

        had_lp = self._lp_event is not None
        self._cancel_long_press()

        if self._long_fired:
            self._long_fired = False
            return True

        if (
            had_lp
            and self._pending_open
            and self.collide_point(*touch.pos)
            and self._on_open
        ):
            self._on_open()
        return False

    def _cancel_long_press(self):
        if self._lp_event:
            self._lp_event.cancel()
            self._lp_event = None

    def _on_long_press(self, dt):
        self._lp_event = None
        if self._touch_start is None:
            return
        self._long_fired = True
        self._pending_open = False
        self._show_actions()

    @classmethod
    def _bind_window_dismiss(cls):
        if cls._window_touch_bound:
            return
        Window.bind(on_touch_down=cls._on_window_touch)
        cls._window_touch_bound = True

    @classmethod
    def _unbind_window_dismiss(cls):
        if not cls._window_touch_bound:
            return
        Window.unbind(on_touch_down=cls._on_window_touch)
        cls._window_touch_bound = False

    @classmethod
    def _on_window_touch(cls, window, touch):
        tile = cls._active_tile
        if not tile or tile._mode != "actions" or tile._animating:
            return
        local = tile.to_widget(touch.x, touch.y)
        if tile.collide_point(*local):
            return
        tile._hide_actions(animated=True)

    def _show_actions(self):
        if self._mode == "actions":
            return
        self._cancel_running_anims()
        LongPressTile._active_tile = self
        LongPressTile._bind_window_dismiss()
        self._animating = True
        self._mode = "actions"

        self._title_face.opacity = 1
        self._actions_face.opacity = 0
        self._actions_face.disabled = True

        def after_title_out(*_):
            self._title_face.opacity = 0
            self._actions_face.disabled = False
            self._actions_face.opacity = 0
            anim_in = Animation(opacity=1, duration=_FLIP_HALF, t="out_quad")
            anim_in.bind(on_complete=lambda *a: self._finish_show())
            self._show_anim = anim_in
            anim_in.start(self._actions_face)

        anim_out = Animation(opacity=0, duration=_FLIP_HALF, t="in_quad")
        anim_out.bind(on_complete=after_title_out)
        self._show_anim = anim_out
        anim_out.start(self._title_face)

    def _finish_show(self):
        self._animating = False
        self._show_anim = None

    def _hide_actions(self, animated=True):
        if self._mode != "actions":
            return
        if LongPressTile._active_tile is self:
            LongPressTile._active_tile = None
            LongPressTile._unbind_window_dismiss()

        if not animated:
            self._cancel_running_anims()
            self._reset_faces_instant()
            return

        if self._animating:
            self._cancel_running_anims()
        self._animating = True

        def after_actions_out(*_):
            self._actions_face.opacity = 0
            self._actions_face.disabled = True
            self._title_face.opacity = 0
            anim_in = Animation(opacity=1, duration=_FLIP_HALF, t="out_quad")
            anim_in.bind(on_complete=lambda *a: self._finish_hide())
            self._hide_anim = anim_in
            anim_in.start(self._title_face)

        anim_out = Animation(opacity=0, duration=_FLIP_HALF, t="in_quad")
        anim_out.bind(on_complete=after_actions_out)
        self._hide_anim = anim_out
        anim_out.start(self._actions_face)

    def _finish_hide(self):
        self._mode = "title"
        self._animating = False
        self._hide_anim = None
        self._long_fired = False

    def _reset_faces_instant(self):
        self._mode = "title"
        self._animating = False
        self._title_face.opacity = 1
        self._actions_face.opacity = 0
        self._actions_face.disabled = True

    def _do_share(self):
        self._hide_actions(animated=True)
        if self._on_share:
            Clock.schedule_once(lambda dt: self._on_share(), _FLIP_TOTAL + 0.02)

    def _do_delete(self):
        self._hide_actions(animated=True)
        if self._on_delete:
            Clock.schedule_once(lambda dt: self._on_delete(), _FLIP_TOTAL + 0.02)

    @classmethod
    def dismiss_active(cls):
        if cls._active_tile:
            cls._active_tile._hide_actions(animated=True)
