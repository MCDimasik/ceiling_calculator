# main.py
from kivy.app import App
from kivy.uix.screenmanager import ScreenManager
from kivy.core.window import Window
from kivy.utils import get_color_from_hex
# Импортируем экраны
from screens.main_screen import MainScreen
from screens.projects_screen import ProjectsScreen
from screens.rooms_screen import RoomsScreen
from screens.room_editor import RoomEditorScreen
from screens.layout_screen import LayoutScreen

import os
os.environ['KIVY_GL_BACKEND'] = 'angle_sdl2'

# Устанавливаем размер как у телефона
Window.size = (360, 640)
Window.clearcolor = (1, 1, 1, 1)  # Белый фон


class CeilingCalculatorApp(App):
    def build(self):
        # Создаем менеджер экранов с дополнительными свойствами
        sm = ScreenManager()

        # Добавляем возможность хранить текущий проект и комнату
        sm.current_project = None
        sm.current_room = None

        # Добавляем экраны
        sm.add_widget(MainScreen(name='main'))
        sm.add_widget(ProjectsScreen(name='projects'))
        sm.add_widget(RoomsScreen(name='rooms'))
        sm.add_widget(RoomEditorScreen(name='room_editor'))
        sm.add_widget(LayoutScreen(name='layout'))  # Добавляем экран раскладки
        Window.clearcolor = get_color_from_hex('#FFFFFF')
        # Применяем стиль для кнопок
        self.theme_cls = type('Theme', (), {
            'primary_color': get_color_from_hex('#000000'),
            'text_color': get_color_from_hex('#000000')
        })

        return sm


if __name__ == '__main__':
    CeilingCalculatorApp().run()
