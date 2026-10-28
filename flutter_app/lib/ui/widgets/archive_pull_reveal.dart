import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Telegram-style archive row: hidden by default, pull down / scroll up at top to reveal.
class ArchivePullReveal extends StatefulWidget {
  const ArchivePullReveal({
    super.key,
    required this.archiveTile,
    required this.child,
    this.archiveHeight = 72,
    this.locked = false,
  });

  final Widget archiveTile;
  final Widget child;
  final double archiveHeight;

  /// When true (e.g. list reorder drag), collapse and ignore pull-to-reveal.
  final bool locked;

  @override
  State<ArchivePullReveal> createState() => _ArchivePullRevealState();
}

class _ArchivePullRevealState extends State<ArchivePullReveal> {
  final _scrollController = ScrollController();
  double _reveal = 0;
  bool _snapScheduled = false;

  ScrollPhysics get _physics => const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );

  @override
  void didUpdateWidget(covariant ArchivePullReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.locked && !oldWidget.locked && _reveal > 0) {
      setState(() => _reveal = 0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setReveal(double value) {
    if (widget.locked) return;
    final next = value.clamp(0.0, widget.archiveHeight);
    if ((next - _reveal).abs() < 0.5) return;
    setState(() => _reveal = next);
  }

  void _scheduleSnap() {
    if (_snapScheduled) return;
    _snapScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapScheduled = false;
      if (!mounted) return;
      _snapReveal();
    });
  }

  void _snapReveal() {
    final target =
        _reveal > widget.archiveHeight * 0.35 ? widget.archiveHeight : 0.0;
    if ((target - _reveal).abs() < 0.5) return;
    setState(() => _reveal = target);
  }

  bool get _atListTop =>
      !_scrollController.hasClients || _scrollController.offset <= 0.5;

  void _onWheel(PointerScrollEvent event) {
    if (widget.locked) return;
    if (!_atListTop && _reveal <= 0) return;
    final delta = event.scrollDelta.dy;
    if (delta < 0 && _atListTop) {
      _setReveal(_reveal - delta);
      _scheduleSnap();
    } else if (delta > 0 && _reveal > 0) {
      _setReveal(_reveal - delta);
      _scheduleSnap();
    }
  }

  void _onDragUpdate(double deltaDy) {
    if (widget.locked) return;
    if (!_atListTop && _reveal <= 0) return;
    _setReveal(_reveal + deltaDy);
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (widget.locked) return false;
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (_reveal > 0 && delta > 0 && _atListTop) {
        final shrink = math.min(_reveal, delta);
        _setReveal(_reveal - shrink);
        if (_reveal > 0) return true;
      }
    }

    if (notification is OverscrollNotification) {
      if (notification.overscroll < 0 && notification.metrics.pixels <= 0) {
        _setReveal(_reveal - notification.overscroll);
        return true;
      }
    }

    if (notification is ScrollEndNotification) {
      _snapReveal();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final reveal = widget.locked ? 0.0 : _reveal;
    final revealFactor = widget.archiveHeight > 0
        ? (reveal / widget.archiveHeight).clamp(0.0, 1.0)
        : 0.0;

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) _onWheel(event);
      },
      onPointerMove: (event) {
        if (widget.locked) return;
        if (event.buttons != 1) return;
        if (event.delta.dy > 0 && _atListTop) {
          _onDragUpdate(event.delta.dy);
        } else if (_reveal > 0 && event.delta.dy < 0) {
          _onDragUpdate(event.delta.dy);
        }
      },
      onPointerUp: (_) {
        if (!widget.locked) _snapReveal();
      },
      child: Column(
        children: [
          ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: revealFactor,
              child: SizedBox(
                height: widget.archiveHeight,
                width: double.infinity,
                child: widget.archiveTile,
              ),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: PrimaryScrollController(
                controller: _scrollController,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    physics: _physics,
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                      PointerDeviceKind.stylus,
                    },
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
