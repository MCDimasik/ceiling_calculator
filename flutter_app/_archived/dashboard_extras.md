# Dashboard extras archived from UI (2026-09-04)

Kept in code history / this note — restore if needed.

## Removed from «Сводка объекта» surface

- AppBar: задачидачи, ZIP, КС-3 menu, summary PDF/text (ZIP/КС доступны через «Документы»)
- Карточки: импорт договора, отдельные КП/КС/закрытие, задачи
- Этап объекта (`_StageCard`)
- План этажа со сводки (дубль кнопки на списке комнат)
- Легенда КС на главной сводки

## Kept

- Одна кнопка **Документы** → `ProjectDocumentsHubScreen` (список: КП, смета, КС-2, КС-3, акт, закрытие, сертификаты, ZIP, загрузка, штамп)
- Типовой этаж (как был)
- Статистика / фильтр / список комнат → документация комнаты (схемы, чеклист, ведомость)

## Hub file

`lib/ui/project_documents_hub_screen.dart`
