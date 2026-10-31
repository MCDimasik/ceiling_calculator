import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/cloud_sync_stub.dart';

/// Breakpoints tuned for **Full HD (1920×1080)** as the primary desktop target,
/// with graceful scale down to laptop / up to 2K+.
class AdaptiveBreakpoints {
  /// Phone / compact: below this → mobile chrome.
  static const compactMax = 900.0;

  /// Comfortable two-pane (project | rooms) from here.
  static const splitMin = 1100.0;

  /// Extended NavigationRail labels (FHD sweet spot).
  static const railExtendedMin = 1400.0;

  /// Content cap inside panes on ultrawide (leave side margins on 1920+).
  static const contentMaxFhd = 1680.0;

  /// Readable column inside cascade solo modules (settings, pricing, inbox…).
  static const paneReadableMax = 760.0;

  /// Slightly wider readable column (inbox, archive grids).
  static const paneReadableWide = 980.0;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactMax;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= compactMax;

  static bool canMasterDetail(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= splitMin;

  static bool railExtended(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= railExtendedMin;

  /// Desktop chrome: wide window, desktop OS, or `--dart-define=SURFACE=desktop`.
  /// Force phone UI while developing on Windows:
  /// `flutter run -d windows --dart-define=FORCE_PHONE=true`
  static bool useDesktopChrome(BuildContext context) {
    const forcePhone =
        bool.fromEnvironment('FORCE_PHONE', defaultValue: false);
    if (forcePhone) return false;

    final surface = AppSurface.fromEnvironment();
    if (surface.isDesktop) return true;
    if (isWide(context)) return true;
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return isWide(context);
    }
    return false;
  }
}

/// Shared desktop density — prefer these over magic numbers in screens.
class DesktopMetrics {
  static bool of(BuildContext context) =>
      AdaptiveBreakpoints.useDesktopChrome(context);

  static double listTileMinHeight(BuildContext context) =>
      of(context) ? 84.0 : 72.0;

  static double listTileMinHeightTall(BuildContext context) =>
      of(context) ? 100.0 : 88.0;

  static double actionOrb(BuildContext context) => of(context) ? 48.0 : 44.0;

  static double actionIcon(BuildContext context) => of(context) ? 24.0 : 22.0;

  static double leadingRadius(BuildContext context) =>
      of(context) ? 24.0 : 20.0;

  static double hPad(BuildContext context) => of(context) ? 22.0 : 16.0;

  static double sectionGap(BuildContext context) => of(context) ? 20.0 : 12.0;

  /// Keep FAB footprint aligned with phone «+ Комната» (110×label 52).
  static double fabWidth(BuildContext context) => kDesktopFabWidth;

  static double fabLabelWidth(BuildContext context) => kDesktopFabLabelWidth;

  static const kDesktopFabWidth = 110.0;
  static const kDesktopFabLabelWidth = 52.0;

  /// Soft text bump for desktop (applied once in MaterialApp.builder).
  static TextScaler textScaler(BuildContext context) {
    final base = MediaQuery.textScalerOf(context);
    if (!of(context)) return base;
    return base.clamp(minScaleFactor: 1.06, maxScaleFactor: 1.16);
  }
}

/// Centers content and caps width on large monitors (FHD-oriented).
class AdaptiveContent extends StatelessWidget {
  const AdaptiveContent({
    super.key,
    required this.child,
    this.maxWidth = AdaptiveBreakpoints.contentMaxFhd,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (!AdaptiveBreakpoints.useDesktopChrome(context)) {
      return child;
    }
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Classic desktop master | detail split (objects ↔ rooms).
class MasterDetailSplit extends StatelessWidget {
  const MasterDetailSplit({
    super.key,
    required this.master,
    required this.detail,
    /// Pass `null` to auto-size from window width (~22% FHD).
    this.masterWidth,
    this.dividerWidth = 1,
  });

  final Widget master;
  final Widget detail;
  final double? masterWidth;
  final double dividerWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = MediaQuery.sizeOf(context).width;
    final auto = (w * 0.22).clamp(360.0, 460.0);
    final mw = masterWidth ?? auto;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: mw, child: master),
        VerticalDivider(
          width: dividerWidth,
          thickness: dividerWidth,
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
        Expanded(child: detail),
      ],
    );
  }
}

/// Centered empty / hint state for wide cascade panes.
class DesktopEmptyState extends StatelessWidget {
  const DesktopEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.maxWidth = 440,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: DesktopMetrics.of(context) ? 72 : 56,
                color: scheme.onSurface.withValues(alpha: 0.38),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.78),
                      height: 1.3,
                    ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                        height: 1.4,
                      ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 24),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Theme overlays for desktop density (list tiles, app bar, icons).
ThemeData desktopThemeOverlay(ThemeData base) {
  final text = base.textTheme.copyWith(
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontSize: (base.textTheme.titleLarge?.fontSize ?? 22) + 1,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontSize: (base.textTheme.titleMedium?.fontSize ?? 16) + 1.5,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: base.textTheme.titleSmall?.copyWith(
      fontSize: (base.textTheme.titleSmall?.fontSize ?? 14) + 1,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(
      fontSize: (base.textTheme.bodyLarge?.fontSize ?? 16) + 0.5,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(
      fontSize: (base.textTheme.bodyMedium?.fontSize ?? 14) + 1,
    ),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontSize: (base.textTheme.labelLarge?.fontSize ?? 14) + 1,
      fontWeight: FontWeight.w600,
    ),
  );
  return base.copyWith(
    textTheme: text,
    primaryTextTheme: text,
    visualDensity: VisualDensity.standard,
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 10,
      minTileHeight: 84,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      titleAlignment: ListTileTitleAlignment.center,
      horizontalTitleGap: 14,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      toolbarHeight: 58,
      titleTextStyle: text.titleLarge,
      actionsIconTheme: IconThemeData(
        size: 26,
        color: base.colorScheme.onSurface,
      ),
      iconTheme: IconThemeData(
        size: 26,
        color: base.colorScheme.onSurface,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      // Keep light-theme solid cards from AppTheme (don't re-alpha them).
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      extendedTextStyle: text.labelLarge,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        iconSize: 26,
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
