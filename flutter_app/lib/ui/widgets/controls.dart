import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Analog-style joystick (parity with Kivy AnalogJoystick).
class AnalogJoystick extends StatefulWidget {
  const AnalogJoystick({
    super.key,
    required this.onDirection,
    this.size = 140,
  });

  final ValueChanged<String> onDirection;
  final double size;

  @override
  State<AnalogJoystick> createState() => _AnalogJoystickState();
}

class _AnalogJoystickState extends State<AnalogJoystick> {
  Offset _knob = Offset.zero;
  static const _dead = 0.35;

  String? _resolve(Offset o) {
    final r = widget.size / 2;
    final nx = o.dx / r;
    final ny = -o.dy / r;
    final mag = math.sqrt(nx * nx + ny * ny);
    if (mag < _dead) return null;
    final angle = math.atan2(ny, nx);
    final deg = angle * 180 / math.pi;
    if (deg >= -22.5 && deg < 22.5) return 'right';
    if (deg >= 22.5 && deg < 67.5) return 'up_right';
    if (deg >= 67.5 && deg < 112.5) return 'up';
    if (deg >= 112.5 && deg < 157.5) return 'up_left';
    if (deg >= 157.5 || deg < -157.5) return 'left';
    if (deg >= -157.5 && deg < -112.5) return 'down_left';
    if (deg >= -112.5 && deg < -67.5) return 'down';
    return 'down_right';
  }

  void _update(Offset local) {
    final c = Offset(widget.size / 2, widget.size / 2);
    var d = local - c;
    final max = widget.size / 2 - 18;
    if (d.distance > max) d = d / d.distance * max;
    setState(() => _knob = d);
  }

  void _end() {
    final dir = _resolve(_knob);
    setState(() => _knob = Offset.zero);
    if (dir != null) widget.onDirection(dir);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: GestureDetector(
        onPanStart: (d) => _update(d.localPosition),
        onPanUpdate: (d) => _update(d.localPosition),
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
        child: CustomPaint(
          painter: _AnalogKnobPainter(
            knob: _knob,
            color: scheme.primary,
            track: scheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}

class _AnalogKnobPainter extends CustomPainter {
  _AnalogKnobPainter({required this.knob, required this.color, required this.track});
  final Offset knob;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, size.width / 2, Paint()..color = track);
    canvas.drawCircle(
      c,
      size.width / 2,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(c + knob, 22, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _AnalogKnobPainter old) => old.knob != knob;
}

enum ArrowDir { left, up, down, right }

/// D-pad: filled pad area + rounded trapezoid keys with depth.
class ArrowJoystick extends StatelessWidget {
  const ArrowJoystick({
    super.key,
    required this.onTick,
    this.onRelease,
    this.size = 96,
  });

  final void Function(double dx, double dy) onTick;
  final VoidCallback? onRelease;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cell = (size / 3).floorToDouble();
    final box = cell * 3;
    Widget empty() => SizedBox(width: cell, height: cell);
    Widget slot(ArrowDir dir, double dx, double dy) {
      return SizedBox(
        width: cell,
        height: cell,
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: HoldRepeatButton(
            direction: dir,
            height: cell,
            trapezoid: true,
            onTick: () => onTick(dx, dy),
            onRelease: onRelease,
          ),
        ),
      );
    }

    return SizedBox(
      width: box,
      height: box,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(box * 0.18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF324558), Color(0xFF1E2834)],
          ),
          border: Border.all(color: const Color(0xFF4A6280), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              empty(),
              slot(ArrowDir.up, 0, 1),
              empty(),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              slot(ArrowDir.left, -1, 0),
              SizedBox(
                width: cell,
                height: cell,
                child: Center(
                  child: Container(
                    width: cell * 0.30,
                    height: cell * 0.30,
                    decoration: BoxDecoration(
                      gradient: const RadialGradient(
                        colors: [Color(0xFF3D5166), Color(0xFF141C26)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF5A7494), width: 1),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x44000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              slot(ArrowDir.right, 1, 0),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              empty(),
              slot(ArrowDir.down, 0, -1),
              empty(),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Hold-to-repeat pad — circle (legacy) or rounded trapezoid.
class HoldRepeatButton extends StatefulWidget {
  const HoldRepeatButton({
    super.key,
    required this.direction,
    required this.onTick,
    this.onRelease,
    this.height = 28,
    this.trapezoid = false,
  });

  final ArrowDir direction;
  final VoidCallback onTick;
  final VoidCallback? onRelease;
  final double height;
  final bool trapezoid;

  @override
  State<HoldRepeatButton> createState() => _HoldRepeatButtonState();
}

class _HoldRepeatButtonState extends State<HoldRepeatButton> {
  Timer? _timer;
  bool _pressed = false;

  void _start() {
    setState(() => _pressed = true);
    widget.onTick();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), () {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => widget.onTick());
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_pressed) setState(() => _pressed = false);
    widget.onRelease?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final fillTop = _pressed ? const Color(0xFF4A6FA5) : const Color(0xFF5E8BC4);
    final fillBottom = _pressed ? const Color(0xFF2E4560) : const Color(0xFF3D5A80);
    return Listener(
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: SizedBox(
        height: h,
        width: double.infinity,
        child: CustomPaint(
          painter: widget.trapezoid
              ? _TrapezoidArrowPainter(
                  direction: widget.direction,
                  fillTop: fillTop,
                  fillBottom: fillBottom,
                  pressed: _pressed,
                )
              : _CircleArrowPainter(direction: widget.direction, color: fillBottom),
        ),
      ),
    );
  }
}

class _TrapezoidArrowPainter extends CustomPainter {
  _TrapezoidArrowPainter({
    required this.direction,
    required this.fillTop,
    required this.fillBottom,
    required this.pressed,
  });
  final ArrowDir direction;
  final Color fillTop;
  final Color fillBottom;
  final bool pressed;

  Path _roundedTrapezoid(Size size) {
    final w = size.width;
    final h = size.height;
    final m = math.min(w, h);
    final outerPad = m * 0.02;
    final innerPad = m * 0.004;
    // Outer base (away from hub); inner base (toward hub) — both wider, shape reaches center.
    final narrow = m * 0.42;
    final wide = m * 1.00;
    final rOuter = m * 0.10;
    final rInner = m * 0.30;

    late Offset a, b, c, d;
    switch (direction) {
      case ArrowDir.up:
        a = Offset(w / 2 - narrow, h - innerPad);
        b = Offset(w / 2 + narrow, h - innerPad);
        c = Offset(w / 2 + wide, outerPad);
        d = Offset(w / 2 - wide, outerPad);
      case ArrowDir.down:
        a = Offset(w / 2 + narrow, innerPad);
        b = Offset(w / 2 - narrow, innerPad);
        c = Offset(w / 2 - wide, h - outerPad);
        d = Offset(w / 2 + wide, h - outerPad);
      case ArrowDir.left:
        a = Offset(w - innerPad, h / 2 - narrow);
        b = Offset(w - innerPad, h / 2 + narrow);
        c = Offset(outerPad, h / 2 + wide);
        d = Offset(outerPad, h / 2 - wide);
      case ArrowDir.right:
        a = Offset(innerPad, h / 2 + narrow);
        b = Offset(innerPad, h / 2 - narrow);
        c = Offset(w - outerPad, h / 2 - wide);
        d = Offset(w - outerPad, h / 2 + wide);
    }
    return _roundQuad(a, b, c, d, [rInner, rInner, rOuter, rOuter]);
  }

  Path _roundQuad(Offset p0, Offset p1, Offset p2, Offset p3, List<double> radii) {
    final pts = [p0, p1, p2, p3];
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final prev = pts[(i + 3) % 4];
      final curr = pts[i];
      final next = pts[(i + 1) % 4];
      final toPrev = prev - curr;
      final toNext = next - curr;
      final lenPrev = toPrev.distance;
      final lenNext = toNext.distance;
      if (lenPrev < 1e-6 || lenNext < 1e-6) continue;
      // Inner base corners (a, b) get a larger cap for pill-shaped inner edge.
      final edgeCap = i < 2 ? 0.52 : 0.45;
      final r = math.min(radii[i], math.min(lenPrev, lenNext) * edgeCap);
      final start = curr + toPrev / lenPrev * r;
      final end = curr + toNext / lenNext * r;
      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }
      path.quadraticBezierTo(curr.dx, curr.dy, end.dx, end.dy);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pad = _roundedTrapezoid(size);
    final bounds = pad.getBounds();

    // Drop shadow for volume.
    canvas.save();
    canvas.translate(0, pressed ? 1.0 : 2.5);
    canvas.drawPath(
      pad,
      Paint()
        ..color = const Color(0x88000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();

    // Gradient fill (lighter toward outer edge).
    final gradient = ui.Gradient.linear(
      _lightOrigin(size),
      _lightEnd(size),
      [fillTop, fillBottom],
    );
    canvas.drawPath(pad, Paint()..shader = gradient);

    // Top bevel highlight.
    canvas.drawPath(
      pad,
      Paint()
        ..color = Colors.white.withValues(alpha: pressed ? 0.08 : 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Inner shadow on base edge.
    canvas.drawPath(
      pad,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final w = size.width;
    final h = size.height;
    final c = bounds.center;
    final s = math.min(w, h) * 0.11;
    final arrow = Path()
      ..moveTo(s * 1.5, 0)
      ..lineTo(-s * 0.8, -s * 1.2)
      ..lineTo(-s * 0.8, -s * 0.4)
      ..lineTo(-s * 1.5, -s * 0.4)
      ..lineTo(-s * 1.5, s * 0.4)
      ..lineTo(-s * 0.8, s * 0.4)
      ..lineTo(-s * 0.8, s * 1.2)
      ..close();
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final nudge = math.min(w, h) * 0.06;
    final shift = switch (direction) {
      ArrowDir.up => Offset(0, -nudge),
      ArrowDir.down => Offset(0, nudge),
      ArrowDir.left => Offset(-nudge, 0),
      ArrowDir.right => Offset(nudge, 0),
    };
    canvas.translate(shift.dx, shift.dy);
    final rot = switch (direction) {
      ArrowDir.right => 0.0,
      ArrowDir.down => math.pi / 2,
      ArrowDir.left => math.pi,
      ArrowDir.up => -math.pi / 2,
    };
    canvas.rotate(rot);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.95)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );
    canvas.restore();
  }

  Offset _lightOrigin(Size size) {
    return switch (direction) {
      ArrowDir.up => Offset(size.width / 2, 0),
      ArrowDir.down => Offset(size.width / 2, size.height),
      ArrowDir.left => Offset(size.width, size.height / 2),
      ArrowDir.right => Offset(0, size.height / 2),
    };
  }

  Offset _lightEnd(Size size) {
    return switch (direction) {
      ArrowDir.up => Offset(size.width / 2, size.height),
      ArrowDir.down => Offset(size.width / 2, 0),
      ArrowDir.left => Offset(0, size.height / 2),
      ArrowDir.right => Offset(size.width, size.height / 2),
    };
  }

  @override
  bool shouldRepaint(covariant _TrapezoidArrowPainter old) =>
      old.direction != direction ||
      old.fillTop != fillTop ||
      old.fillBottom != fillBottom ||
      old.pressed != pressed;
}

class _CircleArrowPainter extends CustomPainter {
  _CircleArrowPainter({required this.direction, required this.color});
  final ArrowDir direction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height) * 0.92;
    final c = Offset(size.width / 2, size.height / 2);
    final r = side / 2;
    canvas.drawCircle(c, r, Paint()..color = color);
    final s = r / 8;
    final arrow = Path()
      ..moveTo(3.5 * s, 0)
      ..lineTo(-0.5 * s, -3 * s)
      ..lineTo(-0.5 * s, -1.2 * s)
      ..lineTo(-3.5 * s, -1.2 * s)
      ..lineTo(-3.5 * s, 1.2 * s)
      ..lineTo(-0.5 * s, 1.2 * s)
      ..lineTo(-0.5 * s, 3 * s)
      ..close();
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final rot = switch (direction) {
      ArrowDir.right => 0.0,
      ArrowDir.down => math.pi / 2,
      ArrowDir.left => math.pi,
      ArrowDir.up => -math.pi / 2,
    };
    canvas.rotate(rot);
    canvas.drawPath(arrow, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CircleArrowPainter old) =>
      old.direction != direction || old.color != color;
}
