import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// List tile with short-tap open and long-press Share/Delete overlay (Kivy LongPressTile).
class LongPressActionTile extends StatefulWidget {
  const LongPressActionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
    this.onRename,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback? onRename;

  @override
  State<LongPressActionTile> createState() => _LongPressActionTileState();
}

class _LongPressActionTileState extends State<LongPressActionTile> {
  bool _actions = false;

  void _showActions() {
    HapticFeedback.mediumImpact();
    setState(() => _actions = true);
  }

  void _hideActions() {
    if (_actions) setState(() => _actions = false);
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
                height: widget.subtitle == null ? 72 : 80,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      if (widget.onRename != null)
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () {
                              _hideActions();
                              widget.onRename!();
                            },
                            child: const Text('Имя', textAlign: TextAlign.center),
                          ),
                        ),
                      if (widget.onRename != null) const SizedBox(width: 6),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            _hideActions();
                            widget.onShare();
                          },
                          child: const Text('Поделиться', textAlign: TextAlign.center),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.error,
                            foregroundColor: scheme.onError,
                          ),
                          onPressed: () {
                            _hideActions();
                            widget.onDelete();
                          },
                          child: const Text('Удалить', textAlign: TextAlign.center),
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
                title: Text(widget.title),
                subtitle: widget.subtitle != null ? Text(widget.subtitle!) : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onOpen,
                onLongPress: _showActions,
              ),
      ),
    );
  }
}
