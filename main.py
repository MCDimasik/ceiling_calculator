from kivy.app import App
from kivy.uix.screenmanager import ScreenManager
from kivy.uix.screenmanager import SlideTransition
from kivy.core.window import Window
from kivy.utils import platform
import os

from screens.main_screen import MainScreen
from screens.projects_screen import ProjectsScreen
from screens.rooms_screen import RoomsScreen
from screens.room_editor import RoomEditorScreen
from screens.layout_screen import LayoutScreen
from screens.materials_projects_screen import MaterialsProjectsScreen
from screens.materials_rooms_screen import MaterialsRoomsScreen
from screens.materials_result_screen import MaterialsResultScreen
from screens.materials_project_result_screen import MaterialsProjectResultScreen
from screens.settings_screen import SettingsScreen

import theme
from ui_style import COLORS

# ANGLE нужен только для отладки на Windows. На Android может ломать рендер/видео.
if platform == "win":
    os.environ["KIVY_GL_BACKEND"] = "angle_sdl2"

if platform != 'android':
    Window.size = (320, 640)


class CeilingCalculatorApp(App):
    theme_mode = theme.THEME_LIGHT
    use_video_bg = True

    def build(self):
        self.theme_prefs_path = os.path.join(self.user_data_dir, 'app_prefs.json')
        self.theme_mode = theme.load_theme_mode(self.theme_prefs_path)
        self.use_video_bg = theme.load_pref_bool(self.theme_prefs_path, "use_video_bg", True)
        # Кэшируем текстуры фоновых картинок, чтобы не было микрофризов на переходах.
        try:
            from kivy.core.image import Image as CoreImage
            from kivy.resources import resource_find

            light_path = resource_find("assets/bg_light.png") or "assets/bg_light.png"
            dark_path = resource_find("assets/bg_dark.png") or "assets/bg_dark.png"
            self.bg_textures = {
                theme.THEME_LIGHT: CoreImage(light_path).texture,
                theme.THEME_DARK: CoreImage(dark_path).texture,
            }
        except Exception:
            self.bg_textures = {}
        effective_dark = theme.resolve_effective_dark(self.theme_mode)
        theme.apply_palette_to_ui_style(effective_dark)
        Window.clearcolor = COLORS['bg']

        if platform == 'android':
            Window.softinput_mode = 'below_target'

        # Возвращаем "как раньше": слайд-переход между экранами.
        sm = ScreenManager(transition=SlideTransition(duration=0.22))
        sm.current_project = None
        sm.current_room = None

        sm.add_widget(MainScreen(name='main'))
        sm.add_widget(ProjectsScreen(name='projects'))
        sm.add_widget(RoomsScreen(name='rooms'))
        sm.add_widget(RoomEditorScreen(name='room_editor'))
        sm.add_widget(LayoutScreen(name='layout'))
        sm.add_widget(MaterialsProjectsScreen(name='materials_projects'))
        sm.add_widget(MaterialsRoomsScreen(name='materials_rooms'))
        sm.add_widget(MaterialsResultScreen(name='materials_result'))
        sm.add_widget(MaterialsProjectResultScreen(name='materials_project_result'))
        sm.add_widget(SettingsScreen(name='settings'))

        return sm

    def on_resume(self):
        return


if __name__ == '__main__':
    CeilingCalculatorApp().run()
