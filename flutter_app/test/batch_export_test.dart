import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/act_export.dart';
import 'package:ceiling_calculator/domain/documentation_model.dart';
import 'package:ceiling_calculator/domain/models.dart';
import 'package:archive/archive.dart';
import 'package:ceiling_calculator/domain/project_batch_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final rectWalls = [
    [0.0, 0.0, 600.0, 0.0],
    [600.0, 0.0, 600.0, 600.0],
    [600.0, 600.0, 0.0, 600.0],
    [0.0, 600.0, 0.0, 0.0],
  ];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') {
          return '.';
        }
        return null;
      },
    );
  });

  test('KS-2 template text includes table header', () async {
    final template = await rootBundle.loadString(defaultKs2TemplateAsset);
    final project = Project(name: 'Obj');
    final room = Room(name: 'R', walls: rectWalls, layoutConfirmed: true);
    final text = buildKs2FromTemplate(
      templateJson: template,
      project: project,
      room: room,
      stamp: DocumentationStamp(),
    );
    expect(text, contains('№ п/п'));
    expect(text, contains('Площадь пола'));
  });

  test('KS-2 template PDF is non-empty', () async {
    final template = await rootBundle.loadString(defaultKs2TemplateAsset);
    final project = Project(name: 'Obj');
    final room = Room(name: 'R', walls: rectWalls, layoutConfirmed: true);
    final pdf = await buildKs2MaterialsPdf(
      project: project,
      room: room,
      stamp: DocumentationStamp(),
      templateJson: template,
    );
    expect(pdf.length, greaterThan(100));
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  test('hidden works act template PDF is non-empty', () async {
    final template = await rootBundle.loadString(defaultActHiddenTemplateAsset);
    final project = Project(name: 'Obj');
    final room = Room(name: 'R', walls: rectWalls, layoutConfirmed: true);
    final pdf = await buildHiddenWorksActPdf(
      project: project,
      room: room,
      stamp: DocumentationStamp(),
      checklist: RoomDocumentationChecklist(),
      actNumber: 1,
      templateJson: template,
    );
    expect(pdf.length, greaterThan(100));
  });

  test('batch export packs room with layout', () async {
    final ks2Template = await rootBundle.loadString(defaultKs2TemplateAsset);
    final actTemplate = await rootBundle.loadString(defaultActHiddenTemplateAsset);
    final project = Project(
      name: 'Batch',
      rooms: [
        Room(name: 'R1', walls: rectWalls, layoutConfirmed: true),
      ],
    );
    final result = await exportProjectDocumentationPack(
      project: project,
      doc: ProjectDocumentation(),
      ks2TemplateJson: ks2Template,
      actHiddenTemplateJson: actTemplate,
    );
    expect(result.roomCount, 1);
    expect(result.fileCount, greaterThan(5));
    expect(await result.file.exists(), isTrue);

    final bytes = await result.file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(
      archive.files.any((f) => f.name.contains('layout.dxf')),
      isTrue,
    );
  });
}
