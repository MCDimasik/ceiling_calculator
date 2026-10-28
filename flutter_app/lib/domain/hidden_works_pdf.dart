import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'as_built_export.dart';
import 'document_qr.dart';
import 'documentation_model.dart';
import 'documentation_photos.dart';
import 'documentation_step_logic.dart';
import 'finish_vedomost.dart';
import 'floor_as_built_export.dart';
import 'pdf_fonts.dart';
import 'pdf_stamp_block.dart';
import 'models.dart';
import 'material_certificates.dart';
import 'room_documentation_status.dart';
import 'wall_as_built_export.dart';

/// PDF pack: checklist + photos for hidden works (акт скрытых работ).
Future<Uint8List> buildHiddenWorksPdf({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  required RoomDocumentationChecklist checklist,
  ProjectDocumentation? projectDoc,
}) async {
  final summary = roomDocumentationSummary(room, project, checklist: checklist);
  final ctx = RoomDocContext.fromRoom(room);
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: room.name);
  final doc = projectDoc ?? ProjectDocumentation.fromJson(project.documentationJson);
  final certs = certificatesForRoom(doc, room, project);
  final qrPayload = buildDocumentQrPayload(
    docType: 'hidden_works',
    projectName: project.name,
    roomName: room.name,
    issuedAt: stampFilled.issueDate,
    documentNumber: stampFilled.documentNumber,
    projectId: project.id,
    roomId: room.id,
  );
  final finishLines = buildFinishVedomostLines(room);
  final pdf = await PdfFonts.newDocument();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Text(
          'Альбом скрытых работ · комплекс отделки',
          style: PdfFonts.titleStyle(fontSize: 16),
        ),
        pw.SizedBox(height: 8),
        ...stampFilled.stampLines(roomName: room.name).map(
              (e) => pw.Text('${e.$1}: ${e.$2}', style: PdfFonts.text(fontSize: 10)),
            ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Сводка: проектирование ${summary.designDone}/${summary.designTotal} · '
          'скрытые ${summary.hiddenWorksDone}/${summary.hiddenWorksTotal}',
          style: PdfFonts.text(fontSize: 10),
        ),
        if (finishLines.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text('Объёмы комплекса отделки', style: PdfFonts.text(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final f in finishLines.where(
            (l) =>
                l.name == 'Площадь' ||
                l.name.startsWith('Площадь') ||
                l.name == 'Проёмы',
          ))
            pw.Text(
              '${f.name}: ${f.quantity} ${f.unit}'.trim(),
              style: PdfFonts.text(fontSize: 9),
            ),
        ],
        if (summary.missingItems.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text('Не закрыто:', style: PdfFonts.text(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          for (final m in summary.missingItems.take(12))
            pw.Text('• $m', style: PdfFonts.text(fontSize: 9)),
        ],
        pw.SizedBox(height: 12),
        pw.Text('Скрытые работы', style: PdfFonts.text(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        ...summary.steps.where((s) => s.step.phase == DocumentationPhase.hiddenWorks).map((s) {
          if (!s.applies) {
            return pw.Text(
              '○ ${s.step.title} — не требуется (${ctx.hiddenWorkSkipReason(s.step.id)})',
              style: PdfFonts.text(fontSize: 9),
            );
          }
          final photos = checklist.photosFor(s.step.id).length;
          return pw.Text(
            '${s.done ? "✓" : "—"} ${s.step.title} · $photos фото · ${s.hint}',
            style: PdfFonts.text(fontSize: 9),
          );
        }),
        if (checklist.notes.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text('Примечания: ${checklist.notes}', style: PdfFonts.text(fontSize: 9)),
        ],
        if (certs.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            'Сертификаты (${certs.length}): ${certs.map((c) => c.label.isNotEmpty ? c.label : c.materialKey).join(', ')}',
            style: PdfFonts.text(fontSize: 9),
          ),
        ],
        pw.SizedBox(height: 8),
        documentQrFooter(payload: qrPayload),
      ],
    ),
  );

  for (final step in DocumentationStep.hiddenWorks) {
    if (!ctx.hiddenWorkApplies(step.id)) continue;
    final paths = checklist.photosFor(step.id);
    if (paths.isEmpty) continue;
    for (var i = 0; i < paths.length; i++) {
      final file = File(paths[i]);
      if (!file.existsSync()) continue;
      final bytes = await file.readAsBytes();
      final caption = photoCaptionFromPath(paths[i]);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(step.title, style: PdfFonts.text(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.Text(
                'Фото ${i + 1} из ${paths.length} · $caption · ${room.name}',
                style: PdfFonts.text(fontSize: 9),
              ),
              pw.SizedBox(height: 8),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  if (certs.isNotEmpty) {
    await appendCertificatePages(pdf, certificates: certs, roomName: room.name);
  }

  return pdf.save();
}

Future<Uint8List> buildCombinedAsBuiltPdf({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  AsBuiltExportOptions options = const AsBuiltExportOptions(),
}) async {
  final ceilingPng = await renderAsBuiltPng(room, options: options);
  final floorPng = await renderFloorPlanPng(room, showWallDims: options.showWallDims);
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: room.name);
  final qrPayload = buildDocumentQrPayload(
    docType: 'as_built_combined',
    projectName: project.name,
    roomName: room.name,
    issuedAt: stampFilled.issueDate,
    documentNumber: stampFilled.documentNumber,
    projectId: project.id,
    roomId: room.id,
  );
  final pdf = await PdfFonts.newDocument();

  void addSchemePage(String title, Uint8List png, String caption) {
    if (png.isEmpty) return;
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pdfGostTitleBlock(stamp: stampFilled, roomName: room.name),
            pw.SizedBox(height: 4),
            pw.Text(title, style: PdfFonts.text(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.Text(caption, style: PdfFonts.text(fontSize: 9)),
            pw.SizedBox(height: 6),
            pw.Expanded(
              child: pw.Center(
                child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  addSchemePage('Исполнительная схема · потолок', ceilingPng, 'Сетка 600×600, направляющие, свет');
  if (options.showFloor) {
    addSchemePage('Исполнительная схема · пол', floorPng, floorPlanCaption(room));
  }

  if (options.showWalls) {
    final wallPng = await renderWallFinishPng(room);
    addSchemePage('Сводка · стены', wallPng, 'Слои отделки и периметр стен');
  }

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pdfGostTitleBlock(stamp: stampFilled, roomName: room.name),
          pw.SizedBox(height: 8),
          documentQrFooter(payload: qrPayload),
        ],
      ),
    ),
  );

  return pdf.save();
}
