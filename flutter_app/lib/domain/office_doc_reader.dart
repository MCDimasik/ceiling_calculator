import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'xlsx_export.dart' show buildSimpleXlsx;

/// Supported office extensions for project document import.
const projectDocImportExtensions = [
  'pdf',
  'txt',
  'text',
  'csv',
  'xlsx',
  'xls',
  'docx',
  'doc',
];

class OfficeReadResult {
  const OfficeReadResult({
    required this.text,
    this.tableRows = const [],
    this.format = '',
    this.warning = '',
  });

  final String text;
  final List<List<String>> tableRows;
  final String format;
  final String warning;

  bool get ok => text.isNotEmpty || tableRows.isNotEmpty;
}

/// Read plain text / table rows from office document bytes (not PDF).
OfficeReadResult readProjectDocumentBytes(Uint8List bytes, String filename) {
  final low = filename.toLowerCase();
  if (low.endsWith('.xlsx')) {
    return _readXlsx(bytes);
  }
  if (low.endsWith('.xls')) {
    return const OfficeReadResult(
      text: '',
      format: 'xls',
      warning: 'Формат .xls не поддерживается. Сохраните файл как .xlsx в Excel.',
    );
  }
  if (low.endsWith('.docx')) {
    return _readDocx(bytes);
  }
  if (low.endsWith('.doc')) {
    return const OfficeReadResult(
      text: '',
      format: 'doc',
      warning: 'Формат .doc не поддерживается. Сохраните файл как .docx в Word.',
    );
  }
  final text = _decodePlainText(bytes);
  return OfficeReadResult(text: text, format: 'text');
}

String _decodePlainText(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes, allowInvalid: true);
  }
}

OfficeReadResult _readXlsx(Uint8List bytes) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return const OfficeReadResult(
      text: '',
      format: 'xlsx',
      warning: 'Не удалось прочитать XLSX (повреждённый архив).',
    );
  }

  final shared = _readSharedStrings(archive);
  final sheetPath = _firstWorksheetPath(archive);
  if (sheetPath == null) {
    return const OfficeReadResult(
      text: '',
      format: 'xlsx',
      warning: 'В XLSX не найден лист.',
    );
  }

  final sheetFile = archive.findFile(sheetPath);
  if (sheetFile == null) {
    return const OfficeReadResult(text: '', format: 'xlsx', warning: 'Лист XLSX пуст.');
  }

  final sheetXml = utf8.decode(sheetFile.content as List<int>, allowMalformed: true);
  final rows = _parseWorksheetRows(sheetXml, shared);
  final text = _rowsToText(rows);
  return OfficeReadResult(text: text, tableRows: rows, format: 'xlsx');
}

OfficeReadResult _readDocx(Uint8List bytes) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return const OfficeReadResult(
      text: '',
      format: 'docx',
      warning: 'Не удалось прочитать DOCX (повреждённый архив).',
    );
  }

  final docFile = archive.findFile('word/document.xml');
  if (docFile == null) {
    return const OfficeReadResult(text: '', format: 'docx', warning: 'В DOCX нет document.xml.');
  }

  final xml = utf8.decode(docFile.content as List<int>, allowMalformed: true);
  final text = _extractDocxText(xml);
  return OfficeReadResult(text: text, format: 'docx');
}

String? _firstWorksheetPath(Archive archive) {
  for (final f in archive.files) {
    final name = f.name;
    if (name.startsWith('xl/worksheets/sheet') && name.endsWith('.xml')) {
      return name;
    }
  }
  return null;
}

List<String> _readSharedStrings(Archive archive) {
  final file = archive.findFile('xl/sharedStrings.xml');
  if (file == null) return [];
  final xml = utf8.decode(file.content as List<int>, allowMalformed: true);
  final out = <String>[];
  final siRe = RegExp(r'<si\b[^>]*>([\s\S]*?)</si>', caseSensitive: false);
  for (final si in siRe.allMatches(xml)) {
    final block = si.group(1) ?? '';
    final parts = RegExp(r'<t[^>]*>([\s\S]*?)</t>', caseSensitive: false)
        .allMatches(block)
        .map((m) => _xmlUnescape(m.group(1) ?? ''))
        .join();
    out.add(parts);
  }
  return out;
}

List<List<String>> _parseWorksheetRows(String xml, List<String> shared) {
  final rows = <List<String>>[];
  final rowRe = RegExp(r'<row\b[^>]*>([\s\S]*?)</row>', caseSensitive: false);
  for (final rowMatch in rowRe.allMatches(xml)) {
    final rowXml = rowMatch.group(1) ?? '';
    final cells = <int, String>{};
    final cellRe = RegExp(r'<c\b([^>]*)(?:/>|>([\s\S]*?)</c>)', caseSensitive: false);
    for (final cellMatch in cellRe.allMatches(rowXml)) {
      final attrs = cellMatch.group(1) ?? '';
      final body = cellMatch.group(2) ?? '';
      final ref = RegExp(r'\br="([A-Z]+)(\d+)"').firstMatch(attrs);
      if (ref == null) continue;
      final col = _colIndex(ref.group(1)!);
      final tMatch = RegExp(r'\bt="([^"]+)"').firstMatch(attrs);
      final cellType = tMatch?.group(1);
      var value = '';
      if (cellType == 'inlineStr') {
        value = RegExp(r'<t[^>]*>([\s\S]*?)</t>', caseSensitive: false)
                .firstMatch(body)
                ?.group(1) ??
            '';
        value = _xmlUnescape(value);
      } else {
        final v = RegExp(r'<v>([\s\S]*?)</v>', caseSensitive: false).firstMatch(body)?.group(1);
        if (v == null) continue;
        if (cellType == 's') {
          final idx = int.tryParse(v.trim());
          if (idx != null && idx >= 0 && idx < shared.length) {
            value = shared[idx];
          }
        } else {
          value = v.trim();
        }
      }
      cells[col] = value.trim();
    }
    if (cells.isEmpty) continue;
    final maxCol = cells.keys.reduce((a, b) => a > b ? a : b);
    final row = List<String>.generate(maxCol + 1, (i) => cells[i] ?? '');
    while (row.isNotEmpty && row.last.isEmpty) {
      row.removeLast();
    }
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
  }
  return rows;
}

int _colIndex(String letters) {
  var n = 0;
  for (var i = 0; i < letters.length; i++) {
    n = n * 26 + (letters.codeUnitAt(i) - 64);
  }
  return n - 1;
}

String _rowsToText(List<List<String>> rows) {
  final buf = StringBuffer();
  for (final row in rows) {
    buf.writeln(row.join('\t'));
  }
  return buf.toString().trim();
}

String _extractDocxText(String xml) {
  final buf = StringBuffer();
  final pRe = RegExp(r'<w:p\b[^>]*>([\s\S]*?)</w:p>', caseSensitive: false);
  for (final p in pRe.allMatches(xml)) {
    final block = p.group(1) ?? '';
    final texts = RegExp(r'<w:t[^>]*>([\s\S]*?)</w:t>', caseSensitive: false)
        .allMatches(block)
        .map((m) => _xmlUnescape(m.group(1) ?? ''))
        .join();
    if (texts.trim().isNotEmpty) {
      buf.writeln(texts);
    }
  }
  if (buf.isEmpty) {
    return RegExp(r'<w:t[^>]*>([\s\S]*?)</w:t>', caseSensitive: false)
        .allMatches(xml)
        .map((m) => _xmlUnescape(m.group(1) ?? ''))
        .join('\n');
  }
  return buf.toString().trim();
}

String _xmlUnescape(String s) {
  return s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}

Uint8List buildProjectPriceImportTemplateXlsx() {
  return buildSimpleXlsx(
    sheetName: 'Расценки',
    rows: const [
      ['match_key', 'наименование', 'ед', 'цена'],
      ['finish_floor', 'Устройство пола', 'м²', '850.00'],
      ['finish_wall', 'Облицовка стен', 'м²', '620.00'],
      ['finish_ceiling', 'Подвесной потолок', 'м²', '1200.00'],
      ['purchase', 'Плиты/кассеты закупка', 'шт', '180.00'],
    ],
  );
}

/// Build minimal DOCX with plain paragraphs (for tests).
Uint8List buildSimpleDocx(List<String> paragraphs) {
  final body = paragraphs
      .map(
        (p) =>
            '<w:p><w:r><w:t xml:space="preserve">${_xmlEscape(p)}</w:t></w:r></w:p>',
      )
      .join();
  final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>$body</w:body>
</w:document>''';

  final archive = Archive()
    ..addFile(ArchiveFile('[Content_Types].xml', 0, utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''')))
    ..addFile(ArchiveFile('_rels/.rels', 0, utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''')))
    ..addFile(ArchiveFile('word/document.xml', 0, utf8.encode(documentXml)));

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _xmlEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
