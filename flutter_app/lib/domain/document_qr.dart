import 'package:pdf/widgets.dart' as pw;

import 'pdf_fonts.dart';

/// Local document fingerprint for QR on exports (offline verification).
String buildDocumentQrPayload({
  required String docType,
  required String projectName,
  required String roomName,
  required DateTime issuedAt,
  String documentNumber = '',
  int? projectId,
  int? roomId,
}) {
  final pid = projectId?.toString() ?? '';
  final rid = roomId?.toString() ?? '';
  final num = documentNumber.trim();
  return 'visota|$docType|$pid|$rid|$projectName|$roomName|${issuedAt.toIso8601String()}|$num';
}

pw.Widget documentQrFooter({
  required String payload,
  double size = 52,
}) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('QR · версия документа', style: PdfFonts.text(fontSize: 7)),
          pw.SizedBox(height: 2),
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: payload,
            width: size,
            height: size,
          ),
        ],
      ),
    ],
  );
}
