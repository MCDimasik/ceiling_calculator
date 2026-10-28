import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'documentation_model.dart';
import 'pdf_fonts.dart';

/// GOST-style title block for PDF exports (mirrors [drawExportStampBlock] on PNG).
pw.Widget pdfGostTitleBlock({
  required DocumentationStamp stamp,
  required String roomName,
}) {
  final lines = stamp.stampLines(roomName: roomName);
  final left = <(String, String)>[];
  final right = <(String, String)>[];
  for (var i = 0; i < lines.length; i++) {
    if (i.isEven) {
      left.add(lines[i]);
    } else {
      right.add(lines[i]);
    }
  }
  final rows = math.max(left.length, right.length);

  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 0.75, color: PdfColors.grey700),
      color: PdfColors.grey100,
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(stamp.sheetTitle, style: PdfFonts.titleStyle(fontSize: 11)),
            ),
            pw.SizedBox(width: 12),
            _pdfScaleBarHint(stamp.scaleNote),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1),
          },
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
          children: [
            for (var i = 0; i < rows; i++)
              pw.TableRow(
                children: [
                  _stampCell(i < left.length ? left[i] : null),
                  _stampCell(i < right.length ? right[i] : null),
                ],
              ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _stampCell((String, String)? line) {
  if (line == null) return pw.SizedBox();
  final (label, value) = line;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: '$label: ', style: PdfFonts.text(fontSize: 8)),
          pw.TextSpan(
            text: value,
            style: PdfFonts.text(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _pdfScaleBarHint(String scaleNote) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Container(
        width: 72,
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(width: 1.5)),
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text('100 см', style: PdfFonts.text(fontSize: 7)),
      if (scaleNote.isNotEmpty)
        pw.Text(scaleNote, style: PdfFonts.text(fontSize: 7)),
    ],
  );
}
