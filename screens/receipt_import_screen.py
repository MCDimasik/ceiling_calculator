"""Импорт PDF-чека."""
from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.metrics import dp
from kivy.utils import platform

from ui_style import COLORS, apply_btn_style, wrap_button_text, style_title
from widgets.ui_components import RoundedButton, RoundedLabel
from widgets.ui_modal import RoundedModal
from widgets.screen_bg import make_bg_root
from receipt_import import import_receipt_pdf


class ReceiptImportScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._root, _ = make_bg_root()
        main = BoxLayout(orientation="vertical", spacing=dp(12), padding=dp(16), size_hint=(1, 1))

        toolbar = BoxLayout(size_hint=(1, None), height=dp(72), spacing=dp(8))
        btn_back = RoundedButton(text="Назад", size_hint=(0.35, 1), font_size=dp(14))
        btn_back.corner_radius = dp(12)
        apply_btn_style(btn_back, role="secondary")
        wrap_button_text(btn_back)
        btn_back.bind(on_press=lambda *_: setattr(self.manager, "current", "suppliers"))

        title = RoundedLabel(text="Импорт чека", size_hint=(0.65, 1), color=COLORS["text"], halign="center", valign="middle")
        title.corner_radius = dp(12)
        style_title(title)
        title.bind(size=title.setter("text_size"))
        toolbar.add_widget(btn_back)
        toolbar.add_widget(title)

        self.info = Label(
            text=(
                "Выберите PDF-файл чека.\n"
                "Если для вашего поставщика есть шаблон (receipt_templates/*.json), "
                "разбор будет точнее.\n"
                "Проверьте цены в карточке поставщика после импорта."
            ),
            font_size=dp(14),
            color=COLORS["text"],
            halign="center",
            valign="middle",
            size_hint=(1, 1),
        )
        self.info.bind(size=lambda inst, val: setattr(inst, "text_size", val))

        btn_pick = RoundedButton(text="Выбрать PDF", size_hint=(1, None), height=dp(54), font_size=dp(16))
        btn_pick.corner_radius = dp(18)
        apply_btn_style(btn_pick, role="primary")
        btn_pick.bind(on_press=self._pick_pdf)

        main.add_widget(toolbar)
        main.add_widget(self.info)
        main.add_widget(btn_pick)
        self._root.add_widget(main)
        self.add_widget(self._root)

    def on_pre_enter(self):
        self._root.apply_bg()

    def _pick_pdf(self, *_):
        if platform == "android":
            self._pick_android()
        else:
            self._pick_desktop()

    def _pick_desktop(self):
        try:
            import tkinter as tk
            from tkinter import filedialog

            root = tk.Tk()
            root.withdraw()
            path = filedialog.askopenfilename(
                title="Выберите PDF чека",
                filetypes=[("PDF", "*.pdf"), ("Все файлы", "*.*")],
            )
            root.destroy()
            if path:
                self._run_import(path)
        except Exception as e:
            self._show_result(False, str(e))

    def _pick_android(self):
        try:
            from platform_files import pick_project_file

            def on_path(path):
                if path:
                    self._run_import(path)

            pick_project_file(on_path)
        except Exception:
            self._show_result(False, "Выбор файла на Android пока через общий импорт. Используйте ПК или добавьте цены вручную.")

    def _run_import(self, path):
        result, err = import_receipt_pdf(path, merge=True)
        if err:
            self._show_result(False, err)
            return
        s = result["supplier"]
        matched = len(result["matched"])
        unmatched = len(result["unmatched"])
        parser = result.get("parser") or {}
        if parser.get("template_name"):
            mode = f"Шаблон: {parser['template_name']}"
        else:
            mode = "Общий разбор (без шаблона)"
        msg = (
            f"Поставщик: {s.name}\n"
            f"{mode}\n"
            f"Сопоставлено позиций: {matched}\n"
            f"Без сопоставления: {unmatched}\n\n"
            "Откройте карточку поставщика и проверьте цены."
        )
        self._show_result(True, msg, supplier_id=s.id)

    def _show_result(self, ok, message, supplier_id=None):
        content = BoxLayout(orientation="vertical", padding=dp(16), spacing=dp(12))
        lbl = Label(text=message, font_size=dp(14), color=COLORS["text"], halign="center", valign="middle")
        lbl.bind(size=lambda inst, val: setattr(inst, "text_size", (inst.width, None)))
        content.add_widget(lbl)
        btns = BoxLayout(spacing=dp(8), size_hint=(1, None), height=dp(44))
        btn_ok = RoundedButton(text="ОК")
        btn_ok.corner_radius = dp(12)
        apply_btn_style(btn_ok, role="secondary")
        modal = RoundedModal(content=content, card_size_hint=(0.9, None), card_height_dp=280)

        if ok and supplier_id:
            btn_open = RoundedButton(text="Открыть")
            btn_open.corner_radius = dp(12)
            apply_btn_style(btn_open, role="primary")

            def open_sup(*_):
                modal.dismiss()
                self.manager.supplier_edit_id = supplier_id
                self.manager.current = "supplier_edit"

            btn_open.bind(on_press=open_sup)
            btns.add_widget(btn_open)

        btn_ok.bind(on_press=lambda *_: (modal.dismiss(), setattr(self.manager, "current", "suppliers") if ok else None))
        btns.add_widget(btn_ok)
        content.add_widget(btns)
        modal.open()
