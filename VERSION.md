# Версии Ceiling Calculator

| Версия | Стек | Ветка / тег | Примечание |
|--------|------|------------|------------|
| **2.1.4** | Python / Kivy | ветка `legacy-kivy`, тег `v2.1.4` | Последний релиз на Kivy (`buildozer.spec`) |
| **3.0.0** | Flutter / Dart | `master`, тег `v3.0.0` | Полный порт на Flutter (`flutter_app/`) |

## Где задаётся номер

- **Flutter (актуальный продукт):** `flutter_app/pubspec.yaml` → `version: 3.0.0+300`  
  (`3.0.0` = versionName, `300` = versionCode для Android)
- **Kivy (архив):** на ветке `legacy-kivy` в `buildozer.spec` → `version = 2.1.4`

## Как получить Kivy-код

```powershell
git fetch origin
git checkout legacy-kivy
# или только посмотреть: git show v2.1.4:main.py
```

Вернуться к Flutter:

```powershell
git checkout master
```

## История major

- **1.x / 2.x** — Kivy (Android через Buildozer)
- **3.x** — Flutter (Windows / Android / web runner)

Подробный протокол переписывания: [docs/AUDIT_AND_MIGRATION_PROTOCOL.md](docs/AUDIT_AND_MIGRATION_PROTOCOL.md)
