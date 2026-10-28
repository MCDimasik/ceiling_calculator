import 'dart:convert';

import 'dart:io';

import 'dart:typed_data';



import 'package:archive/archive.dart';

import 'package:path/path.dart' as p;

import 'package:path_provider/path_provider.dart';



import 'act_export.dart';

import 'as_built_export.dart';

import 'cost_calculator.dart';

import 'documentation_model.dart';

import 'document_template_loader.dart';

import 'dxf_export.dart';

import 'floor_as_built_export.dart';

import 'hidden_works_pdf.dart';

import 'layout_layers.dart';

import 'material_certificates.dart';

import 'models.dart';

import 'project_dashboard.dart';

import 'project_export.dart';

import 'project_summary_export.dart';

import 'scheme_png_export.dart';

import 'vedomost_export.dart';



class ProjectBatchExportResult {

  const ProjectBatchExportResult({

    required this.file,

    required this.roomCount,

    required this.fileCount,

    this.warnings = const [],

    this.nextActNumber,

  });



  final File file;

  final int roomCount;

  final int fileCount;

  final List<String> warnings;

  /// Updated act counter after batch (persist to [ProjectDocumentation.nextActNumber]).
  final int? nextActNumber;

}



Future<ProjectBatchExportResult> exportProjectDocumentationPack({
  required Project project,
  required ProjectDocumentation doc,
  Map<String, SupplierPrice>? supplierPrices,
  String? ks2TemplateJson,
  String? actHiddenTemplateJson,
  String? ks3TemplateJson,
  DateTime? periodFrom,
  DateTime? periodTo,
}) async {

  final archive = Archive();

  final warnings = <String>[];

  final dash = buildProjectDashboard(project);



  archive.addFile(

    ArchiveFile(

      '${safeExportBasename(project.name)}_svodka.txt',

      utf8.encode(buildProjectSummaryText(dash)).length,

      utf8.encode(buildProjectSummaryText(dash)),

    ),

  );



  var fileCount = 1;

  var roomCount = 0;

  var actCounter = doc.nextActNumber;



  Future<void> tryExport(String label, Future<void> Function() action) async {

    try {

      await action();

    } catch (e, st) {

      warnings.add('$label: $e');

      assert(() {

        warnings.add('$label stack: $st');

        return true;

      }());

    }

  }



  for (final room in project.rooms) {

    if (!room.hasLayout) continue;

    roomCount++;

    final base = safeExportBasename(room.name);

    final roomStamp = doc.stamp.withDefaults(projectName: project.name, roomName: room.name);

    final checklist = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);

    final roomPrefix = '${room.name}: ';

    final roomActNum = actCounter++;

    final ks2Tpl = ks2TemplateJson ?? await loadKs2TemplateJson(doc, room: room);


    void addText(String name, String text) {

      archive.addFile(ArchiveFile('rooms/$base/$name', text.length, utf8.encode(text)));

      fileCount++;

    }



    addText(

      'vedomost.txt',

      supplierPrices != null && supplierPrices.isNotEmpty

          ? buildVedomostTextWithPricing(

              project: project,

              room: room,

              stamp: roomStamp,

              prices: supplierPrices,

            )

          : buildVedomostText(project: project, room: room, stamp: roomStamp),

    );

    addText(

      'ks2.txt',

      buildKs2FromTemplate(

        templateJson: ks2Tpl,

        project: project,

        room: room,

        stamp: roomStamp,

        prices: supplierPrices,

      ),

    );

    addText('checklist.json', jsonEncode(checklist.toJson()));



    await tryExport('$roomPrefix vedomost.pdf', () async {

      final vedomostPdf = await buildVedomostPdf(

        project: project,

        room: room,

        stamp: roomStamp,

        prices: supplierPrices,

        templateJson: await loadVedomostTemplateJson(doc, room: room),

      );

      if (vedomostPdf.isEmpty) {

        warnings.add('$roomPrefix vedomost.pdf: пустой файл');

        return;

      }

      archive.addFile(ArchiveFile('rooms/$base/vedomost.pdf', vedomostPdf.length, vedomostPdf));

      fileCount++;

    });



    await tryExport('$roomPrefix scheme_combined.pdf', () async {
      final layersRaw = room.layoutViewJson?['layers'];
      final layers = LayoutLayerVisibility.fromJson(
        layersRaw is Map ? Map<String, dynamic>.from(layersRaw) : null,
      );
      final schemeOptions = AsBuiltExportOptions.fromLayoutLayers(layers);

      final combinedPdf = await buildCombinedAsBuiltPdf(

        project: project,

        room: room,

        stamp: roomStamp,

        options: schemeOptions,

      );

      if (combinedPdf.isEmpty) {

        warnings.add('$roomPrefix scheme_combined.pdf: пустой файл');

        return;

      }

      archive.addFile(

        ArchiveFile('rooms/$base/scheme_combined.pdf', combinedPdf.length, combinedPdf),

      );

      fileCount++;

    });



    await tryExport('$roomPrefix act_hidden.pdf', () async {

      final actPdf = await buildHiddenWorksActPdf(

        project: project,

        room: room,

        stamp: roomStamp,

        checklist: checklist,

        actNumber: roomActNum,

        templateJson: await loadActHiddenTemplateJson(doc, room: room),

      );

      if (actPdf.isEmpty) {

        warnings.add('$roomPrefix act_hidden.pdf: пустой файл');

        return;

      }

      archive.addFile(ArchiveFile('rooms/$base/act_hidden.pdf', actPdf.length, actPdf));

      fileCount++;

    });



    await tryExport('$roomPrefix ks2.pdf', () async {

      final ks2Pdf = await buildKs2MaterialsPdf(

        project: project,

        room: room,

        stamp: roomStamp,

        prices: supplierPrices,

        templateJson: await loadKs2TemplateJson(doc, room: room),

      );

      if (ks2Pdf.isEmpty) {

        warnings.add('$roomPrefix ks2.pdf: пустой файл');

        return;

      }

      archive.addFile(ArchiveFile('rooms/$base/ks2.pdf', ks2Pdf.length, ks2Pdf));

      fileCount++;

    });



    await tryExport('$roomPrefix scheme PNG', () async {
      final layersRaw = room.layoutViewJson?['layers'];
      final layers = LayoutLayerVisibility.fromJson(
        layersRaw is Map ? Map<String, dynamic>.from(layersRaw) : null,
      );
      final schemeOptions = AsBuiltExportOptions.fromLayoutLayers(layers);

      for (final kind in AsBuiltSchemeKind.values) {

        final png = await renderStampedSchemePng(

          room: room,

          stamp: roomStamp,

          scheme: kind,

          options: schemeOptions,

        );

        if (png.isEmpty) {

          warnings.add('$roomPrefix ${kind.name}.png: пустой файл');

          continue;

        }

        final name = switch (kind) {

          AsBuiltSchemeKind.ceiling => 'scheme_ceiling.png',

          AsBuiltSchemeKind.floor => 'scheme_floor.png',

          AsBuiltSchemeKind.walls => 'scheme_walls.png',

          AsBuiltSchemeKind.combined => 'scheme_combined.png',

        };

        archive.addFile(ArchiveFile('rooms/$base/$name', png.length, png));

        fileCount++;

      }

    });



    await tryExport('$roomPrefix layout.dxf', () async {
      final grid = gridForDxfExport(room, project);
      final layersRaw = room.layoutViewJson?['layers'];
      final layers = LayoutLayerVisibility.fromJson(
        layersRaw is Map ? Map<String, dynamic>.from(layersRaw) : null,
      );
      final dxf = buildLayoutDxf(
        room: room,
        grid: grid,
        includeGrid: layers.grid,
        includeWalls: layers.walls,
        includeGuides: layers.guides,
        includeLights: layers.lights,
        includeFloor: layers.floor,
        includeNotes: layers.notes,
        includeDimensions: layers.wallDims || layers.tileDims,
      );
      if (dxf.isEmpty) {
        warnings.add('$roomPrefix layout.dxf: пустой файл');
        return;
      }
      archive.addFile(ArchiveFile('rooms/$base/layout.dxf', dxf.length, dxf));
      fileCount++;
    });


    if (checklist.stepPhotos.values.any((l) => l.isNotEmpty) ||

        checklist.hiddenWorksConfirmed.isNotEmpty) {

      await tryExport('$roomPrefix hidden_works.pdf', () async {

        final hwPdf = await buildHiddenWorksPdf(

          project: project,

          room: room,

          stamp: roomStamp,

          checklist: checklist,

          projectDoc: doc,

        );

        if (hwPdf.isEmpty) {

          warnings.add('$roomPrefix hidden_works.pdf: пустой файл');

          return;

        }

        archive.addFile(ArchiveFile('rooms/$base/hidden_works.pdf', hwPdf.length, hwPdf));

        fileCount++;

      });

    }



    addText(

      'act_hidden.txt',

      buildHiddenWorksActText(

        project: project,

        room: room,

        stamp: roomStamp,

        checklist: checklist,

        actNumber: roomActNum,

      ),

    );



    final roomCerts = certificatesForRoom(doc, room, project);

    for (final cert in roomCerts) {

      final file = File(cert.localPath);

      if (!file.existsSync()) {

        warnings.add('$roomPrefix cert ${cert.label}: файл не найден');

        continue;

      }

      final bytes = await file.readAsBytes();

      final label = safeExportBasename(cert.label.isNotEmpty ? cert.label : cert.materialKey);

      final ext = p.extension(cert.localPath);

      archive.addFile(ArchiveFile('rooms/$base/certs/$label$ext', bytes.length, bytes));

      fileCount++;

    }



    for (final photoEntry in checklist.stepPhotos.entries) {

      final stepId = safeExportBasename(photoEntry.key);

      for (var pi = 0; pi < photoEntry.value.length; pi++) {

        final photoPath = photoEntry.value[pi];

        final file = File(photoPath);

        if (!file.existsSync()) {

          warnings.add('$roomPrefix photo $stepId #$pi: файл не найден');

          continue;

        }

        final bytes = await file.readAsBytes();

        final ext = p.extension(photoPath);

        archive.addFile(

          ArchiveFile(

            'rooms/$base/photos/${stepId}_$pi$ext',

            bytes.length,

            bytes,

          ),

        );

        fileCount++;

      }

    }

  }



  for (final entry in await certificateArchiveEntries(doc.certificates)) {

    archive.addFile(ArchiveFile(entry.$1, entry.$2.length, entry.$2));

    fileCount++;

  }

  final now = DateTime.now();
  final ks3From = periodFrom ?? DateTime(now.year, now.month, 1);
  final ks3To = periodTo ?? now;
  final ks3Tpl = ks3TemplateJson ?? await loadKs3TemplateJson(doc);
  final projectStamp = doc.stamp.withDefaults(projectName: project.name, roomName: '');

  await tryExport('KS-3 PDF', () async {
    final ks3Pdf = await buildKs3MaterialsPdf(
      project: project,
      stamp: projectStamp,
      periodFrom: ks3From,
      periodTo: ks3To,
      templateJson: ks3Tpl,
      prices: supplierPrices,
    );
    if (ks3Pdf.isEmpty) {
      warnings.add('ks3.pdf: пустой файл');
      return;
    }
    archive.addFile(ArchiveFile('ks3.pdf', ks3Pdf.length, ks3Pdf));
    fileCount++;
  });

  final ks3Text = buildKs3FromTemplate(
    templateJson: ks3Tpl,
    project: project,
    stamp: projectStamp,
    periodFrom: ks3From,
    periodTo: ks3To,
    prices: supplierPrices,
  );
  archive.addFile(ArchiveFile('ks3.txt', ks3Text.length, utf8.encode(ks3Text)));
  fileCount++;

  if (doc.ks2Acts.isNotEmpty) {
    final ledgerJson = jsonEncode(doc.ks2Acts.map((a) => a.toJson()).toList());
    archive.addFile(ArchiveFile('ks2_ledger.json', ledgerJson.length, utf8.encode(ledgerJson)));
    fileCount++;
  }

  if (warnings.isNotEmpty) {

    final report = StringBuffer('Отчёт экспорта · ${project.name}\n\n');

    for (final w in warnings) {

      report.writeln('• $w');

    }

    final reportText = report.toString();

    archive.addFile(

      ArchiveFile('export_warnings.txt', reportText.length, utf8.encode(reportText)),

    );

    fileCount++;

  }



  final encoded = ZipEncoder().encode(archive);

  final dir = await getTemporaryDirectory();

  final out = File(p.join(dir.path, '${safeExportBasename(project.name)}_docs.zip'));

  await out.writeAsBytes(encoded);

  return ProjectBatchExportResult(

    file: out,

    roomCount: roomCount,

    fileCount: fileCount,

    warnings: warnings,

    nextActNumber: actCounter,

  );

}



Future<Uint8List> encodeProjectBatchPreview(Project project) async {

  final lines = <String>[

    'Пакет документации · ${project.name}',

    'Комнат с чертежом: ${project.rooms.where((r) => r.hasLayout).length}',

    for (final r in project.rooms.where((r) => r.hasLayout)) '• ${r.name}',

  ];

  return Uint8List.fromList(utf8.encode(lines.join('\n')));

}


