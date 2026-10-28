import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'documentation_model.dart';
import 'material_catalog.dart';
import 'models.dart';
import 'pdf_fonts.dart';
import 'pdf_plan_import.dart';
import 'project_materials.dart';

/// Keys used to match project certificates to a room's materials.
Set<String> materialKeysForRoom(Room room, Project project) {
  final keys = <String>{'all'};
  final (ceiling, _, cell) = roomEffectiveConfig(room, project);
  if (ceiling == 'Грильято') {
    keys.add('cassette_grilyato');
    keys.add('guide_2400');
    keys.add('guide_1200');
    keys.add('profile_papa_${_cellKey(cell)}');
    keys.add('profile_mama_${_cellKey(cell)}');
  } else if (ceiling == 'GL') {
    keys.add('cassette_gl');
  } else {
    keys.add('armstrong_tile');
    keys.add('guide_3600');
    keys.add('guide_1200');
    keys.add('guide_600');
  }
  keys.add('light_fixture_led');
  keys.add('susp_05');
  keys.add('corner');
  keys.add('connector');
  if (room.lightFixtures.isNotEmpty) keys.add('light_fixture_led');
  if (room.hasLayout) {
    keys.add('finish_floor');
    if (room.materialsCeiling != null) keys.add('finish_ceiling');
  }
  if (room.wallFinishLayers.isNotEmpty) keys.add('finish_wall');
  return keys;
}

String _cellKey(String? cell) {
  return switch (cell) {
    '50x50' => '50',
    '75x75' => '75',
    '100x100' => '100',
    _ => '100',
  };
}

/// Certificates applicable to this room (by material key or «all»).
List<MaterialCertificate> certificatesForRoom(
  ProjectDocumentation doc,
  Room room,
  Project project,
) {
  if (doc.certificates.isEmpty) return const [];
  final keys = materialKeysForRoom(room, project);
  return doc.certificates
      .where((c) => keys.contains(c.materialKey) || c.materialKey == 'all')
      .toList();
}

String certificateMaterialLabel(String materialKey) {
  if (materialKey == 'all') return 'Все материалы';
  if (materialKey == 'finish_floor') return 'Отделка пола';
  if (materialKey == 'finish_wall') return 'Отделка стен';
  if (materialKey == 'finish_ceiling') return 'Отделка потолка';
  return catalogByItemKey(materialKey)?.displayName ?? materialKey;
}

/// Append certificate file pages to an existing PDF document.
Future<void> appendCertificatePages(
  pw.Document pdf, {
  required List<MaterialCertificate> certificates,
  required String roomName,
}) async {
  for (final cert in certificates) {
    final file = File(cert.localPath);
    if (!file.existsSync()) continue;
    final ext = p.extension(cert.localPath).toLowerCase();
    final title = cert.label.isNotEmpty ? cert.label : cert.materialKey;
    if (ext == '.pdf') {
      final pdfBytes = await file.readAsBytes();
      final jpegs = extractEmbeddedJpegsFromPdf(pdfBytes);
      if (jpegs.isNotEmpty) {
        for (var i = 0; i < jpegs.length; i++) {
          final jpeg = jpegs[i];
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(24),
              build: (context) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    i == 0 ? 'Сертификат · $title' : 'Сертификат · $title · ${i + 1}',
                    style: PdfFonts.titleStyle(fontSize: 13),
                  ),
                  pw.Text(
                    '${certificateMaterialLabel(cert.materialKey)} · $roomName',
                    style: PdfFonts.text(fontSize: 9),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Expanded(
                    child: pw.Center(
                      child: pw.Image(pw.MemoryImage(jpeg), fit: pw.BoxFit.contain),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } else {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(28),
            build: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Сертификат · $title',
                  style: PdfFonts.titleStyle(fontSize: 13),
                ),
                pw.Text(
                  '${certificateMaterialLabel(cert.materialKey)} · $roomName',
                  style: PdfFonts.text(fontSize: 9),
                ),
                pw.SizedBox(height: 8),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      'PDF без встроенных изображений.\n'
                      'Файл сохранён в архиве ZIP:\n'
                      'certs/${p.basename(cert.localPath)}\n\n'
                      'Откройте его из папки certs/.',
                      style: PdfFonts.text(fontSize: 10),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } else {
      final bytes = await file.readAsBytes();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Сертификат · $title',
                style: PdfFonts.titleStyle(fontSize: 13),
              ),
              pw.Text(
                certificateMaterialLabel(cert.materialKey),
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
}

/// Copy certificate files into ZIP archive folder `certs/`.
/// Note: `package:pdf` cannot merge external PDF pages into the album;
/// binary PDFs are always shipped under `certs/` for the field archive.
Future<List<(String archivePath, Uint8List bytes)>> certificateArchiveEntries(
  List<MaterialCertificate> certificates,
) async {
  final out = <(String, Uint8List)>[];
  final used = <String>{};
  for (final cert in certificates) {
    final file = File(cert.localPath);
    if (!file.existsSync()) continue;
    final ext = p.extension(cert.localPath);
    final base = (cert.label.isNotEmpty ? cert.label : cert.materialKey)
        .replaceAll(RegExp(r'[^\w\d\-_.]+'), '_');
    var name = '$base$ext';
    var i = 2;
    while (used.contains(name)) {
      name = '${base}_$i$ext';
      i++;
    }
    used.add(name);
    out.add(('certs/$name', await file.readAsBytes()));
  }
  return out;
}
