import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// PC cascade: horizontal action strip clipped to the mid column.
/// Mouse-wheel scrolls sideways; overflow stays under the detail pane.
class DesktopRoomActionsBar extends StatefulWidget {
  const DesktopRoomActionsBar({
    super.key,
    required this.onCreateRoom,
    required this.onBatchRooms,
    required this.onCreateFloor,
    required this.onTypicalFloors,
    this.onCreateSpecialSpace,
  });

  final VoidCallback onCreateRoom;
  final VoidCallback onBatchRooms;
  final VoidCallback onCreateFloor;
  final VoidCallback onTypicalFloors;
  final VoidCallback? onCreateSpecialSpace;

  @override
  State<DesktopRoomActionsBar> createState() => _DesktopRoomActionsBarState();
}

class _DesktopRoomActionsBarState extends State<DesktopRoomActionsBar> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onWheel(PointerScrollEvent event) {
    if (!_scroll.hasClients) return;
    final next = (_scroll.offset + event.scrollDelta.dy)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if (next != _scroll.offset) {
      _scroll.jumpTo(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items =
        <({IconData icon, String label, VoidCallback onTap, bool primary})>[
      (
        icon: Icons.add,
        label: 'Комната',
        onTap: widget.onCreateRoom,
        primary: true,
      ),
      (
        icon: Icons.library_add_outlined,
        label: 'Несколько',
        onTap: widget.onBatchRooms,
        primary: false,
      ),
      (
        icon: Icons.layers_outlined,
        label: 'Этаж',
        onTap: widget.onCreateFloor,
        primary: false,
      ),
      (
        icon: Icons.copy_all_outlined,
        label: 'Типовой',
        onTap: widget.onTypicalFloors,
        primary: false,
      ),
      if (widget.onCreateSpecialSpace != null)
        (
          icon: Icons.alt_route_outlined,
          label: 'Особое',
          onTap: widget.onCreateSpecialSpace!,
          primary: false,
        ),
    ];

    return SizedBox(
      height: 44,
      child: Listener(
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) _onWheel(signal);
        },
        child: Stack(
          children: [
            ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final it = items[i];
                return _DeskActionChip(
                  icon: it.icon,
                  label: it.label,
                  primary: it.primary,
                  onTap: it.onTap,
                );
              },
            ),
            // Soft edge hint that more actions are under the detail pane.
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 28,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.surface.withValues(alpha: 0),
                        scheme.surface.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeskActionChip extends StatelessWidget {
  const _DeskActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.primary,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(6); // Win11-ish, not pill
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
    final style = ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: radius),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    if (primary) {
      return FilledButton(
        onPressed: onTap,
        style: style,
        child: child,
      );
    }
    return FilledButton.tonal(
      onPressed: onTap,
      style: style.copyWith(
        foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
        backgroundColor: WidgetStatePropertyAll(
          scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        ),
      ),
      child: child,
    );
  }
}
