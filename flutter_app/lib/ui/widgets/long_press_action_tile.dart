import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'long_press_action_barrier.dart';

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

  void _showActions() {
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
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor ?? scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 22,
              color: foregroundColor ?? scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dragHandle(ColorScheme scheme) {
    final index = widget.reorderIndex!;
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
              width: 44,
              height: 44,
              child: Icon(
                Icons.drag_handle,
                size: 22,
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _actions
            ? SizedBox(
                key: const ValueKey('actions'),
                height: widget.subtitle == null ? 72 : 88,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      if (widget.reorderIndex != null) ...[
                        _dragHandle(scheme),
                        const SizedBox(width: 6),
                      ],
                      if (widget.onRename != null)
                        _actionIcon(
                          icon: Icons.drive_file_rename_outline,
                          tooltip: 'Имя',
                          onPressed: () {
                            _hideActions();
                            widget.onRename!();
                          },
                        ),
                      if (widget.onRename != null) const SizedBox(width: 6),
                      if (widget.onDuplicate != null)
                        _actionIcon(
                          icon: Icons.content_copy,
                          tooltip: 'Копия',
                          onPressed: () {
                            _hideActions();
                            widget.onDuplicate!();
                          },
                        ),
                      if (widget.onDuplicate != null) const SizedBox(width: 6),
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
                      const Spacer(),
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
                minTileHeight: 72,
                leading: widget.leading,
                title: Row(
                  children: [
                    Expanded(child: Text(widget.title)),
                    if (widget.titleTrailing != null) widget.titleTrailing!,
                  ],
                ),
                subtitle: widget.subtitle != null ? Text(widget.subtitle!) : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onOpen,
                onLongPress: _showActions,
              ),
      ),
    );
  }
}
