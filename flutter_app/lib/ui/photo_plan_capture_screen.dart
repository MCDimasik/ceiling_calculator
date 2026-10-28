import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_scope.dart';
import '../domain/design_walls_baseline.dart';
import '../domain/finish_design_baseline.dart';
import '../domain/geometry_capture_apply.dart';
import '../domain/geometry_polygon.dart';
import '../domain/models.dart';
import '../domain/pdf_plan_import.dart';
import '../domain/pdf_vector_walls.dart';
import '../domain/photo_plan.dart';
import '../domain/plan_auto_outline.dart';
import '../domain/plan_orthogonal.dart';
import '../domain/plan_seg_model.dart';
import '../domain/wall_polygon_diff.dart';

enum _PlanMode { corners, autoOutline }

/// Photo/PDF plan → pan/zoom → corners / auto-outline → known wall → rooms.
class PhotoPlanCaptureScreen extends StatefulWidget {
  const PhotoPlanCaptureScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  State<PhotoPlanCaptureScreen> createState() => _PhotoPlanCaptureScreenState();
}

class _PhotoPlanCaptureScreenState extends State<PhotoPlanCaptureScreen> {
  Room? _room;
  int _existingRoomCount = 0;
  bool _loading = true;
  String? _imagePath;
  Uint8List? _imageBytes;
  Size? _imageSize;
  final _transform = TransformationController();

  /// Original PDF (if any) — used for vector wall extraction.
  String? _pdfPath;
  int _pdfPageIndex = 0;
  PdfVectorWalls? _vectorWalls;

  /// Active polygon being edited (image coords).
  final _points = <Offset>[];
  /// Extra closed outlines ready to become rooms.
  final _drafts = <List<Offset>>[];

  int _wallIndex = 0;
  final _lengthCtrl = TextEditingController(text: '400');
  String? _error;
  PolygonFootprint? _preview;
  _PlanMode _mode = _PlanMode.corners;
  bool _orthoDefault = true;
  /// Snap taps to PDF vector wall junctions (toggleable).
  bool _snapToVectorWalls = true;
  bool _autoBusy = false;
  /// PDF page raster / vector extract in progress (blocks UI freezes feel).
  bool _pdfBusy = false;

  /// Dragging a corner (Углы or after Авто).
  int? _dragVertex;
  /// Selected corner for selective delete.
  int? _selectedVertex;

  bool get _supportsCamera =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _hasVectorWalls => _vectorWalls?.isUseful == true;

  double get _viewScale {
    final s = _transform.value.getMaxScaleOnAxis();
    return s.isFinite && s > 1e-6 ? s : 1.0;
  }

  @override
  void dispose() {
    _lengthCtrl.dispose();
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _onTransform() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final project =
        await AppScope.of(context).projects.getProject(widget.projectId);
    Room? room;
    if (project != null) {
      _existingRoomCount = project.rooms.length;
      for (final r in project.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
    if (!mounted) return;
    setState(() {
      _room = room;
      _loading = false;
    });
  }

  Future<void> _setImagePath(
    String path, {
    String? pdfPath,
    int pdfPageIndex = 0,
  }) async {
    setState(() {
      _imagePath = path;
      _imageSize = null;
      _imageBytes = null;
      _pdfPath = pdfPath;
      _pdfPageIndex = pdfPageIndex;
      _vectorWalls = null;
      _points.clear();
      _drafts.clear();
      _preview = null;
      _error = null;
      _transform.value = Matrix4.identity();
    });
    await _decodeImage(path);
    await _tryExtractPdfVectors();
  }

  Future<void> _tryExtractPdfVectors() async {
    final pdf = _pdfPath;
    final size = _imageSize;
    if (pdf == null || size == null) return;
    try {
      final bytes = await File(pdf).readAsBytes();
      final pageIndex = _pdfPageIndex;
      final w = size.width;
      final h = size.height;
      // Heavy PDF parse off the UI isolate — large CAD sheets otherwise freeze.
      final raw = await Isolate.run(
        () => PdfVectorWallExtractor.extractSendable(
          pdfBytes: bytes,
          pageIndex: pageIndex,
          imageWidth: w,
          imageHeight: h,
        ),
      );
      if (!mounted) return;
      setState(() {
        _vectorWalls =
            raw == null ? null : PdfVectorWalls.fromSendable(raw);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _vectorWalls = null);
    }
  }

  Future<void> _pickImage() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      allowMultiple: false,
    );
    if (files.isEmpty || files.first.path == null) return;
    var path = files.first.path!;
    if (path.toLowerCase().endsWith('.pdf')) {
      var pageIndex = 0;
      final pageCount = await countPdfPages(path);
      if (pageCount > 1 && mounted) {
        final picked = await showDialog<int>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Страница PDF'),
            children: [
              for (var i = 0; i < pageCount; i++)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, i),
                  child: Text('Стр. ${i + 1}'),
                ),
            ],
          ),
        );
        if (picked == null) return;
        pageIndex = picked;
      }
      if (!mounted) return;
      setState(() {
        _error = null;
        _pdfBusy = true;
      });
      try {
        final raster = await rasterizePdfPlanPage(path, pageIndex: pageIndex);
        if (raster == null) {
          if (!mounted) return;
          setState(() {
            _pdfBusy = false;
            _error = pdfPlanUnsupportedMessage();
          });
          return;
        }
        final pdfPath = files.first.path!;
        await _setImagePath(raster, pdfPath: pdfPath, pdfPageIndex: pageIndex);
      } finally {
        if (mounted) setState(() => _pdfBusy = false);
      }
      return;
    }
    await _setImagePath(path);
  }

  Future<void> _pickFromCamera() async {
    if (!_supportsCamera) {
      setState(() => _error = 'Камера доступна только в приложении на телефоне');
      return;
    }
    final shot = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 92);
    if (shot == null) return;
    await _setImagePath(shot.path);
  }

  Future<void> _decodeImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size =
          Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageSize = size;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось прочитать изображение');
    }
  }

  Offset? _sceneToImage(Offset scene, Size boxSize) {
    final img = _imageSize;
    if (img == null) return null;
    final fitted = applyBoxFit(BoxFit.contain, img, boxSize);
    final dest = fitted.destination;
    final scale = dest.width / img.width;
    final inset = Offset(
      (boxSize.width - dest.width) / 2,
      (boxSize.height - dest.height) / 2,
    );
    if (scene.dx < inset.dx ||
        scene.dy < inset.dy ||
        scene.dx > inset.dx + dest.width ||
        scene.dy > inset.dy + dest.height) {
      return null;
    }
    final inner = scene - inset;
    return Offset(inner.dx / scale, inner.dy / scale);
  }

  double _hitTolImage() {
    final img = _imageSize;
    if (img == null) return 10;
    // Small enough to place corners on narrow wall nibs when zoomed in.
    return (mathMin(img.width, img.height) * 0.0035).clamp(4.0, 20.0);
  }

  double _junctionSnapTol() {
    final img = _imageSize;
    if (img == null) return 16;
    return (mathMin(img.width, img.height) * 0.008).clamp(8.0, 36.0);
  }

  double mathMin(double a, double b) => a < b ? a : b;

  Offset _orthoFromPrev(Offset p, Offset prev) {
    final dx = p.dx - prev.dx;
    final dy = p.dy - prev.dy;
    if (dx.abs() >= dy.abs()) return Offset(p.dx, prev.dy);
    return Offset(prev.dx, p.dy);
  }

  /// Place a new corner: 90° first (if on), then optional vector-junction snap.
  Offset _placeCorner(Offset tap) {
    var p = tap;
    final prev = _points.isEmpty ? null : _points.last;

    if (_orthoDefault && prev != null) {
      p = _orthoFromPrev(p, prev);
    }

    if (_snapToVectorWalls &&
        _hasVectorWalls &&
        _vectorWalls!.junctions.isNotEmpty) {
      final tol = _junctionSnapTol();
      // Prefer a junction that already keeps a right angle with [prev].
      if (_orthoDefault && prev != null) {
        Offset? best;
        var bestD = tol * tol;
        for (final j in _vectorWalls!.junctions) {
          final axisOk = (j.dx - prev.dx).abs() <= 1.5 ||
              (j.dy - prev.dy).abs() <= 1.5;
          if (!axisOk) continue;
          final d = (j - p).distanceSquared;
          if (d < bestD) {
            bestD = d;
            best = j;
          }
        }
        if (best != null) return best;
        // Snap ortho point to nearest junction, then re-apply 90°.
        final j = _vectorWalls!.snapToJunction(p, tolImg: tol * 0.55);
        if (j != null) return _orthoFromPrev(j, prev);
        return p;
      }
      final j = _vectorWalls!.snapToJunction(p, tolImg: tol);
      if (j != null) return j;
    }
    return p;
  }

  int? _hitVertex(Offset imagePt, {double? tol}) {
    final t = tol ?? _hitTolImage();
    var best = -1;
    var bestD = t * t;
    for (var i = 0; i < _points.length; i++) {
      final d = (_points[i] - imagePt).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best >= 0 ? best : null;
  }

  void _undoLastPoint() {
    if (_points.isEmpty) return;
    setState(() {
      _points.removeLast();
      _selectedVertex = null;
      _wallIndex =
          _wallIndex.clamp(0, _points.isEmpty ? 0 : _points.length - 1);
      _updatePreview();
    });
  }

  void _deleteSelectedVertex() {
    final i = _selectedVertex;
    if (i == null || i < 0 || i >= _points.length) return;
    setState(() {
      _points.removeAt(i);
      _selectedVertex = null;
      _dragVertex = null;
      _wallIndex =
          _wallIndex.clamp(0, _points.isEmpty ? 0 : _points.length - 1);
      _updatePreview();
    });
  }

  void _commitActiveAsDraft() {
    if (_points.length < 3) return;
    final validation = validatePhotoPlanPoints(_points);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _drafts.add(List<Offset>.from(_points));
      _points.clear();
      _selectedVertex = null;
      _dragVertex = null;
      _preview = null;
      _error = null;
    });
  }

  void _mergeLastTwoDrafts() {
    if (_drafts.length < 2) return;
    setState(() {
      final b = _drafts.removeLast();
      final a = _drafts.removeLast();
      _drafts.add(PlanAutoOutline.mergePolygons(a, b));
    });
  }

  void _updatePreview() {
    final validation = validatePhotoPlanPoints(_points);
    if (validation != null || _points.length < 3) {
      _preview = null;
      return;
    }
    final length = double.tryParse(_lengthCtrl.text.replaceAll(',', '.'));
    if (length == null || length <= 0) {
      _preview = null;
      return;
    }
    try {
      final walls = wallsFromPhotoPlan(
        imagePoints: _points,
        wallIndex: _wallIndex,
        wallLengthCm: length,
      );
      _preview = footprintFromWalls(walls);
    } catch (_) {
      _preview = null;
    }
  }

  Future<void> _autoOutlineAt(Offset imagePt) async {
    final bytes = _imageBytes;
    if (bytes == null || _autoBusy) return;
    setState(() {
      _autoBusy = true;
      _error = null;
    });
    try {
      final outline = await PlanAutoOutline.outlineAtTap(
        imageBytes: bytes,
        tapImage: imagePt,
        vectorWalls: _vectorWalls,
      );
      if (!mounted) return;
      if (outline == null || outline.length < 3) {
        final mlHint = PlanSegModel.lastError;
        setState(() {
          _autoBusy = false;
          _error = _hasVectorWalls
              ? 'Не удалось обвести по векторным стенам. '
                  'Тапните в центр комнаты (не на стену/дверь).'
              : (mlHint != null
                  ? '$mlHint\n'
                      'Или тапните ближе к центру комнаты на плане-схеме.'
                  : 'Не удалось обвести помещение. '
                      'Тапните ближе к центру комнаты на плане.');
        });
        return;
      }
      // Soft 90° only — forceAxisAligned collapses L-shapes / nibs into junk.
      var pts = outline;
      if (_orthoDefault) {
        pts = orthogonalizePolygon(pts, magnetDeg: 16);
      }
      setState(() {
        // Multi-room: keep previous closed contour as another room draft.
        if (_points.length >= 3) {
          final v = validatePhotoPlanPoints(_points);
          if (v == null) {
            _drafts.add(List<Offset>.from(_points));
          }
        }
        _points
          ..clear()
          ..addAll(pts);
        _selectedVertex = null;
        _dragVertex = null;
        _wallIndex = 0;
        _autoBusy = false;
        _error = null;
        _updatePreview();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _autoBusy = false;
        _error = 'Автообводка: $e';
      });
    }
  }

  Future<void> _applyAll() async {
    final room = _room;
    if (room?.id == null) return;

    final polygons = <List<Offset>>[
      if (_points.length >= 3) List<Offset>.from(_points),
      ..._drafts,
    ];
    if (polygons.isEmpty) {
      setState(() => _error = 'Нет контуров для создания');
      return;
    }
    for (final p in polygons) {
      final v = validatePhotoPlanPoints(p);
      if (v != null) {
        setState(() => _error = v);
        return;
      }
    }
    final length = double.tryParse(_lengthCtrl.text.replaceAll(',', '.'));
    if (length == null || length <= 0) {
      setState(() => _error = 'Укажите длину стены в см');
      return;
    }

    final projects = AppScope.of(context).projects;
    try {
      // First polygon → current room.
      final walls0 = wallsFromPhotoPlan(
        imagePoints: polygons.first,
        wallIndex: _wallIndex.clamp(0, polygons.first.length - 1),
        wallLengthCm: length,
      );
      final result0 = wallsOnlyCaptureResult(walls0);
      snapshotFinishDesignIfNeeded(room!);
      final diff = compareWallPolygons(readDesignWalls(room), walls0);
      final choice = await showCaptureApplyDialog(
        context: context,
        room: room,
        result: result0,
        diff: diff,
      );
      if (choice == null || !choice.apply || !mounted) return;
      await applyCaptureToRoom(
        room: room,
        result: result0,
        choice: choice,
        projects: projects,
      );

      // Extra polygons → new rooms with auto-names.
      for (var i = 1; i < polygons.length; i++) {
        final name = 'Комната ${_existingRoomCount + i}';
        final created = await projects.createRoom(widget.projectId, name);
        final walls = wallsFromPhotoPlan(
          imagePoints: polygons[i],
          wallIndex: 0,
          wallLengthCm: length,
        );
        created.walls = walls;
        await projects.updateRoom(created);
      }

      if (!mounted) return;
      final extra = polygons.length - 1;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            extra > 0
                ? 'Контур применён · создано ещё $extra комн.'
                : 'Контур комнаты создан',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = _room;
    final preview = _preview;
    final totalRooms = (_points.length >= 3 ? 1 : 0) + _drafts.length;

    return PopScope(
      canPop: _points.isEmpty && _drafts.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Уйти без применения?'),
            content: Text(
              'Черновик: ${_points.length} углов, черновиков ${_drafts.length}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Остаться'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Уйти'),
              ),
            ],
          ),
        );
        if (ok == true && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Фото-план · ${room?.name ?? ''}'),
          actions: [
            if (_imagePath != null)
              IconButton(
                tooltip: 'Сбросить зум',
                onPressed: () =>
                    setState(() => _transform.value = Matrix4.identity()),
                icon: const Icon(Icons.fit_screen),
              ),
          ],
        ),
        body: Stack(
          children: [
            Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (preview != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Text(
                  '≈ ${preview.areaM2.toStringAsFixed(2)} м² · '
                  'периметр ${preview.perimeterM.toStringAsFixed(2)} м'
                  '${_drafts.isNotEmpty ? ' · ещё ${_drafts.length}' : ''}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            if (_imagePath != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    SegmentedButton<_PlanMode>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: _PlanMode.corners,
                          label: Text('Углы'),
                          icon: Icon(Icons.polyline, size: 16),
                        ),
                        ButtonSegment(
                          value: _PlanMode.autoOutline,
                          label: Text('Авто'),
                          icon: Icon(Icons.touch_app_outlined, size: 16),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) =>
                          setState(() => _mode = s.first),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('90°'),
                      selected: _orthoDefault,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      onSelected: (v) => setState(() => _orthoDefault = v),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      tooltip: 'Сохранить комнату и начать следующую',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                      onPressed:
                          _points.length >= 3 ? _commitActiveAsDraft : null,
                      icon: Badge(
                        isLabelVisible: _drafts.isNotEmpty,
                        smallSize: 14,
                        label: Text(
                          '${_drafts.length}',
                          style: const TextStyle(fontSize: 9),
                        ),
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .outlineVariant,
                        textColor: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                        child: const Icon(Icons.add_home_outlined, size: 18),
                      ),
                    ),
                    if (_hasVectorWalls) ...[
                      const SizedBox(width: 2),
                      IconButton(
                        tooltip:
                            'Привязка к углам векторных стен '
                            '(${_vectorWalls!.junctions.length})',
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(32, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: _snapToVectorWalls
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                        ),
                        isSelected: _snapToVectorWalls,
                        onPressed: () => setState(
                          () => _snapToVectorWalls = !_snapToVectorWalls,
                        ),
                        icon: Icon(
                          _snapToVectorWalls
                              ? Icons.link
                              : Icons.link_off,
                          size: 18,
                        ),
                      ),
                    ],
                    if (_autoBusy) ...[
                      const SizedBox(width: 6),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: _imagePath == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Выбрать файл (JPG/PDF)'),
                          ),
                          const SizedBox(height: 8),
                          if (_supportsCamera)
                            OutlinedButton.icon(
                              onPressed: _pickFromCamera,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Сфотографировать план'),
                            ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final boxSize =
                            Size(constraints.maxWidth, constraints.maxHeight);
                        return InteractiveViewer(
                          transformationController: _transform,
                          minScale: 0.15,
                          maxScale: 24,
                          boundaryMargin: const EdgeInsets.all(200),
                          child: SizedBox(
                            width: boxSize.width,
                            height: boxSize.height,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (d) {
                                final scene = d.localPosition;
                                final imgPt = _sceneToImage(scene, boxSize);
                                if (imgPt == null) return;
                                final hit = _hitVertex(imgPt);
                                if (hit != null) {
                                  setState(() {
                                    _selectedVertex =
                                        _selectedVertex == hit ? null : hit;
                                  });
                                  return;
                                }
                                if (_mode == _PlanMode.autoOutline) {
                                  _autoOutlineAt(imgPt);
                                  return;
                                }
                                setState(() {
                                  final p = _placeCorner(imgPt);
                                  _points.add(p);
                                  _selectedVertex = null;
                                  _error = null;
                                  _updatePreview();
                                });
                              },
                              onLongPressStart: (d) {
                                final imgPt =
                                    _sceneToImage(d.localPosition, boxSize);
                                if (imgPt == null) return;
                                final hit = _hitVertex(imgPt);
                                if (hit == null) return;
                                setState(() {
                                  _dragVertex = hit;
                                  _selectedVertex = hit;
                                });
                              },
                              onLongPressMoveUpdate: (d) {
                                final i = _dragVertex;
                                if (i == null) return;
                                final imgPt =
                                    _sceneToImage(d.localPosition, boxSize);
                                if (imgPt == null) return;
                                setState(() {
                                  var p = imgPt;
                                  // 90° first, then optional wall snap (same as tap).
                                  if (_orthoDefault && _points.length >= 3) {
                                    final trial = List<Offset>.from(_points)
                                      ..[i] = p;
                                    Offset? best;
                                    final magnet = _hitTolImage() * 1.4;
                                    var bestD = magnet * magnet;
                                    for (final c
                                        in orthoCornerCandidates(trial, i)) {
                                      final d = (c - p).distanceSquared;
                                      if (d < bestD) {
                                        bestD = d;
                                        best = c;
                                      }
                                    }
                                    if (best != null) p = best;
                                  }
                                  if (_snapToVectorWalls && _hasVectorWalls) {
                                    final tol = _junctionSnapTol() * 0.7;
                                    if (_orthoDefault &&
                                        _points.length >= 3) {
                                      // Keep right angles: only snap to a
                                      // junction that stays on the ortho axes.
                                      final prev = _points[
                                          (i - 1 + _points.length) %
                                              _points.length];
                                      final next = _points[
                                          (i + 1) % _points.length];
                                      Offset? bestJ;
                                      var bestD = tol * tol;
                                      for (final j
                                          in _vectorWalls!.junctions) {
                                        final axisOk =
                                            ((j.dx - prev.dx).abs() <= 1.5 ||
                                                    (j.dy - prev.dy)
                                                            .abs() <=
                                                        1.5) &&
                                                ((j.dx - next.dx).abs() <=
                                                        1.5 ||
                                                    (j.dy - next.dy)
                                                            .abs() <=
                                                        1.5);
                                        if (!axisOk) continue;
                                        final d =
                                            (j - p).distanceSquared;
                                        if (d < bestD) {
                                          bestD = d;
                                          bestJ = j;
                                        }
                                      }
                                      if (bestJ != null) p = bestJ;
                                    } else {
                                      final j =
                                          _vectorWalls!.snapToJunction(
                                        p,
                                        tolImg: tol,
                                      );
                                      if (j != null) p = j;
                                    }
                                  }
                                  _points[i] = p;
                                  _updatePreview();
                                });
                              },
                              onLongPressEnd: (_) {
                                final i = _dragVertex;
                                if (i == null) {
                                  return;
                                }
                                setState(() {
                                  if (_orthoDefault && _points.length >= 3) {
                                    final next =
                                        snapVertexNeighborhoodToRightAngles(
                                      _points,
                                      i,
                                      magnetDeg: 18,
                                    );
                                    _points
                                      ..clear()
                                      ..addAll(next);
                                    _updatePreview();
                                  }
                                  _dragVertex = null;
                                });
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  const ColoredBox(color: Color(0xFFFFFFFF)),
                                  Image.file(
                                    File(_imagePath!),
                                    fit: BoxFit.contain,
                                  ),
                                  CustomPaint(
                                    painter: _PlanOverlayPainter(
                                      points: _points,
                                      drafts: _drafts,
                                      wallIndex: _wallIndex,
                                      imageSize: _imageSize,
                                      boxSize: boxSize,
                                      viewScale: _viewScale,
                                      dragVertex: _dragVertex,
                                      selectedVertex: _selectedVertex,
                                      showAngles: _dragVertex != null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('Углов: ${_points.length}'),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Удалить выбранную точку',
                        onPressed: _selectedVertex == null
                            ? null
                            : _deleteSelectedVertex,
                        icon: const Icon(Icons.delete_outline),
                      ),
                      IconButton(
                        tooltip: 'Отменить угол',
                        onPressed: _points.isEmpty ? null : _undoLastPoint,
                        icon: const Icon(Icons.undo),
                      ),
                      TextButton(
                        onPressed: _points.isEmpty && _drafts.isEmpty
                            ? null
                            : () => setState(() {
                                  _points.clear();
                                  _drafts.clear();
                                  _preview = null;
                                  _wallIndex = 0;
                                  _dragVertex = null;
                                  _selectedVertex = null;
                                  _error = null;
                                }),
                        child: const Text('Сброс'),
                      ),
                      TextButton(
                        onPressed: _pickImage,
                        child: const Text('Другое'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed:
                            _drafts.length >= 2 ? _mergeLastTwoDrafts : null,
                        child: const Text('Объединить'),
                      ),
                      const Spacer(),
                      Text(
                        'Комнат: $totalRooms',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _wallIndex.clamp(
                            0,
                            _points.isEmpty ? 0 : _points.length - 1,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Стена для масштаба',
                            isDense: true,
                          ),
                          items: List.generate(
                            _points.length < 2 ? 1 : _points.length,
                            (i) => DropdownMenuItem(
                              value: i,
                              child: Text('Стена ${i + 1}'),
                            ),
                          ),
                          onChanged: _points.length < 2
                              ? null
                              : (v) => setState(() {
                                    _wallIndex = v ?? 0;
                                    _updatePreview();
                                  }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 96,
                        child: TextField(
                          controller: _lengthCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'см',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(_updatePreview),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: totalRooms >= 1 ? _applyAll : null,
                    child: Text(
                      totalRooms <= 1
                          ? 'Создать контур комнаты'
                          : 'Создать $totalRooms комнат',
                    ),
                  ),
                ],
              ),
            ),
          ],
            ),
            if (_pdfBusy)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Открываю страницу PDF…'),
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

class _PlanOverlayPainter extends CustomPainter {
  _PlanOverlayPainter({
    required this.points,
    required this.drafts,
    required this.wallIndex,
    required this.imageSize,
    required this.boxSize,
    required this.viewScale,
    this.dragVertex,
    this.selectedVertex,
    this.showAngles = false,
  });

  final List<Offset> points;
  final List<List<Offset>> drafts;
  final int wallIndex;
  final Size? imageSize;
  final Size boxSize;
  final double viewScale;
  final int? dragVertex;
  final int? selectedVertex;
  final bool showAngles;

  /// Marker radius in the pre-InteractiveViewer box, capped by plan size so
  /// points never eat a room on a dense sheet, and kept ~constant on screen
  /// when zooming in.
  double get _markerR {
    final img = imageSize;
    final view = viewScale.clamp(0.05, 64.0);
    final fit = img == null
        ? 1.0
        : applyBoxFit(BoxFit.contain, img, boxSize).destination.width /
            img.width;
    // Cap vs plan size at fit zoom; shrink further when zoomed in.
    final planCap = img == null
        ? 1.0
        : (mathMin(img.width, img.height) * 0.00035 * fit).clamp(0.2, 1.0);
    // ~0.95 screen px at any zoom — tiny at max zoom so walls stay visible.
    final screenNice = 0.95 / view;
    return screenNice < planCap ? screenNice : planCap;
  }

  /// Screen-constant label size (like tile dims on ceiling layout).
  double get _labelFont {
    final view = viewScale.clamp(0.05, 64.0);
    // ~13–15 CSS px on screen at any zoom.
    return 14.0 / view;
  }

  double mathMin(double a, double b) => a < b ? a : b;

  Offset? _toDisplay(Offset imagePoint) {
    final img = imageSize;
    if (img == null) return null;
    final fitted = applyBoxFit(BoxFit.contain, img, boxSize);
    final dest = fitted.destination;
    final scale = dest.width / img.width;
    final inset = Offset(
      (boxSize.width - dest.width) / 2,
      (boxSize.height - dest.height) / 2,
    );
    return inset + Offset(imagePoint.dx * scale, imagePoint.dy * scale);
  }

  void _paintPoly(
    Canvas canvas,
    List<Offset> pts, {
    required Color stroke,
    required Color fill,
    int? highlightWall,
    int? liftIndex,
  }) {
    final display = <Offset>[
      for (final p in pts)
        if (_toDisplay(p) case final d?) d,
    ];
    if (display.isEmpty) return;
    final r = _markerR;
    final strokeW = (1.4 / viewScale.clamp(0.05, 64.0)).clamp(0.6, 2.2);
    if (display.length >= 3) {
      final path = Path()..addPolygon(display, true);
      canvas.drawPath(path, Paint()..color = fill);
    }
    final line = Paint()
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < display.length; i++) {
      if (i == display.length - 1 && display.length < 3) break;
      final a = display[i];
      final b = display[(i + 1) % display.length];
      line.color =
          i == highlightWall ? const Color(0xFFFF9800) : stroke;
      canvas.drawLine(a, b, line);
    }
    for (var i = 0; i < display.length; i++) {
      final selected = i == selectedVertex || i == liftIndex;
      final center = display[i];
      final ring = selected ? r * 1.35 : r;
      final core = selected ? r * 0.55 : r * 0.45;
      canvas.drawCircle(
        center,
        ring,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.92)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (strokeW * 0.9).clamp(0.5, 1.4),
      );
      canvas.drawCircle(
        center,
        core.clamp(0.2, 1.6),
        Paint()
          ..color = i == liftIndex
              ? const Color(0xFFFFC857)
              : i == selectedVertex
                  ? const Color(0xFF7E57C2)
                  : const Color(0xFFE53935),
      );
    }
    if (showAngles && pts.length >= 3 && liftIndex != null) {
      // One label only — at the dragged corner (no shadow ghosts).
      final i = liftIndex!;
      final ang = vertexInteriorAngleDeg(pts, i);
      final near90 = (ang - 90).abs() <= 0.25;
      final label = formatVertexAngleLabel(ang);
      final at = display[i];
      final fs = _labelFont;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: near90
                ? const Color(0xFF1B5E20)
                : const Color(0xFF000000),
            fontSize: fs,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pad = fs * 0.22;
      final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          at.dx - tp.width / 2 - pad,
          at.dy - (fs + 4) - pad,
          tp.width + pad * 2,
          tp.height + pad * 2,
        ),
        Radius.circular(pad),
      );
      canvas.drawRRect(
        bg,
        Paint()..color = const Color(0xE6FFFFFF),
      );
      tp.paint(canvas, at + Offset(-tp.width / 2, -(fs + 4)));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in drafts) {
      _paintPoly(
        canvas,
        d,
        stroke: const Color(0xFF66BB6A),
        fill: const Color(0x3366BB6A),
      );
    }
    _paintPoly(
      canvas,
      points,
      stroke: const Color(0xFF1E88E5),
      fill: const Color(0x331E88E5),
      highlightWall: wallIndex,
      liftIndex: dragVertex,
    );
  }

  @override
  bool shouldRepaint(covariant _PlanOverlayPainter old) =>
      old.points != points ||
      old.drafts != drafts ||
      old.wallIndex != wallIndex ||
      old.imageSize != imageSize ||
      old.boxSize != boxSize ||
      old.viewScale != viewScale ||
      old.dragVertex != dragVertex ||
      old.selectedVertex != selectedVertex ||
      old.showAngles != showAngles;
}
