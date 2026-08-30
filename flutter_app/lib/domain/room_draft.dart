import 'dart:math' as math;

/// Mutable wall-draft state for the room editor (cm).
class RoomDraft {
  RoomDraft({
    List<List<double>>? walls,
    List<double>? cursor,
  })  : walls = walls != null ? walls.map((w) => List<double>.from(w)).toList() : [],
        cursor = cursor != null ? List<double>.from(cursor) : [0, 0];

  final List<List<double>> walls;
  List<double> cursor;
  final List<_Snap> _undo = [];
  final List<_Snap> _redo = [];

  bool get isClosed {
    if (walls.length < 3) return false;
    final start = (walls.first[0], walls.first[1]);
    final end = (walls.last[2], walls.last[3]);
    final dx = end.$1 - start.$1;
    final dy = end.$2 - start.$2;
    return math.sqrt(dx * dx + dy * dy) < 0.1;
  }

  void seedUndoBaseline() {
    _undo
      ..clear()
      ..add(_Snap.from(walls, cursor));
    _redo.clear();
  }

  bool get canUndo => _undo.length > 1;
  bool get canRedo => _redo.isNotEmpty;

  void saveUndo() {
    _undo.add(_Snap.from(walls, cursor));
    _redo.clear();
  }

  bool undo() {
    if (_undo.length <= 1) return false;
    _redo.add(_Snap.from(walls, cursor));
    final prev = _undo.removeLast();
    _apply(prev);
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    _undo.add(_Snap.from(walls, cursor));
    final next = _redo.removeLast();
    _apply(next);
    return true;
  }

  void reset() {
    saveUndo();
    walls.clear();
    cursor = [0, 0];
  }

  void addWall(String direction, double lengthCm) {
    saveUndo();
    final length = (lengthCm * 10).round() / 10.0;
    final x1 = cursor[0];
    final y1 = cursor[1];
    final component = direction.contains('_') ? length / math.sqrt(2) : length;
    late final double x2;
    late final double y2;
    switch (direction) {
      case 'up':
        x2 = x1;
        y2 = y1 + component;
      case 'down':
        x2 = x1;
        y2 = y1 - component;
      case 'left':
        x2 = x1 - component;
        y2 = y1;
      case 'right':
        x2 = x1 + component;
        y2 = y1;
      case 'up_left':
        x2 = x1 - component;
        y2 = y1 + component;
      case 'up_right':
        x2 = x1 + component;
        y2 = y1 + component;
      case 'down_left':
        x2 = x1 - component;
        y2 = y1 - component;
      case 'down_right':
        x2 = x1 + component;
        y2 = y1 - component;
      default:
        return;
    }
    walls.add([x1, y1, x2, y2]);
    cursor = [x2, y2];
  }

  void closeRoom() {
    if (walls.length < 3 || isClosed) return;
    saveUndo();
    final x1 = walls.last[2];
    final y1 = walls.last[3];
    final x2 = walls.first[0];
    final y2 = walls.first[1];
    walls.add([x1, y1, x2, y2]);
    cursor = [x2, y2];
  }

  List<(double, double)> orderedPoints() {
    if (walls.isEmpty) return const [];
    final pts = <(double, double)>[(walls.first[0], walls.first[1])];
    for (final w in walls) {
      pts.add((w[2], w[3]));
    }
    if (pts.length > 1 && pts.first == pts.last) pts.removeLast();
    return pts;
  }

  void _apply(_Snap s) {
    walls
      ..clear()
      ..addAll(s.walls.map((w) => List<double>.from(w)));
    cursor = List<double>.from(s.cursor);
  }
}

class _Snap {
  _Snap(this.walls, this.cursor);
  factory _Snap.from(List<List<double>> walls, List<double> cursor) =>
      _Snap(walls.map((w) => List<double>.from(w)).toList(), List<double>.from(cursor));
  final List<List<double>> walls;
  final List<double> cursor;
}
