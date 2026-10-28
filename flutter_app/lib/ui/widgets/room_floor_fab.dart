import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_extended_fab.dart';

/// FAB that swipes horizontally between «Комната» and «Этаж».
///
/// In finish module, [onCreateSpecialSpace] enables a vertical swipe-up that
/// reveals a secondary «Нестандарт» button emerging from behind «Комната».
class RoomFloorFab extends StatefulWidget {
  const RoomFloorFab({
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

  /// Finish-only: non-standard space (volume / stairwell).
  final VoidCallback? onCreateSpecialSpace;

  @override
  State<RoomFloorFab> createState() => _RoomFloorFabState();
}

enum _FabMode { room, floor }

class _RoomFloorFabState extends State<RoomFloorFab>
    with TickerProviderStateMixin {
  _FabMode _mode = _FabMode.room;
  bool _pulling = false;
  double _pullDx = 0;
  late final AnimationController _colorCtrl;
  late final AnimationController _specialCtrl;
  /// Soft idle nudge: suggests horizontal swipe (and vertical for «Особое»).
  late final AnimationController _hintCtrl;
  static const _switchPx = 18.0;
  static const _maxSlide = 10.0;
  static const _specialRevealPx = 36.0;
  static const _specialGap = 10.0;

  static const _floorColor = Color(0xFF9B6B9E);
  static const _specialColor = Color(0xFF5B7C99);

  bool get _specialEnabled => widget.onCreateSpecialSpace != null;

  @override
  void initState() {
    super.initState();
    _colorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 0,
    );
    _specialCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 0,
    );
    // ~2.2s motion + ~5s pause between cycles.
    _hintCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7200),
    )..repeat();
  }

  @override
  void dispose() {
    _colorCtrl.dispose();
    _specialCtrl.dispose();
    _hintCtrl.dispose();
    super.dispose();
  }

  /// Tiny translate only — size/colors of the FAB stay the same.
  ///
  /// First ~30% of the 7.2s cycle = motion; remaining ~5s = pause.
  Offset _idleHintOffset() {
    if (_pulling || _specialCtrl.value > 0.05) return Offset.zero;
    const motionEnd = 2200 / 7200; // ≈0.306
    final t = _hintCtrl.value;
    if (t >= motionEnd) return Offset.zero;
    final u = t / motionEnd; // 0..1 within the motion window
    // Gentle L/R then brief U/D — soft amplitude.
    if (u < 0.58) {
      final phase = (u / 0.58) * 2 * math.pi;
      final amp = (u < 0.1 || u > 0.48) ? 0.0 : 1.8;
      return Offset(amp * math.sin(phase), 0);
    }
    if (_mode == _FabMode.room && u > 0.64 && u < 0.88) {
      final v = (u - 0.64) / 0.24;
      final amp = _specialEnabled ? 1.5 : 1.1;
      return Offset(0, -amp * math.sin(v * math.pi));
    }
    return Offset.zero;
  }

  _FabMode get _preview {
    if (!_pulling) return _mode;
    if (_pullDx.abs() > _switchPx) {
      return _mode == _FabMode.room ? _FabMode.floor : _FabMode.room;
    }
    return _mode;
  }

  double get _blend {
    if (_pulling) {
      final towardFloor = _preview == _FabMode.floor;
      final progress = Curves.easeOutCubic.transform(
        (_pullDx.abs() / _switchPx).clamp(0.0, 1.0),
      );
      if (_mode == _FabMode.floor) {
        return towardFloor ? 1.0 : 1.0 - progress;
      }
      return towardFloor ? progress : 0.0;
    }
    return _colorCtrl.value;
  }

  void _endPull() {
    final next = _preview;
    final visual = _blend;
    setState(() {
      _pulling = false;
      _pullDx = 0;
      _mode = next;
    });
    _colorCtrl.value = visual;
    final target = next == _FabMode.floor ? 1.0 : 0.0;
    if ((visual - target).abs() < 0.02) {
      _colorCtrl.value = target;
    } else {
      _colorCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _collapseSpecial() {
    if (_specialCtrl.value > 0) {
      _specialCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInCubic,
      );
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (!_specialEnabled || _mode == _FabMode.floor) return;
    // Negative dy = finger up → reveal; positive dy = down → collapse.
    final delta = -d.delta.dy / _specialRevealPx;
    _specialCtrl.value = (_specialCtrl.value + delta).clamp(0.0, 1.0);
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (!_specialEnabled) return;
    final vy = d.primaryVelocity ?? 0;
    // Fling down closes; fling up opens; otherwise snap by midpoint.
    double snap;
    if (vy > 280) {
      snap = 0;
    } else if (vy < -280) {
      snap = 1;
    } else {
      snap = _specialCtrl.value >= 0.45 ? 1.0 : 0.0;
    }
    _specialCtrl.animateTo(
      snap,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = _preview;
    final isFloor = preview == _FabMode.floor;
    final slide = _pullDx.clamp(-_maxSlide, _maxSlide);
    final label = isFloor ? 'Этаж' : 'Комната';
    final tip = isFloor
        ? 'Нажмите — этаж · удерживайте — типовой · свайп — комната'
        : _specialEnabled
            ? 'Нажмите — комната · вверх — нестандарт · свайп — этаж'
            : 'Нажмите — комната · удерживайте — несколько · свайп — этаж';

    return Tooltip(
      message: tip,
      child: AnimatedBuilder(
        animation: Listenable.merge([_colorCtrl, _specialCtrl, _hintCtrl]),
        builder: (context, _) {
          final blend = _blend;
          final fill =
              Color.lerp(scheme.primaryContainer, _floorColor, blend)!;
          final fg =
              Color.lerp(scheme.onPrimaryContainer, Colors.white, blend)!;
          final reveal = Curves.easeOutCubic.transform(_specialCtrl.value);
          final specialOffsetY = (1.0 - reveal) * 48;
          final specialOpacity = reveal;
          final hint = _idleHintOffset();

          return SizedBox(
            width: kAppExtendedFabWidth,
            // Extra height so the revealed button isn't clipped by Scaffold FAB slot.
            height: 56 + (reveal > 0.01 ? 56 + _specialGap : 0),
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                if (_specialEnabled && reveal > 0.01)
                  Positioned(
                    bottom: 56 + _specialGap,
                    child: Opacity(
                      opacity: specialOpacity,
                      child: Transform.translate(
                        offset: Offset(0, specialOffsetY * 0.35),
                        child: Transform.scale(
                          scale: 0.86 + 0.14 * reveal,
                          alignment: Alignment.bottomCenter,
                          child: GestureDetector(
                            onVerticalDragUpdate: _onVerticalDragUpdate,
                            onVerticalDragEnd: _onVerticalDragEnd,
                            child: AppExtendedFab(
                              heroTag: 'room_special_fab',
                              onPressed: () {
                                widget.onCreateSpecialSpace?.call();
                                _collapseSpecial();
                              },
                              backgroundColor: _specialColor,
                              foregroundColor: Colors.white,
                              icon: Icons.alt_route_outlined,
                              label: 'Особое',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                GestureDetector(
                  onHorizontalDragStart: (_) {
                    _colorCtrl.stop();
                    _collapseSpecial();
                    setState(() {
                      _pulling = true;
                      _pullDx = 0;
                    });
                  },
                  onHorizontalDragUpdate: (d) => setState(() {
                    _pullDx += d.delta.dx;
                  }),
                  onHorizontalDragEnd: (_) => _endPull(),
                  onHorizontalDragCancel: () {
                    final visual = _blend;
                    setState(() {
                      _pulling = false;
                      _pullDx = 0;
                    });
                    _colorCtrl.value = visual;
                    _colorCtrl.animateTo(
                      _mode == _FabMode.floor ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                    );
                  },
                  onVerticalDragUpdate:
                      _specialEnabled ? _onVerticalDragUpdate : null,
                  onVerticalDragEnd:
                      _specialEnabled ? _onVerticalDragEnd : null,
                  onLongPress: () {
                    if (isFloor) {
                      widget.onTypicalFloors();
                    } else {
                      widget.onBatchRooms();
                    }
                  },
                  child: Transform.translate(
                    offset: Offset(
                          (_pulling ? slide * 0.15 : 0) + hint.dx,
                          hint.dy,
                        ),
                    child: AppExtendedFab(
                      heroTag: 'room_floor_fab',
                      onPressed: () {
                        if (isFloor) {
                          widget.onCreateFloor();
                        } else {
                          if (_specialCtrl.value > 0.5) {
                            _collapseSpecial();
                          } else {
                            widget.onCreateRoom();
                          }
                        }
                      },
                      backgroundColor: fill,
                      foregroundColor: fg,
                      icon: isFloor ? Icons.layers_outlined : Icons.add,
                      label: label,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
