import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/project_floors.dart';

/// Top floor switcher: swipe between floors or tap a label.
/// Hidden when the project has only the implicit first floor.
/// Long-press: delete and (for unique floors) make typical.
class FloorPagerChip extends StatelessWidget {
  const FloorPagerChip({
    super.key,
    required this.floors,
    required this.selected,
    required this.onSelected,
    this.onDeleteFloor,
    this.onMakeTypical,
  });

  final List<ProjectFloor> floors;
  final ProjectFloor? selected;
  final ValueChanged<ProjectFloor> onSelected;
  final ValueChanged<ProjectFloor>? onDeleteFloor;
  final ValueChanged<ProjectFloor>? onMakeTypical;

  @override
  Widget build(BuildContext context) {
    final pages = floorsForPager(floors);
    if (!projectHasExplicitFloors(floors) || pages.isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: pages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final f = pages[i];
          final sel = selected?.id == f.id || (selected == null && i == 0);
          return Material(
            color: sel
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelected(f),
              onLongPress: (onDeleteFloor == null && onMakeTypical == null)
                  ? null
                  : () async {
                      onSelected(f);
                      final action = await showModalBottomSheet<String>(
                        context: context,
                        showDragHandle: true,
                        builder: (ctx) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                title: Text(f.pagerLabel),
                                subtitle: Text(
                                  f.isTypicalGroup
                                      ? 'Типовой блок этажей'
                                      : 'Этаж объекта',
                                ),
                              ),
                              if (!f.isTypicalGroup && onMakeTypical != null)
                                ListTile(
                                  leading: const Icon(Icons.copy_all_outlined),
                                  title: const Text('Сделать типовым'),
                                  subtitle: const Text(
                                    'Создать копии этажа с теми же помещениями',
                                  ),
                                  onTap: () =>
                                      Navigator.pop(ctx, 'make_typical'),
                                ),
                              if (onDeleteFloor != null)
                                ListTile(
                                  leading: Icon(
                                    Icons.delete_outline,
                                    color: scheme.error,
                                  ),
                                  title: Text(
                                    f.isTypicalGroup
                                        ? 'Удалить типовой блок'
                                        : 'Удалить этаж',
                                    style: TextStyle(color: scheme.error),
                                  ),
                                  subtitle: const Text(
                                    'Помещения этого этажа будут удалены',
                                  ),
                                  onTap: () => Navigator.pop(ctx, 'delete'),
                                ),
                              ListTile(
                                leading: const Icon(Icons.close),
                                title: const Text('Отмена'),
                                onTap: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                        ),
                      );
                      if (action == 'delete') onDeleteFloor?.call(f);
                      if (action == 'make_typical') onMakeTypical?.call(f);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 120),
                  child: Text(
                    f.pagerLabel,
                    key: ValueKey('${f.id}-${f.pagerLabel}'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Horizontal page swipe over floors; [childBuilder] gets rooms for that floor.
class FloorPageView extends StatefulWidget {
  const FloorPageView({
    super.key,
    required this.floors,
    required this.rooms,
    required this.selected,
    required this.onSelected,
    required this.childBuilder,
  });

  final List<ProjectFloor> floors;
  final List<Room> rooms;
  final ProjectFloor? selected;
  final ValueChanged<ProjectFloor> onSelected;
  final Widget Function(
    BuildContext context,
    ProjectFloor? floor,
    List<Room> rooms,
  ) childBuilder;

  @override
  State<FloorPageView> createState() => _FloorPageViewState();
}

class _FloorPageViewState extends State<FloorPageView> {
  late PageController _controller;

  List<ProjectFloor> get _pages => floorsForPager(widget.floors);

  @override
  void initState() {
    super.initState();
    final pages = _pages;
    var index = 0;
    if (widget.selected != null) {
      final i = pages.indexWhere((f) => f.id == widget.selected!.id);
      if (i >= 0) index = i;
    }
    _controller = PageController(initialPage: index);
  }

  @override
  void didUpdateWidget(covariant FloorPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected?.id != oldWidget.selected?.id &&
        widget.selected != null) {
      final pages = _pages;
      final i = pages.indexWhere((f) => f.id == widget.selected!.id);
      if (i >= 0 &&
          _controller.hasClients &&
          (_controller.page?.round() ?? 0) != i) {
        _controller.animateToPage(
          i,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!projectHasExplicitFloors(widget.floors)) {
      return widget.childBuilder(context, null, widget.rooms);
    }
    final pages = _pages;
    if (pages.isEmpty) {
      return widget.childBuilder(context, null, widget.rooms);
    }
    return PageView.builder(
      controller: _controller,
      itemCount: pages.length,
      onPageChanged: (i) {
        if (i >= 0 && i < pages.length) widget.onSelected(pages[i]);
      },
      itemBuilder: (context, i) {
        final floor = pages[i];
        final rooms = roomsForPagerFloor(
          rooms: widget.rooms,
          floors: widget.floors,
          selected: floor,
          includeSpanningStairwells: true,
        );
        return widget.childBuilder(context, floor, rooms);
      },
    );
  }
}
