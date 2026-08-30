# Ceiling Calculator

Калькулятор раскладки потолка, материалов и отделки.

**Текущая версия: 3.0.0 (Flutter)** — см. [VERSION.md](VERSION.md).

Исходники приложения: каталог [`flutter_app/`](flutter_app/).

## Запуск

```powershell
$env:Path = "$env:LOCALAPPDATA\flutter\bin;" + $env:Path
cd flutter_app
flutter pub get
flutter run -d windows
flutter test
```

## Legacy Kivy (2.1.4)

Старый Python/Kivy-клиент вынесен в ветку **`legacy-kivy`** (тег `v2.1.4`).  
На `master` его нет — только Flutter.

Протокол миграции и аудит: [docs/AUDIT_AND_MIGRATION_PROTOCOL.md](docs/AUDIT_AND_MIGRATION_PROTOCOL.md)
