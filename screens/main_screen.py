from kivy.uix.screenmanager import Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.metrics import dp


class MainScreen(Screen):
    """Главный экран с выбором калькулятора"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Основной вертикальный контейнер
        main_layout = BoxLayout(
            orientation='vertical',
            padding=dp(20),
            spacing=dp(20)
        )

        # Заголовок приложения
        title = Label(
            text='Калькулятор потолков',
            font_size=dp(28),
            color=(0, 0, 0, 1),
            size_hint=(1, 0.2),
            bold=True
        )

        # Контейнер для кнопок
        buttons_layout = BoxLayout(
            orientation='vertical',
            spacing=dp(15),
            size_hint=(1, 0.8)
        )

        # Кнопка 1: Расчет раскладки потолка
        btn_calc1 = Button(
            text='Расчет раскладки потолка',
            font_size=dp(18),
            background_color=(0.2, 0.6, 1, 1),
            color=(1, 1, 1, 1),
            size_hint=(1, 0.45)
        )
        # Изменено: теперь идем в проекты
        btn_calc1.bind(on_press=self.go_to_projects)

        # Кнопка 2: Расчет материалов (заглушка)
        btn_calc2 = Button(
            text='Расчет материалов',
            font_size=dp(18),
            background_color=(0.3, 0.7, 0.3, 1),
            color=(1, 1, 1, 1),
            size_hint=(1, 0.45)
        )
        btn_calc2.bind(on_press=self.show_placeholder)

        # Собираем интерфейс
        buttons_layout.add_widget(btn_calc1)
        buttons_layout.add_widget(btn_calc2)

        main_layout.add_widget(title)
        main_layout.add_widget(buttons_layout)

        self.add_widget(main_layout)

    def go_to_projects(self, instance):  # Переименован метод
        """Переход к экрану проектов"""
        print("Переход к экрану проектов")
        self.manager.current = 'projects'

    def show_placeholder(self, instance):
        """Заглушка для второго калькулятора"""
        instance.text = "В разработке!"
        from kivy.clock import Clock
        Clock.schedule_once(lambda dt: setattr(
            instance, 'text', 'Расчет материалов'), 1)
