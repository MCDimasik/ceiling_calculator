# Flutter port of Ceiling Calculator

Python/Kivy app remains in the repo root for reference.

## Run

```powershell
$env:Path = "$env:LOCALAPPDATA\flutter\bin;" + $env:Path
cd flutter_app
flutter pub get
# при ошибке symlink: start ms-settings:developers
flutter run -d windows
flutter test
```

## Parity with Kivy (без 3D — его нет в Kivy)

| Область | Статус |
|---------|--------|
| Главное меню (раскладка / материалы / импорт / поставщики / настройки) | done |
| Long-press Настройки → админ | done |
| Проекты / комнаты CRUD + share `.ccproj` | done |
| Редактор: джойстик, undo/redo, zoom ±, замыкание | done |
| Раскладка: сетка / панорама / свет, стрелки, размеры | done |
| Материалы + формулы + share + переход в раскладку | done |
| Поставщики, позиции каталога, +10%, шт/уп | done |
| Импорт чека PDF/TXT + шаблон Сатурн + seed | done |
| Стоимость + выгода | done |
| Тема light/dark/system | done |
| 3D | нет в Kivy — не делаем |

## Запуск сценария проверки

1. Главная → **Расчет раскладки** → проект → комната → джойстик → **Раскладка** → свет / стрелки
2. **Расчет материалов** → **Полный Расчет** / комната → формулы / **Поделиться**
3. Long-press **Настройки** → пароль → **Поставщики** → **Импорт чека** / цены → **Стоимость**
