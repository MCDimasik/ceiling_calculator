import 'package:flutter/material.dart';

import '../domain/finish_model.dart';

/// Which top-level module is open in the desktop cascade.
enum DesktopCascadeModule {
  ceiling,
  materialsCeiling,
  finish,
  documentation,
  pricing,
  archive,
  inbox,
  settings,
}

extension DesktopCascadeModuleX on DesktopCascadeModule {
  String get labelRu => switch (this) {
        DesktopCascadeModule.ceiling => 'Раскладка',
        DesktopCascadeModule.materialsCeiling => 'Мат. потолка',
        DesktopCascadeModule.finish => 'Отделка',
        DesktopCascadeModule.documentation => 'Документы',
        DesktopCascadeModule.pricing => 'Расценки',
        DesktopCascadeModule.archive => 'Архив',
        DesktopCascadeModule.inbox => 'Входящие',
        DesktopCascadeModule.settings => 'Настройки',
      };

  IconData get icon => switch (this) {
        DesktopCascadeModule.ceiling => Icons.grid_on_outlined,
        DesktopCascadeModule.materialsCeiling => Icons.inventory_2_outlined,
        DesktopCascadeModule.finish => Icons.apartment_outlined,
        DesktopCascadeModule.documentation => Icons.description_outlined,
        DesktopCascadeModule.pricing => Icons.payments_outlined,
        DesktopCascadeModule.archive => Icons.archive_outlined,
        DesktopCascadeModule.inbox => Icons.inbox_outlined,
        DesktopCascadeModule.settings => Icons.settings_outlined,
      };

  AppModule? get appModule => switch (this) {
        DesktopCascadeModule.ceiling => AppModule.ceilingLayout,
        DesktopCascadeModule.finish => AppModule.finish,
        DesktopCascadeModule.documentation => AppModule.documentation,
        _ => null,
      };

  bool get usesProjectRoomsCascade =>
      this == DesktopCascadeModule.ceiling ||
      this == DesktopCascadeModule.finish ||
      this == DesktopCascadeModule.documentation;

  bool get usesProjectThenDetail =>
      this == DesktopCascadeModule.materialsCeiling;

  /// Mid list + right detail (Расценки, Архив).
  bool get usesHubThenDetail =>
      this == DesktopCascadeModule.pricing ||
      this == DesktopCascadeModule.archive;
}

/// Inherited API so nested screens open the next cascade pane
/// instead of pushing a full-screen route.
class DesktopCascadeHost extends InheritedWidget {
  const DesktopCascadeHost({
    super.key,
    required this.openModule,
    required this.openProject,
    required this.openDetail,
    required this.closeDetail,
    required this.clearProject,
    required this.goHome,
    required this.module,
    required this.projectId,
    required this.hasDetail,
    required this.detailId,
    required super.child,
  });

  final void Function(DesktopCascadeModule module) openModule;
  final void Function(int projectId) openProject;
  final void Function(
    Widget detail, {
    String? title,
    Object? detailId,
  }) openDetail;
  final VoidCallback closeDetail;
  final VoidCallback clearProject;
  final VoidCallback goHome;

  final DesktopCascadeModule? module;
  final int? projectId;
  final bool hasDetail;

  /// Stable id of center content (e.g. `room:12`, `dash:3`) for list highlight
  /// and forcing Flutter to rebuild when switching rooms.
  final Object? detailId;

  static DesktopCascadeHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopCascadeHost>();

  static DesktopCascadeHost of(BuildContext context) {
    final h = maybeOf(context);
    assert(h != null, 'DesktopCascadeHost not found');
    return h!;
  }

  @override
  bool updateShouldNotify(DesktopCascadeHost oldWidget) =>
      module != oldWidget.module ||
      projectId != oldWidget.projectId ||
      hasDetail != oldWidget.hasDetail ||
      detailId != oldWidget.detailId;
}
