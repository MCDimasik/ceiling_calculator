import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../adaptive_layout.dart';
import 'long_press_action_barrier.dart';

/// Soft selection disc — not a Material checkbox / “envelope”.
class SelectionDisc extends StatelessWidget {
  const SelectionDisc({
    super.key,
    required this.selected,
    this.size = 28,
  });

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.transparent,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 0 : 1.6,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.28),
                  blurRadius: 8,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: selected
          ? Icon(
              Icons.done_rounded,
              size: size * 0.55,
              color: scheme.onPrimary,
            )
          : null,
    );
  }
}

/// List tile with short-tap open and long-press action overlay (icon buttons).
class LongPressActionTile extends StatefulWidget {
  const LongPressActionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.titleTrailing,
    required this.onOpen,
    required this.onShare,
    this.onDelete,
    this.onRename,
    this.onDuplicate,
    this.onArchive,
    this.onRestore,
    this.onToggleSelect,
    this.selected = false,
    this.selectionMode = false,
    this.reorderIndex,
    this.onReorderHandleActive,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? titleTrailing;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;
  final VoidCallback? onDuplicate;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;

  /// When set, action row shows a “select” disc; used for multi-select.
  final VoidCallback? onToggleSelect;
  final bool selected;
  final bool selectionMode;

  /// When set (inside [ReorderableListView]), first action is a drag handle.
  final int? reorderIndex;

  /// Fired when the reorder handle is pressed / released (before list drag starts).
  final ValueChanged<bool>? onReorderHandleActive;

  @override
  State<LongPressActionTile> createState() => _LongPressActionTileState();
}

class _LongPressActionTileState extends State<LongPressActionTile> {
  bool _actions = false;
  final _token = Object();

  @override
  void initState() {
    super.initState();
    LongPressActionBarrier.instance.bindClose(_token, _hideActions);
  }

  @override
  void dispose() {
    LongPressActionBarrier.instance.unbindClose(_token);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LongPressActionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectionMode && _actions) {
      _hideActions();
    }
  }

  void _showActions() {
    if (widget.selectionMode) {
      widget.onToggleSelect?.call();
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _actions = true);
    LongPressActionBarrier.instance.registerOpen(_token);
  }

  void _hideActions() {
    if (!_actions) return;
    setState(() => _actions = false);
    LongPressActionBarrier.instance.registerClosed(_token);
  }

  Widget _actionIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? backgroundColor,
    Color? foregroundColor,
    Widget? child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final orb = DesktopMetrics.actionOrb(context);
    final iconSize = DesktopMetrics.actionIcon(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor ?? scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: orb,
            height: orb,
            child: child ??
                Icon(
                  icon,
                  size: iconSize,
                  color: foregroundColor ?? scheme.onSurface,
                ),
          ),
        ),
      ),
    );
  }

  Widget _dragHandle(ColorScheme scheme) {
    final index = widget.reorderIndex!;
    final orb = DesktopMetrics.actionOrb(context);
    final iconSize = DesktopMetrics.actionIcon(context);
    return Tooltip(
      message: 'Тяните для порядка',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => widget.onReorderHandleActive?.call(true),
        onPointerUp: (_) => widget.onReorderHandleActive?.call(false),
        onPointerCancel: (_) => widget.onReorderHandleActive?.call(false),
        child: ReorderableDragStartListener(
          index: index,
          child: Material(
            color: scheme.primaryContainer,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: orb,
              height: orb,
              child: Icon(
                Icons.drag_handle,
                size: iconSize,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final tileH = DesktopMetrics.listTileMinHeight(context);
    final tileTall = DesktopMetrics.listTileMinHeightTall(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.42)
          : null,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _actions
            ? SizedBox(
                key: const ValueKey('actions'),
                height: widget.subtitle == null ? tileH : tileTall,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              if (widget.reorderIndex != null) ...[
                                _dragHandle(scheme),
                                const SizedBox(width: 6),
                              ],
                              if (widget.onRename != null) ...[
                                _actionIcon(
                                  icon: Icons.drive_file_rename_outline,
                                  tooltip: 'Имя',
                                  onPressed: () {
                                    _hideActions();
                                    widget.onRename!();
                                  },
                                ),
                                const SizedBox(width: 6),
                              ],
                              if (widget.onDuplicate != null) ...[
                                _actionIcon(
                                  icon: Icons.content_copy,
                                  tooltip: 'Копия',
                                  onPressed: () {
                                    _hideActions();
                                    widget.onDuplicate!();
                                  },
                                ),
                                const SizedBox(width: 6),
                              ],
                              _actionIcon(
                                icon: Icons.share_outlined,
                                tooltip: 'Поделиться',
                                backgroundColor: scheme.primaryContainer,
                                foregroundColor: scheme.onPrimaryContainer,
                                onPressed: () {
                                  _hideActions();
                                  widget.onShare();
                                },
                              ),
                              if (widget.onToggleSelect != null) ...[
                                const SizedBox(width: 6),
                                _actionIcon(
                                  icon: Icons.circle_outlined,
                                  tooltip:
                                      selected ? 'Снять выбор' : 'Выбрать',
                                  backgroundColor: selected
                                      ? scheme.primary
                                      : scheme.surfaceContainerHighest,
                                  foregroundColor: selected
                                      ? scheme.onPrimary
                                      : scheme.onSurface,
                                  child: Center(
                                    child: SelectionDisc(
                                      selected: selected,
                                      size: 22,
                                    ),
                                  ),
                                  onPressed: () {
                                    _hideActions();
                                    widget.onToggleSelect!();
                                  },
                                ),
                              ],
                              if (widget.onArchive != null) ...[
                                const SizedBox(width: 6),
                                _actionIcon(
                                  icon: Icons.archive_outlined,
                                  tooltip: 'В архив',
                                  onPressed: () {
                                    _hideActions();
                                    widget.onArchive!();
                                  },
                                ),
                              ],
                              if (widget.onRestore != null) ...[
                                const SizedBox(width: 6),
                                _actionIcon(
                                  icon: Icons.unarchive_outlined,
                                  tooltip: 'Вернуть',
                                  onPressed: () {
                                    _hideActions();
                                    widget.onRestore!();
                                  },
                                ),
                              ],
                              if (widget.onDelete != null) ...[
                                const SizedBox(width: 6),
                                _actionIcon(
                                  icon: Icons.delete_outline,
                                  tooltip: 'Удалить',
                                  backgroundColor: scheme.error,
                                  foregroundColor: scheme.onError,
                                  onPressed: () {
                                    _hideActions();
                                    widget.onDelete!();
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: _hideActions,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              )
            : ListTile(
                key: const ValueKey('title'),
                minTileHeight: tileH,
                leading: widget.selectionMode || selected
                    ? SelectionDisc(
                        selected: selected,
                        size: DesktopMetrics.of(context) ? 30 : 28,
                      )
                    : widget.leading,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (widget.titleTrailing != null) widget.titleTrailing!,
                  ],
                ),
                subtitle: widget.subtitle != null
                    ? Text(
                        widget.subtitle!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      )
                    : null,
                trailing: widget.selectionMode
                    ? null
                    : Icon(
                        Icons.chevron_right,
                        size: DesktopMetrics.of(context) ? 28 : 24,
                      ),
                onTap: widget.selectionMode
                    ? () => widget.onToggleSelect?.call()
                    : widget.onOpen,
                onLongPress: _showActions,
              ),
      ),
    );
  }
}
