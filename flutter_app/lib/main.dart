import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/project_repository.dart';
import 'data/supplier_repository.dart';
import 'domain/admin_access.dart';
import 'domain/legacy_migration.dart';
import 'domain/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initDatabaseFactory();
  final db = await openAppDatabase();
  final projects = ProjectRepository(db);
  final suppliers = SupplierRepository(db);
  final admin = AdminAccess();
  final theme = ThemeController();
  await Future.wait([admin.load(), theme.load()]);
  await bootstrapSuppliers(suppliers);
  // Warm project list so first «Проекты» open is from memory.
  await projects.warmCaches();
  runApp(CeilingCalculatorApp(
    projects: projects,
    suppliers: suppliers,
    admin: admin,
    theme: theme,
  ));
}
