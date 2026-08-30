import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/finish_model.dart';
import '../domain/master_plan.dart';
import '../domain/models.dart';
import 'widgets/screen_scaffold.dart';

/// Door anchor in world cm (after placement offset + rotation).
class _DoorAnchor {
  const _DoorAnchor({
    required this.roomId,
    required this.openingIndex,
    required this.world,
    required this.wallDir,
  });

  final int roomId;
  final int openingIndex;
  final Offset world;
  final Offset wallDir;
}

/// World ↔ scene mapping shared by painter and hit-test.
class _PlanView {
  _PlanView({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.scale,
    required this.ox,
    required this.oy,
  });

  final double minX, maxX, minY, maxY, scale, ox, oy;

  Offset toScene(Offset world) => Offset(
        ox + (world.dx - minX) * scale,
        oy + (maxY - world.dy) * scale,
      );

  Offset toWorld(Offset scene) => Offset(
        (scene.dx - ox) / scale + minX,
        maxY - (scene.dy - oy) / scale,
      );

  static _PlanView? compute({
    required Project project,
    required MasterPlan plan,
    required Size size,
  }) {
    if (plan.placements.isEmpty) return null;
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final pl in plan.placements) {
      final room = _roomOf(project, pl.roomId);
      if (room == null || !room.hasLayout) continue;
      for (final p in _worldPolygon(room, pl)) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
    }
    if (!minX.isFinite) return null;
    final worldW = (maxX - minX).clamp(1.0, 1e9);
    final worldH = (maxY - minY).clamp(1.0, 1e9);
    final scale = math.min(size.width / worldW, size.height / worldH) * 0.85;
    final ox = (size.width - worldW * scale) / 2;
    final oy = (size.height - worldH * scale) / 2;
    return _PlanView(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      scale: scale,
      ox: ox,
      oy: oy,
    );
  }
}

Room? _roomOf(Project project, int id) {
  for (final r in project.rooms) {
    if (r.id == id) return r;
  }
  return null;
}

Offset _rotateAround(Offset p, Offset origin, double degCw) {
  if (degCw.abs() < 1e-9) return p;
  final rad = degCw * math.pi / 180;
  final c = math.cos(rad);
  final s = math.sin(rad);
  final dx = p.dx - origin.dx;
  final dy = p.dy - origin.dy;
  // Clockwise in standard math coords (y up).
  return Offset(origin.dx + dx * c + dy * s, origin.dy - dx * s + dy * c);
}

Offset _roomLocalOrigin(Room room) {
  var minX = room.walls.first[0];
  var maxX = room.walls.first[0];
  var minY = room.walls.first[1];
  var maxY = room.walls.first[1];
  for (final w in room.walls) {
    for (final x in [w[0], w[2]]) {
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
    }
    for (final y in [w[1], w[3]]) {
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
  }
  return Offset((minX + maxX) / 2, (minY + maxY) / 2);
}

Offset _toWorldPoint(Offset local, Room room, MasterRoomPlacement pl) {
  final origin = _roomLocalOrigin(room);
  final rotated = _rotateAround(local, origin, pl.rotationDeg);
  return Offset(rotated.dx + pl.offsetXCm, rotated.dy + pl.offsetYCm);
}

List<Offset> _worldPolygon(Room room, MasterRoomPlacement pl) {
  final pts = <Offset>[];
  for (final w in room.walls) {
    pts.add(_toWorldPoint(Offset(w[0], w[1]), room, pl));
  }
  final last = room.walls.last;
  final lastPt = _toWorldPoint(Offset(last[2], last[3]), room, pl);
  if (pts.isEmpty || (pts.last - lastPt).distance > 0.5) pts.add(lastPt);
  return pts;
}

bool _pointInPoly(List<Offset> poly, Offset p) {
  var hit = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final yi = poly[i].dy, yj = poly[j].dy;
    final xi = poly[i].dx, xj = poly[j].dx;
    final denom = (yj - yi).abs() < 1e-12 ? 1e-12 : (yj - yi);
    final crosses = ((yi > p.dy) != (yj > p.dy)) &&
        (p.dx < (xj - xi) * (p.dy - yi) / denom + xi);
    if (crosses) hit = !hit;
  }
  return hit;
}

/// Assemble rooms of a project into one object plan.
class MasterPlanScreen extends StatefulWidget {
  const MasterPlanScreen({super.key, required this.projectId});

  final int projectId;

  @override
  State<MasterPlanScreen> createState() => _MasterPlanScreenState();
}

class _MasterPlanScreenState extends State<MasterPlanScreen> {
  Project? _project;
  MasterPlan _plan = MasterPlan();
  bool _loading = true;
  int? _selectedRoomId;
  bool _started = false;
  bool _draggingRoom = false;
  final _transform = TransformationController();
  static const _snapCm = 55.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    if (!mounted) return;
    setState(() {
      _project = project;
      _plan = MasterPlan.fromJson(project?.masterPlanJson);
      _loading = false;
      if (_plan.placements.isEmpty && project != null) {
        var x = 0.0;
        for (final r in project.rooms) {
          if (r.id == null || !r.hasLayout) continue;
          _plan.placements.add(MasterRoomPlacement(roomId: r.id!, offsetXCm: x));
          final (minX, maxX, _, _) = _roomBounds(r);
          x += (maxX - minX) + 40;
        }
      }
    });
  }

  (double, double, double, double) _roomBounds(Room room) {
    var minX = room.walls.first[0];
    var maxX = room.walls.first[0];
    var minY = room.walls.first[1];
    var maxY = room.walls.first[1];
    for (final w in room.walls) {
      for (final x in [w[0], w[2]]) {
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
      }
      for (final y in [w[1], w[3]]) {
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
    }
    return (minX, maxX, minY, maxY);
  }

  Room? _roomById(int id) {
    final p = _project;
    if (p == null) return null;
    return _roomOf(p, id);
  }

  MasterRoomPlacement? _placementOf(int roomId) {
    for (final p in _plan.placements) {
      if (p.roomId == roomId) return p;
    }
    return null;
  }

  List<_DoorAnchor> _doorsFor(Room room, MasterRoomPlacement pl) {
    final out = <_DoorAnchor>[];
    final openings = room.openings.map(RoomOpening.fromJson).toList();
    for (var i = 0; i < openings.length; i++) {
      final o = openings[i];
      if (o.kind != 'door') continue;
      final wi = o.wallIndex;
      if (wi == null || wi < 0 || wi >= room.walls.length) continue;
      final w = room.walls[wi];
      final ax = w[0], ay = w[1], bx = w[2], by = w[3];
      final len = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));
      if (len < 1) continue;
      final ux = (bx - ax) / len;
      final uy = (by - ay) / len;
      final mid = o.offsetAlongWallCm + o.widthCm / 2;
      if (mid < 0 || mid > len) continue;
      final local = Offset(ax + ux * mid, ay + uy * mid);
      final world = _toWorldPoint(local, room, pl);
      final dirLocal = Offset(ux, uy);
      final dirEnd = _toWorldPoint(local + dirLocal, room, pl);
      final wallDir = dirEnd - world;
      out.add(
        _DoorAnchor(
          roomId: room.id!,
          openingIndex: i,
          world: world,
          wallDir: wallDir.distance < 1e-6 ? dirLocal : wallDir / wallDir.distance,
        ),
      );
    }
    return out;
  }

  /// Snap selected room so one of its doors coincides with another room's door.
  bool _trySnapDoors(int movingId) {
    final movingRoom = _roomById(movingId);
    final movingPl = _placementOf(movingId);
    if (movingRoom == null || movingPl == null) return false;

    final mine = _doorsFor(movingRoom, movingPl);
    if (mine.isEmpty) return false;

    _DoorAnchor? bestA;
    _DoorAnchor? bestB;
    var bestDist = _snapCm;

    for (final pl in _plan.placements) {
      if (pl.roomId == movingId) continue;
      final other = _roomById(pl.roomId);
      if (other == null) continue;
      final theirs = _doorsFor(other, pl);
      for (final a in mine) {
        for (final b in theirs) {
          final d = (a.world - b.world).distance;
          if (d < bestDist) {
            bestDist = d;
            bestA = a;
            bestB = b;
          }
        }
      }
    }
    if (bestA == null || bestB == null) return false;

    final dx = bestB.world.dx - bestA.world.dx;
    final dy = bestB.world.dy - bestA.world.dy;
    movingPl.offsetXCm += dx;
    movingPl.offsetYCm += dy;

    final aOpen = RoomOpening.fromJson(movingRoom.openings[bestA.openingIndex]);
    final bRoom = _roomById(bestB.roomId)!;
    final bOpen = RoomOpening.fromJson(bRoom.openings[bestB.openingIndex]);
    if (aOpen.wallIndex != null && bOpen.wallIndex != null) {
      _plan.sharedWalls.removeWhere(
        (s) =>
            (s.roomIdA == movingId && s.roomIdB == bestB!.roomId) ||
            (s.roomIdA == bestB!.roomId && s.roomIdB == movingId),
      );
      _plan.sharedWalls.add(
        MasterSharedWall(
          roomIdA: movingId,
          wallIndexA: aOpen.wallIndex!,
          roomIdB: bestB.roomId,
          wallIndexB: bOpen.wallIndex!,
        ),
      );
    }
    return true;
  }

  Future<void> _persist() async {
    final project = _project;
    if (project?.id == null) return;
    project!.masterPlanJson = _plan.toJson();
    await AppScope.of(context).projects.updateMasterPlan(project.id!, project.masterPlanJson);
  }

  void _addRoom(Room room) {
    if (room.id == null || !room.hasLayout) return;
    if (_plan.placements.any((p) => p.roomId == room.id)) return;
    var x = 0.0;
    for (final pl in _plan.placements) {
      final r = _roomById(pl.roomId);
      if (r == null) continue;
      final (minX, maxX, _, _) = _roomBounds(r);
      x = math.max(x, pl.offsetXCm + (maxX - minX) + 40);
    }
    setState(() {
      _plan.placements.add(MasterRoomPlacement(roomId: room.id!, offsetXCm: x));
      _selectedRoomId = room.id;
    });
    _persist();
  }

  void _nudgeSelected(double dx, double dy) {
    final id = _selectedRoomId;
    if (id == null) return;
    final i = _plan.placements.indexWhere((p) => p.roomId == id);
    if (i < 0) return;
    setState(() {
      _plan.placements[i].offsetXCm += dx;
      _plan.placements[i].offsetYCm += dy;
    });
  }

  void _rotateSelected90() {
    final id = _selectedRoomId;
    if (id == null) return;
    final pl = _placementOf(id);
    if (pl == null) return;
    setState(() {
      pl.rotationDeg = (pl.rotationDeg + 90) % 360;
      // Clear shared walls involving this room — geometry changed.
      _plan.sharedWalls.removeWhere((s) => s.roomIdA == id || s.roomIdB == id);
    });
    _persist();
  }

  double get _totalFloorM2 {
    var sum = 0.0;
    for (final pl in _plan.placements) {
      final r = _roomById(pl.roomId);
      if (r == null || !r.hasLayout) continue;
      sum += _polygonAreaM2(r.walls);
    }
    return sum;
  }

  double _polygonAreaM2(List<List<double>> walls) {
    if (walls.length < 3) return 0;
    final pts = <(double, double)>[];
    for (final w in walls) {
      pts.add((w[0], w[1]));
    }
    pts.add((walls.last[2], walls.last[3]));
    var sum = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      sum += pts[i].$1 * pts[i + 1].$2 - pts[i + 1].$1 * pts[i].$2;
    }
    return sum.abs() / 2.0 / 10000.0;
  }

  int? _hitRoom(Offset scene, Size sceneSize) {
    final project = _project;
    if (project == null || _plan.placements.isEmpty) return null;
    final view = _PlanView.compute(project: project, plan: _plan, size: sceneSize);
    if (view == null) return null;
    final world = view.toWorld(scene);

    // Collect hits; prefer smaller area if overlap, then last drawn.
    int? bestId;
    var bestArea = double.infinity;
    for (final pl in _plan.placements) {
      final room = _roomById(pl.roomId);
      if (room == null || !room.hasLayout) continue;
      final pts = _worldPolygon(room, pl);
      if (!_pointInPoly(pts, world)) continue;
      var area = 0.0;
      for (var i = 0; i < pts.length; i++) {
        final j = (i + 1) % pts.length;
        area += pts[i].dx * pts[j].dy - pts[j].dx * pts[i].dy;
      }
      area = area.abs();
      if (area <= bestArea) {
        bestArea = area;
        bestId = pl.roomId;
      }
    }
    return bestId;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final project = _project;
    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('План объекта')),
        body: const Center(child: Text('Проект не найден')),
      );
    }

    final available = project.rooms
        .where((r) => r.id != null && r.hasLayout && !_plan.placements.any((p) => p.roomId == r.id))
        .toList();

    return ScreenScaffold(
      appBar: AppBar(
        title: Text(_plan.name),
        actions: [
          IconButton(
            tooltip: 'Сохранить',
            onPressed: _persist,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Нажмите комнату, чтобы выбрать. Тяните — двери примагнитятся. '
                  'Щипок = масштаб; пустое место = панорама.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Комнат: ${_plan.placements.length}  ·  '
                  'Стыков по дверям: ${_plan.sharedWalls.length}  ·  '
                  'Пол ≈ ${_totalFloorM2.toStringAsFixed(2)} м²',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (available.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final r in available)
                        ActionChip(
                          label: Text('＋ ${r.name}'),
                          onPressed: () => _addRoom(r),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: const Color(0xFF1A2330),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Match viewport so hit-test and paint share the same space.
                      final sceneSize = Size(
                        math.max(constraints.maxWidth, 1),
                        math.max(constraints.maxHeight, 1),
                      );
                      return Stack(
                        children: [
                          InteractiveViewer(
                            transformationController: _transform,
                            minScale: 0.4,
                            maxScale: 4,
                            // Camera pan only when not dragging a room.
                            panEnabled: !_draggingRoom,
                            scaleEnabled: true,
                            boundaryMargin: const EdgeInsets.all(200),
                            child: SizedBox(
                              width: sceneSize.width,
                              height: sceneSize.height,
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (e) {
                                  final id = _hitRoom(e.localPosition, sceneSize);
                                  setState(() {
                                    _selectedRoomId = id;
                                    _draggingRoom = id != null;
                                  });
                                },
                                onPointerMove: (e) {
                                  if (!_draggingRoom || _selectedRoomId == null) return;
                                  if (e.localDelta == Offset.zero) return;
                                  final view = _PlanView.compute(
                                    project: project,
                                    plan: _plan,
                                    size: sceneSize,
                                  );
                                  if (view == null) return;
                                  // localDelta is already in scene (child) coords under InteractiveViewer.
                                  final worldDx = e.localDelta.dx / view.scale;
                                  final worldDy = -e.localDelta.dy / view.scale;
                                  _nudgeSelected(worldDx, worldDy);
                                },
                                onPointerUp: (_) {
                                  final wasDragging = _draggingRoom;
                                  final id = _selectedRoomId;
                                  setState(() => _draggingRoom = false);
                                  if (wasDragging && id != null) {
                                    setState(() => _trySnapDoors(id));
                                    _persist();
                                  }
                                },
                                onPointerCancel: (_) {
                                  setState(() => _draggingRoom = false);
                                },
                                child: CustomPaint(
                                  size: sceneSize,
                                  painter: _MasterPlanPainter(
                                    project: project,
                                    plan: _plan,
                                    selectedRoomId: _selectedRoomId,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_selectedRoomId != null)
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: Material(
                                color: const Color(0xFF2A3848).withValues(alpha: 0.92),
                                elevation: 2,
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: _rotateSelected90,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.rotate_90_degrees_cw,
                                      size: 20,
                                      color: Color(0xFFFFC857),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedRoomId == null
                          ? 'Выберите комнату · щипок = масштаб'
                          : '«${_roomById(_selectedRoomId!)?.name ?? "—"}» · тяните · ↻ в углу',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (_selectedRoomId != null)
                    IconButton(
                      tooltip: 'Убрать с плана',
                      onPressed: () {
                        setState(() {
                          _plan.sharedWalls.removeWhere(
                            (s) =>
                                s.roomIdA == _selectedRoomId || s.roomIdB == _selectedRoomId,
                          );
                          _plan.placements.removeWhere((p) => p.roomId == _selectedRoomId);
                          _selectedRoomId = null;
                        });
                        _persist();
                      },
                      icon: const Icon(Icons.link_off),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterPlanPainter extends CustomPainter {
  _MasterPlanPainter({
    required this.project,
    required this.plan,
    required this.selectedRoomId,
  });

  final Project project;
  final MasterPlan plan;
  final int? selectedRoomId;

  @override
  void paint(Canvas canvas, Size size) {
    if (plan.placements.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'Добавьте комнаты чипами сверху',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height / 2));
      return;
    }

    final view = _PlanView.compute(project: project, plan: plan, size: size);
    if (view == null) return;

    final doorMarks = <Offset>[];

    for (final pl in plan.placements) {
      final room = _roomOf(project, pl.roomId);
      if (room == null || !room.hasLayout) continue;
      final pts = _worldPolygon(room, pl);
      final selected = pl.roomId == selectedRoomId;
      final path = Path()..moveTo(view.toScene(pts.first).dx, view.toScene(pts.first).dy);
      for (var i = 1; i < pts.length; i++) {
        final m = view.toScene(pts[i]);
        path.lineTo(m.dx, m.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = selected ? const Color(0xFF3D5A80) : const Color(0xFF2A3848)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = selected ? const Color(0xFFFFC857) : const Color(0xFF8FB4D4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.5 : 1.5,
      );

      final c = view.toScene(Offset(
        pts.map((e) => e.dx).reduce((a, b) => a + b) / pts.length,
        pts.map((e) => e.dy).reduce((a, b) => a + b) / pts.length,
      ));
      final tp = TextPainter(
        text: TextSpan(
          text: room.name,
          style: TextStyle(
            color: selected ? const Color(0xFFFFC857) : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 120);
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));

      for (final raw in room.openings) {
        final o = RoomOpening.fromJson(raw);
        if (o.kind != 'door' || o.wallIndex == null) continue;
        final wi = o.wallIndex!;
        if (wi < 0 || wi >= room.walls.length) continue;
        final w = room.walls[wi];
        final ax = w[0], ay = w[1], bx = w[2], by = w[3];
        final len = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));
        if (len < 1) continue;
        final ux = (bx - ax) / len, uy = (by - ay) / len;
        final mid = o.offsetAlongWallCm + o.widthCm / 2;
        doorMarks.add(_toWorldPoint(Offset(ax + ux * mid, ay + uy * mid), room, pl));
      }
    }

    final doorPaint = Paint()..color = const Color(0xFFE07A5F);
    for (final d in doorMarks) {
      canvas.drawCircle(view.toScene(d), 5, doorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MasterPlanPainter old) =>
      old.plan != plan ||
      old.selectedRoomId != selectedRoomId ||
      old.project.rooms != project.rooms;
}
