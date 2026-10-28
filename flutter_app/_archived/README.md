# Deferred / archived features (2026-09-04, roles/admin cleared 2026-10-27)

Implementations kept here so we can restore later without archaeology.

## 0. Field roles · admin password · смена · задачи (cleared 2026-10-27)

**Why removed:** Rebuild roles/permissions from scratch. Old site-role gates and
admin password confused Home/docs and hid features that are now public.

**Removed from live `lib/` (copies here):**
- `admin_access.dart` — password unlock
- `field_role.dart` — worker / foreman / manager / full
- `field_tasks.dart`, `field_task_routing.dart`
- `field_tasks_screen.dart`, `field_checklist_screen.dart`
- `project_fact_alerts.dart` (depended on field tasks)

**Live change:**
- No `AdminAccess` / `FieldRoleController` in `AppScope`
- Settings: no role picker, no admin hold-to-unlock
- Docs: no «Исполнитель / бригада», priority, «Задачи бригады», dashboard «Назначение»
- Checklist JSON still has `assignee` / `priority` / `manualTasks` fields for old data + exports

**Also archived (redundant):**
- `project_cost_screen.dart` — AppBar «Стоимость» по объекту

**Receipt import:** live again under Расценки → Материалы → Поставщики
(`lib/ui/receipt_import_screen.dart`). Copy in `_archived/` is a snapshot only.

**Already public:** Home «Расценки» (works + suppliers), docs hub, KS-2, finish, layout.

**Restore later:** copy domain/UI back, re-wire `main.dart` / `AppScope`, rebuild permission model as needed.

## 1. Room Hub in «Расчёт отделки»

**Why removed:** Extra hop object → rooms → Hub → Отделка. Finish should open the finish editor directly.

**Live change:** `rooms_screen.dart` + `room_navigation.dart` open `FinishRoomScreen` for `AppModule.finish` (no Hub).

**Kept copies:**
- `room_hub_screen.dart` — full Hub UI
- `room_navigation.dart` — previous `openRoomHub` / `openRoomModule` that always went through Hub
- `open_finish_room_snippet.dart` — finish-only entry helper

Hub may still be used by documentation / materials / cross-module jumps; only the **finish entry path** was bypassed.

## 2. «Проект vs факт» / rebaseline

**Why removed:** Not needed in current workflow.

**Live change:** UI entry points and field-task alerts disconnected. Domain helpers left in `lib/` so data models still load; restore UI from copies below.

**Kept copies:**
- `project_fact_alerts.dart`
- `rebaseline_wizard_screen.dart`
- `finish_design_baseline.dart`
- `typical_floor_diff.dart`
- `finish_project_vs_fact_ui.dart.txt` — UI cards, ghost overlay, tab alerts, rebaseline dialogs

## 3. Сводка объекта — лишние входы

См. `dashboard_extras.md`.

**Оставлено:** одна кнопка «Документы» → `ProjectDocumentsHubScreen`; типовой этаж; прогресс комнат.

**Убрано с поверхности сводки:** задачи, этап, план этажа, разрозненные карточки КП/КС/импорт (собраны в хаб документов).

## Restore checklist

1. Copy domain/UI files back from this folder into `lib/…` if overwritten.
2. Wire `rooms_screen` finish path through Hub again if desired.
3. Re-paste snippets from `finish_project_vs_fact_ui.dart.txt`.
4. Re-add role/admin wiring in `main.dart` / `AppScope` only when the new permission model is ready.
5. Restore dashboard AppBar/cards from git/`dashboard_extras.md` notes if needed.
