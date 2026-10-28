import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Cyrillic-capable fonts for package:pdf (Courier/Helvetica lack Unicode).
class PdfFonts {
  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> ensureLoaded() async {
    if (_regular != null) return;
    _regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Arial-Regular.ttf'));
    _bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Arial-Bold.ttf'));
  }

  static Future<pw.Document> newDocument() async {
    await ensureLoaded();
    return pw.Document(
      theme: pw.ThemeData.withFont(
        base: _regular!,
        bold: _bold!,
      ),
    );
  }

  static pw.TextStyle text({
    double fontSize = 10,
    pw.FontWeight? fontWeight,
  }) =>
      pw.TextStyle(fontSize: fontSize, fontWeight: fontWeight);

  static pw.TextStyle titleStyle({double fontSize = 14}) =>
      pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold);
}
