"""Список поставщиков."""
from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.scrollview import ScrollView
from kivy.metrics import dp
from kivy.app import App

from ui_style import COLORS, apply_btn_style, wrap_button_text, style_title
from widgets.ui_components import RoundedButton, RoundedLabel
from widgets.screen_bg import make_bg_root
from supplier_db import list_suppliers, init_supplier_tables
import theme


class SuppliersScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._root, _ = make_bg_root()

        main = BoxLayout(orientation="vertical", spacing=dp(8), padding=dp(12), size_hint=(1, 1))

        toolbar = BoxLayout(size_hint=(1, None), height=dp(72), spacing=dp(6))
        btn_back = RoundedButton(text="Назад", size_hint=(0.28, 1), font_size=dp(14))
        btn_back.corner_radius = dp(12)
        apply_btn_style(btn_back, role="secondary")
        wrap_button_text(btn_back)
        btn_back.bind(on_press=lambda *_: setattr(self.manager, "current", "main"))

        title = RoundedLabel(
            text="Поставщики",
            size_hint=(0.44, 1),
            color=COLORS["text"],
            halign="center",
            valign="middle",
        )
        title.corner_radius = dp(12)
        style_title(title)
        title.bind(size=title.setter("text_size"))

        spacer = Label(size_hint=(0.28, 1))

        toolbar.add_widget(btn_back)
        toolbar.add_widget(title)
        toolbar.add_widget(spacer)

        actions = BoxLayout(size_hint=(1, None), height=dp(54), spacing=dp(8))
        btn_import = RoundedButton(text="Импорт чека", size_hint=(0.5, 1), font_size=dp(14))
        btn_import.corner_radius = dp(14)
        apply_btn_style(btn_import, role="surface")
        wrap_button_text(btn_import)
        btn_import.bind(on_press=lambda *_: setattr(self.manager, "current", "receipt_import"))

        btn_add = RoundedButton(text="Добавить поставщика", size_hint=(0.5, 1), font_size=dp(14))
        btn_add.corner_radius = dp(14)
        apply_btn_style(btn_add, role="surface")
        wrap_button_text(btn_add, horizontal_padding_dp=4)
        btn_add.bind(on_press=self._open_add_supplier)

        actions.add_widget(btn_import)
        actions.add_widget(btn_add)

        self.list_box = BoxLayout(orientation="vertical", spacing=dp(10), size_hint_y=None)
        self.list_box.bind(minimum_height=self.list_box.setter("height"))

        scroll = ScrollView(size_hint=(1, 1))
        scroll.add_widget(self.list_box)

        main.add_widget(toolbar)
        main.add_widget(actions)
        main.add_widget(scroll)

        self._root.add_widget(main)
        self.add_widget(self._root)

    def on_pre_enter(self):
        self._root.apply_bg()
        init_supplier_tables()
        self._reload_list()

    def _reload_list(self):
        self.list_box.clear_widgets()
        suppliers = list_suppliers()
        if not suppliers:
            lbl = Label(
                text="Нет поставщиков.\nДобавьте вручную или импортируйте чек.",
                font_size=dp(14),
                color=(0.5, 0.5, 0.5, 1),
                halign="center",
                size_hint_y=None,
                height=dp(80),
            )
            lbl._theme_slot = "muted"
            lbl.bind(size=lbl.setter("text_size"))
            self.list_box.add_widget(lbl)
            return

        for s in suppliers:
            btn = RoundedButton(
                text=s.name,
                size_hint=(1, None),
                height=dp(54),
                font_size=dp(16),
                color=COLORS["text"],
            )
            btn.corner_radius = dp(18)
            apply_btn_style(btn, role="surface")
            sid = s.id
            btn.bind(on_press=lambda _, sid=sid: self._open_supplier(sid))
            self.list_box.add_widget(btn)

    def _open_add_supplier(self, *_):
        self.manager.supplier_edit_id = None
        self.manager.current = "supplier_edit"

    def _open_supplier(self, supplier_id):
        self.manager.supplier_edit_id = supplier_id
        self.manager.current = "supplier_edit"
