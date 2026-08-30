# Flutter — Ceiling Calculator 3.0.0

Актуальный клиент. История версий: корневой [VERSION.md](../VERSION.md).  
Kivy 2.1.4: ветка `legacy-kivy`.

## Run

```powershell
$env:Path = "$env:LOCALAPPDATA\flutter\bin;" + $env:Path
cd flutter_app
flutter pub get
# при ошибке symlink: start ms-settings:developers
flutter run -d windows
flutter test
```

## Стек и возможности (vs Kivy 2.1.4)

| Область | Статус |
|---------|--------|
| Главное меню (раскладка / материалы / отделка / импорт / настройки) | done |
| Long-press Настройки → админ (поставщики / чек / стоимость) | done |
| Проекты / комнаты CRUD + share `.ccproj` | done |
| Редактор: джойстик-оверлей, undo/redo, zoom, замыкание | done |
| Раскладка: сетка / панорама / свет / направляющие / шаблоны каркаса | done |
| Материалы: закупка плит/профилей, Грильято папа/мама, share | done |
| Пол: паттерны, +90°, размеры подрезов | done |
| Поставщики, чек, стоимость | done |
| Тема light/dark/system | done |
| 3D | не в scope |

## Проверка

1. Раскладка → проект → комната → стены → раскладка (сетка / напр. / свет)
2. Материалы → полный расчёт / комната
3. Отделка → пол
4. Админ → поставщики / чек / стоимость
