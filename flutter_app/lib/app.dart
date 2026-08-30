import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'data/project_repository.dart';
import 'data/supplier_repository.dart';
import 'domain/admin_access.dart';
import 'domain/theme_controller.dart';
import 'ui/app_theme.dart';
import 'ui/home_screen.dart';

class CeilingCalculatorApp extends StatelessWidget {
  const CeilingCalculatorApp({
    super.key,
    required this.projects,
    required this.suppliers,
    required this.admin,
    required this.theme,
  });

  final ProjectRepository projects;
  final SupplierRepository suppliers;
  final AdminAccess admin;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      projects: projects,
      suppliers: suppliers,
      admin: admin,
      theme: theme,
      child: AnimatedBuilder(
        animation: theme,
        builder: (context, _) {
          return MaterialApp(
            title: 'Ceiling Calculator',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: theme.mode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
