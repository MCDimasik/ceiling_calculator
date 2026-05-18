from kivy.uix.modalview import ModalView
from kivy.uix.floatlayout import FloatLayout
from kivy.graphics import Color, RoundedRectangle
from kivy.metrics import dp

from ui_style import COLORS


class RoundedModal(ModalView):
    """
    Единый modal в стиле приложения:
    - затемнение фона
    - скругленная карточка для контента
    """

    def __init__(self, content, card_size_hint=(0.88, None), card_height_dp=260, **kwargs):
        super().__init__(**kwargs)
        self.background = ""
        self.background_color = (0, 0, 0, 0)
        self.auto_dismiss = True

        root = FloatLayout()
        self.add_widget(root)

        card_kwargs = {
            "size_hint": card_size_hint,
            "pos_hint": {"center_x": 0.5, "center_y": 0.55},
        }
        if card_size_hint[1] is None:
            card_kwargs["height"] = dp(card_height_dp)
        self.card = FloatLayout(**card_kwargs)
        root.add_widget(self.card)
        self.card.add_widget(content)

        # ensure content fills card by default
        content.size_hint = (1, 1)
        content.pos_hint = {"x": 0, "y": 0}

        self.bind(size=self._redraw, pos=self._redraw)
        self.card.bind(size=self._redraw, pos=self._redraw)
        self._redraw()

    def _redraw(self, *_):
        self.canvas.before.clear()
        self.card.canvas.before.clear()

        # Dim overlay
        with self.canvas.before:
            Color(*COLORS.get("overlay", (0, 0, 0, 0.35)))
            RoundedRectangle(pos=self.pos, size=self.size, radius=[(0, 0)] * 4)

        # Card
        r = dp(18)
        with self.card.canvas.before:
            Color(*COLORS["surface"])
            RoundedRectangle(pos=self.card.pos, size=self.card.size, radius=[(r, r)] * 4)
