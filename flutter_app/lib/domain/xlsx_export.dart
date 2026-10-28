import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Minimal XLSX (Office Open XML) writer for tabular BOM export.
///
/// Uses sharedStrings + styles so Excel does not offer "repair".
Uint8List buildSimpleXlsx({
  required String sheetName,
  required List<List<String>> rows,
}) {
  final cells = <String, XlsxCell>{};
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      cells['${_colName(c)}${r + 1}'] = XlsxCell.text(rows[r][c]);
    }
  }
  return buildSparseXlsx(sheetName: sheetName, cells: cells);
}

class XlsxCell {
  const XlsxCell.text(this.value) : isNumber = false;
  const XlsxCell.number(this.value) : isNumber = true;

  final String value;
  final bool isNumber;
}

Uint8List buildSparseXlsx({
  required String sheetName,
  required Map<String, XlsxCell> cells,
}) {
  final strings = <String>[];
  final stringIndex = <String, int>{};

  int addString(String raw) {
    final cleaned = _sanitizeCellText(raw);
    final existing = stringIndex[cleaned];
    if (existing != null) return existing;
    final i = strings.length;
    strings.add(cleaned);
    stringIndex[cleaned] = i;
    return i;
  }

  final byRow = <int, List<String>>{};
  final sortedRefs = cells.keys.toList()..sort(_cellRefSort);
  for (final ref in sortedRefs) {
    final rowNum = int.parse(RegExp(r'\d+').firstMatch(ref)!.group(0)!);
    byRow.putIfAbsent(rowNum, () => []);
    final cell = cells[ref]!;
    if (cell.isNumber) {
      final raw = cell.value.replaceAll(',', '.');
      final asDouble = double.tryParse(raw);
      final numVal = asDouble == null
          ? raw
          : (asDouble == asDouble.roundToDouble()
              ? '${asDouble.round()}'
              : asDouble.toString());
      byRow[rowNum]!.add('<c r="$ref"><v>$numVal</v></c>');
    } else {
      final idx = addString(cell.value);
      byRow[rowNum]!.add('<c r="$ref" t="s"><v>$idx</v></c>');
    }
  }

  final sheetRows = StringBuffer();
  for (final rowNum in byRow.keys.toList()..sort()) {
    sheetRows.write('<row r="$rowNum">');
    sheetRows.write(byRow[rowNum]!.join());
    sheetRows.write('</row>');
  }

  final sst = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
      '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'count="${strings.length}" uniqueCount="${strings.length}">',
    );
  for (final s in strings) {
    final esc = _xmlEscape(s);
    final space =
        (s.startsWith(' ') || s.endsWith(' ') || s.contains('\n'))
            ? ' xml:space="preserve"'
            : '';
    sst.write('<si><t$space>$esc</t></si>');
  }
  sst.write('</sst>');

  // ASCII-safe sheet name for Excel (Cyrillic names often trigger repair).
  final safeSheetName = _safeSheetName(sheetName);

  final archive = Archive();
  void addXml(String path, String xml) {
    archive.addFile(ArchiveFile.bytes(path, utf8.encode(xml)));
  }

  addXml(
    '[Content_Types].xml',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
</Types>''',
  );

  addXml(
    '_rels/.rels',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''',
  );

  addXml(
    'xl/workbook.xml',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="${_xmlEscape(safeSheetName)}" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>''',
  );

  addXml(
    'xl/_rels/workbook.xml.rels',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
</Relationships>''',
  );

  addXml(
    'xl/styles.xml',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="1"><font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font></fonts>
  <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
  </fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''',
  );

  addXml('xl/sharedStrings.xml', sst.toString());

  addXml(
    'xl/worksheets/sheet1.xml',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheetData>$sheetRows</sheetData>
</worksheet>''',
  );

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Excel sheet names: max 31 chars, no \\ / ? * [ ].
String _safeSheetName(String name) {
  var s = name
      .replaceAll(RegExp(r'[\\/?*\[\]]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.isEmpty) s = 'Sheet1';
  // Prefer ASCII for maximum Excel compatibility on Windows.
  if (RegExp(r'[^\x20-\x7E]').hasMatch(s)) {
    if (s.toLowerCase().contains('ks-2') || s.contains('КС')) return 'KS-2';
    if (s.toLowerCase().contains('ks-3') || s.contains('КС-3')) return 'KS-3';
    if (s.contains('КП') || s.toLowerCase().contains('kp')) return 'KP';
    return 'Sheet1';
  }
  if (s.length > 31) s = s.substring(0, 31);
  return s;
}

String _colName(int index) {
  var n = index + 1;
  final buf = StringBuffer();
  while (n > 0) {
    n--;
    buf.writeCharCode(65 + (n % 26));
    n ~/= 26;
  }
  return buf.toString().split('').reversed.join();
}

String _sanitizeCellText(String s) =>
    s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

int _cellRefSort(String a, String b) {
  final ra = int.parse(RegExp(r'\d+').firstMatch(a)!.group(0)!);
  final rb = int.parse(RegExp(r'\d+').firstMatch(b)!.group(0)!);
  if (ra != rb) return ra.compareTo(rb);
  return a.compareTo(b);
}
