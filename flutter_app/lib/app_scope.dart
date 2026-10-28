import 'package:flutter/material.dart';

import 'data/project_repository.dart';
import 'data/supplier_repository.dart';
import 'domain/theme_controller.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.projects,
    required this.suppliers,
    required this.theme,
    required super.child,
  });

  final ProjectRepository projects;
  final SupplierRepository suppliers;
  final ThemeController theme;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      projects != oldWidget.projects ||
      suppliers != oldWidget.suppliers ||
      theme != oldWidget.theme;
}
