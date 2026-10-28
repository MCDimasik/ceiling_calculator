import 'package:flutter/material.dart';

/// Shared footprint for «+ Проект», «+ Комната», «+ Этаж».
const kAppExtendedFabWidth = 110.0;
const kAppExtendedFabLabelWidth = 52.0;
const kAppExtendedFabPadding = EdgeInsetsDirectional.only(start: 10, end: 10);
const kAppExtendedFabIconGap = 4.0;

/// Extended FAB with a fixed outer size so labels of different lengths match.
class AppExtendedFab extends StatelessWidget {
  const AppExtendedFab({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
    this.heroTag,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor;
    return SizedBox(
      width: kAppExtendedFabWidth,
      child: FloatingActionButton.extended(
        heroTag: heroTag,
        onPressed: onPressed,
        backgroundColor: backgroundColor,
        foregroundColor: fg,
        extendedPadding: kAppExtendedFabPadding,
        extendedIconLabelSpacing: kAppExtendedFabIconGap,
        icon: Icon(icon, size: 22, color: fg),
        label: SizedBox(
          width: kAppExtendedFabLabelWidth,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
