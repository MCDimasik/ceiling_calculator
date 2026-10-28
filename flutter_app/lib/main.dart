import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/project_repository.dart';
import 'data/supplier_repository.dart';
import 'domain/legacy_migration.dart';
import 'domain/theme_controller.dart';
import 'domain/work_rates_catalog.dart';
import 'ui/widgets/app_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initDatabaseFactory();
  final db = await openAppDatabase();
  final projects = ProjectRepository(db);
  final suppliers = SupplierRepository(db);
  final theme = ThemeController();
  await theme.load();
  await bootstrapSuppliers(suppliers);
  // Warm work-rates catalog for KS-2 price fallback / pickers.
  await WorkRatesCatalogStore.ensureLoaded();
  // Warm project list so first «Проекты» open is from memory.
  await projects.warmCaches();
  // Pre-blur light+dark backgrounds once (memory + disk) — no flash on finish screens.
  await BgBlurCache.warm(const [
    'assets/media/bg_light.png',
    'assets/media/bg_dark.png',
  ]);
  runApp(CeilingCalculatorApp(
    projects: projects,
    suppliers: suppliers,
    theme: theme,
  ));
}
