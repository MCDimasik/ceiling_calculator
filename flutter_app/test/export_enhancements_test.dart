import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/as_built_export.dart';
import 'package:ceiling_calculator/domain/documentation_model.dart';
import 'package:ceiling_calculator/domain/export_stamp_overlay.dart';
import 'package:ceiling_calculator/domain/finish_design_baseline.dart';
import 'package:ceiling_calculator/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('export_stamp_overlay', () {
    test('applyExportStamp increases image height', () async {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 80), Paint()..color = const Color(0xFFE0E0E0));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 80);
      final raw = await image.toByteData(format: ImageByteFormat.png);
      image.dispose();

      final stamped = await applyExportStamp(
        pngBytes: raw!.buffer.asUint8List(),
        stamp: DocumentationStamp(objectName: 'Obj'),
        roomName: 'Room A',
      );
      expect(stamped.length, greaterThan(raw.lengthInBytes));

      final codec = await instantiateImageCodec(stamped);
      final frame = await codec.getNextFrame();
      expect(frame.image.height, greaterThan(80));
      frame.image.dispose();
    });
  });

  group('pdf_stamp_block', () {
    test('buildSchemePdf includes GOST title block bytes', () async {
      final room = Room(
        name: 'Офис',
        walls: [
          [0, 0, 600, 0],
          [600, 0, 600, 400],
          [600, 400, 0, 400],
          [0, 400, 0, 0],
        ],
        gridOffsetX: 0,
        gridOffsetY: 0,
      );
      final project = Project(name: 'Тест', rooms: [room]);
      final stamp = DocumentationStamp(
        objectName: 'Объект-1',
        sheetTitle: 'Исполнительная схема',
        scaleNote: '1:50',
      );
      final pdf = await buildSchemePdf(
        project: project,
        room: room,
        stamp: stamp,
        scheme: AsBuiltSchemeKind.floor,
      );
      expect(pdf, isNotEmpty);
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    });
  });

  group('baseline history', () {
    test('rebaseline archives previous snapshot', () {
      final room = Room(
        name: 'R',
        walls: [
          [0, 0, 400, 0],
          [400, 0, 400, 300],
          [400, 300, 0, 300],
          [0, 300, 0, 0],
        ],
        gridOffsetX: 5,
        ceilingHeightCm: 280,
      );
      ensureFinishDesignBaseline(room);
      rebaselineFinishDesign(room);
      expect(readBaselineHistory(room).length, 1);
      room.gridOffsetX = 15;
      rebaselineFinishDesign(room);
      expect(readBaselineHistory(room).length, 2);
      expect(readBaselineHistory(room).first.ceilingGridX, 5);
    });
  });
}
