import 'package:flutter/material.dart';

import '../data/project_repository.dart';
import 'design_walls_baseline.dart';
import 'finish_capture_impact.dart';
import 'finish_design_baseline.dart';
import 'layout_contour_sync.dart';
import 'models.dart';
import 'opening_remap.dart';
import 'room_scan_import.dart';
import 'wall_polygon_diff.dart';

class CaptureApplyChoice {
  const CaptureApplyChoice({
    required this.apply,
    this.importOpenings = true,
    this.realignGrids = false,
    this.overwriteProjectBaseline = false,
  });

  final bool apply;
  final bool importOpenings;
  final bool realignGrids;
  final bool overwriteProjectBaseline;
}

Future<CaptureApplyChoice?> showCaptureApplyDialog({
  required BuildContext context,
  required Room room,
  required RoomScanImportResult result,
  required WallPolygonDiff diff,
}) async {
  var importOpenings = result.openings.isNotEmpty;
  final impact = computeFinishCaptureImpact(
    room: room,
    newWalls: result.walls,
    newHeightCm: result.ceilingHeightCm,
    newOpenings: importOpenings ? result.openings : null,
  );
  final heightLine = result.ceilingHeightCm != null
      ? 'Высота: ${result.ceilingHeightCm!.round()} см\n'
      : '';
  final diffLine = diff.hasDesignBaseline
      ? '\n${formatWallPolygonDiffSummary(diff)}\n'
      : '\nБазовый проект отделки будет сохранён.\n';
  final openingsLine = result.openings.isNotEmpty
      ? 'Проёмов: ${result.openings.length}\n'
      : '';
  final finishLine = '\n${formatFinishCaptureImpactSummary(impact)}\n';

  var realignGrids = diff.hasSignificantDiff;
  var overwriteBaseline = false;

  return showDialog<CaptureApplyChoice>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Применить к комплексу отделки'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Контур → пол, потолок, стены, проёмы, смета.\n\n'
                'Стен: ${result.walls.length}\n'
                'Площадь: ${result.footprint.areaM2.toStringAsFixed(2)} м²\n'
                'Периметр: ${result.footprint.perimeterM.toStringAsFixed(2)} м\n'
                '$heightLine'
                '$openingsLine'
                '$finishLine'
                '$diffLine',
              ),
              if (result.openings.isNotEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Импортировать проёмы'),
                  subtitle: Text('${result.openings.length} шт. → стены отделки'),
                  value: importOpenings,
                  onChanged: (v) => setLocal(() => importOpenings = v ?? true),
                ),
              if (diff.hasDesignBaseline && diff.hasSignificantDiff)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Подстроить сетки пола и потолка'),
                  subtitle: Text(
                    'Сдвиг ${gridRealignDeltaFromDiff(diff).$1}×${gridRealignDeltaFromDiff(diff).$2} см',
                  ),
                  value: realignGrids,
                  onChanged: (v) => setLocal(() => realignGrids = v ?? false),
                ),
              if (diff.hasDesignBaseline)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Перезаписать проектную базу'),
                  subtitle: const Text(
                    'После применения текущее состояние станет новым «проектом» для сравнения',
                  ),
                  value: overwriteBaseline,
                  onChanged: (v) => setLocal(() => overwriteBaseline = v ?? false),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              CaptureApplyChoice(
                apply: true,
                importOpenings: importOpenings,
                realignGrids: realignGrids,
                overwriteProjectBaseline: overwriteBaseline,
              ),
            ),
            child: const Text('Применить'),
          ),
        ],
      ),
    ),
  );
}

Future<LayoutContourSyncResult> applyCaptureToRoom({
  required Room room,
  required RoomScanImportResult result,
  required CaptureApplyChoice choice,
  required ProjectRepository projects,
}) async {
  if (!choice.apply || result.walls.length < 3) {
    return const LayoutContourSyncResult();
  }

  final oldWalls = room.walls.map((w) => List<double>.from(w)).toList();

  if (!choice.overwriteProjectBaseline) {
    snapshotFinishDesignIfNeeded(room);
  }

  room.walls = result.walls;
  if (result.ceilingHeightCm != null && result.ceilingHeightCm! > 100) {
    room.ceilingHeightCm = result.ceilingHeightCm!;
  }
  if (choice.importOpenings && result.openings.isNotEmpty) {
    room.openings = result.openings.map((o) => o.toJson()).toList();
  } else if (oldWalls.isNotEmpty) {
    remapRoomOpeningsAfterWallChange(room, oldWalls: oldWalls);
  }

  if (choice.realignGrids) {
    final design = readDesignWalls(room);
    final wallDiff = compareWallPolygons(design, result.walls);
    final (dx, dy) = gridRealignDeltaFromDiff(wallDiff);
    if (dx != 0 || dy != 0) {
      if (room.layoutConfirmed) {
        room.gridOffsetX += dx;
        room.gridOffsetY += dy;
      }
      room.floorGridOffsetX += dx;
      room.floorGridOffsetY += dy;
    }
  }

  if (choice.overwriteProjectBaseline) {
    rebaselineFinishDesign(room);
  }

  final sync = syncLayoutFeaturesToContour(room);

  await projects.updateRoom(room);
  return sync;
}

RoomScanImportResult wallsOnlyCaptureResult(List<List<double>> walls) {
  return RoomScanImportResult(walls: walls, source: 'photo');
}

String captureApplySnackBarMessage(
  RoomScanImportResult result,
  CaptureApplyChoice choice,
  Room room, {
  LayoutContourSyncResult? contourSync,
}) {
  final impact = computeFinishCaptureImpact(
    room: room,
    newWalls: result.walls,
    newHeightCm: result.ceilingHeightCm,
    newOpenings: choice.importOpenings ? result.openings : null,
  );
  final parts = <String>['Отделка обновлена · ${result.walls.length} стен'];
  parts.add(formatFinishCaptureCompact(impact));
  if (choice.importOpenings && result.openings.isNotEmpty) {
    parts.add('${result.openings.length} проёмов');
  }
  if (choice.realignGrids) parts.add('сетки подстроены');
  if (choice.overwriteProjectBaseline) parts.add('проект обновлён');
  final syncLabel = contourSync?.summaryRu ?? '';
  if (syncLabel.isNotEmpty) parts.add(syncLabel);
  return parts.join(' · ');
}
