import 'package:flutter/material.dart';

/// Soft fill used by expandable section headers (KS-2 rooms, floor groups, …).
Color expandSectionFill(ColorScheme scheme, {bool emphasized = false}) {
  if (emphasized) {
    return scheme.primaryContainer.withValues(alpha: 0.72);
  }
  return scheme.surfaceContainerHighest.withValues(alpha: 0.58);
}

/// Collapsible section header with a soft body + InkWell ripple.
class ExpandSectionHeader extends StatelessWidget {
  const ExpandSectionHeader({
    super.key,
    required this.title,
    required this.expanded,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.emphasized = false,
  });

  final String title;
  final String? subtitle;
  final bool expanded;
  final VoidCallback onTap;
  final Widget? leading;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: expandSectionFill(scheme, emphasized: emphasized),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: ListTile(
        leading: leading ??
            Icon(expanded ? Icons.expand_less : Icons.expand_more),
        title: Text(
          title,
          style: emphasized
              ? const TextStyle(fontWeight: FontWeight.w700)
              : null,
        ),
        subtitle: subtitle == null ? null : Text(subtitle!),
        onTap: onTap,
      ),
    );
  }
}

/// ExpansionTile with soft body; no shape-morph rectangle during expand.
class SoftExpansionTile extends StatelessWidget {
  const SoftExpansionTile({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.leading,
    this.initiallyExpanded = false,
    this.emphasized = false,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final List<Widget> children;
  final bool initiallyExpanded;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = expandSectionFill(scheme, emphasized: emphasized);
    // ClipRRect + flat Border shapes: ExpansionTile's default shape animation
    // draws a hard rectangle behind children while expanding.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: fill,
          elevation: 0,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              backgroundColor: Colors.transparent,
              collapsedBackgroundColor: Colors.transparent,
              // Empty Border = no morphing outline during expand/collapse.
              shape: const Border(),
              collapsedShape: const Border(),
              initiallyExpanded: initiallyExpanded,
              leading: leading,
              title: title,
              subtitle: subtitle,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}
