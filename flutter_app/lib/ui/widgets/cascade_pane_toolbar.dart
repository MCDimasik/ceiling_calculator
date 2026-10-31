import 'package:flutter/material.dart';

/// Compact pane toolbar for cascade list columns (projects / rooms).
/// Desktop chrome — not a full mobile [AppBar].
class CascadePaneToolbar extends StatelessWidget
    implements PreferredSizeWidget {
  const CascadePaneToolbar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 48 : 56);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest.withValues(alpha: 0.88),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: subtitle == null ? 47 : 55,
              child: Row(
                children: [
                  if (leading != null) leading!,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  ...actions.map(
                    (a) => IconTheme(
                      data: IconThemeData(
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      child: a,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}
