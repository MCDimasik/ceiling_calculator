import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'xlsx_export.dart';

/// Fill an existing XLSX blank (preserves styles/merges) by patching sheet cells.
///
/// Critical for Excel: keep original `<si>` XML intact and only **append** new
/// shared strings. Rewriting the whole SST (flattening rich text) makes Excel
/// offer «восстановление».
Uint8List fillXlsxTemplate({
  required Uint8List templateBytes,
  required Map<String, XlsxCell> cells,
  String worksheetPath = 'xl/worksheets/sheet1.xml',
  String sharedStringsPath = 'xl/sharedStrings.xml',
  /// Clone [expandTemplateRow] so [expandCount] data lines fit (KS «по помещениям»).
  int? expandTemplateRow,
  int expandCount = 1,
}) {
  final decoded = ZipDecoder().decodeBytes(templateBytes);
  final files = <String, List<int>>{};
  for (final file in decoded.files) {
    if (!file.isFile) continue;
    files[file.name] = List<int>.from(file.content as List<int>);
  }

  final ssRaw = files[sharedStringsPath];
  final shared = _SharedStringsTable.parse(
    ssRaw == null ? null : utf8.decode(ssRaw),
  );

  final sheetRaw = files[worksheetPath];
  if (sheetRaw == null) {
    throw StateError('Worksheet $worksheetPath missing in template');
  }
  var sheetXml = utf8.decode(sheetRaw);
  // Drop ConsultantPlus print header — not part of GOST KS blanks.
  sheetXml = sheetXml.replaceAll(
    RegExp(r'<headerFooter[\s\S]*?</headerFooter>'),
    '',
  );
  // Blank opens in pageBreakPreview → Excel paints «Страница 1» watermark.
  sheetXml = sheetXml.replaceAllMapped(
    RegExp(r'(<sheetView\b)([^>]*?)(/?>)'),
    (m) {
      var attrs = m.group(2)!;
      if (attrs.contains('view="pageBreakPreview"') ||
          attrs.contains('view="pageLayout"')) {
        attrs = attrs.replaceAll(
          RegExp(r'\s*view="(?:pageBreakPreview|pageLayout)"'),
          '',
        );
      }
      return '${m.group(1)}$attrs${m.group(3)}';
    },
  );
  // Drop printerSettings link — leftover page chrome from the blank.
  sheetXml = sheetXml.replaceAllMapped(
    RegExp(r'<pageSetup([^>]*?)\s+r:id="[^"]+"([^>]*?)/?>'),
    (m) => '<pageSetup${m.group(1)}${m.group(2)}/>',
  );
  if (expandTemplateRow != null && expandCount > 1) {
    sheetXml = _expandSheetDataRows(
      sheetXml,
      templateRow: expandTemplateRow,
      count: expandCount,
    );
  }
  final patchedSheet = _patchSheetXml(sheetXml, cells, shared);
  files[worksheetPath] = utf8.encode(patchedSheet);
  files[sharedStringsPath] = utf8.encode(shared.toXml());

  // Ensure Content_Types mentions sharedStrings.
  final ctPath = '[Content_Types].xml';
  final ct = files[ctPath];
  if (ct != null) {
    var ctXml = utf8.decode(ct);
    if (!ctXml.contains('/xl/sharedStrings.xml')) {
      ctXml = ctXml.replaceFirst(
        '</Types>',
        '  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>\n</Types>',
      );
      files[ctPath] = utf8.encode(ctXml);
    }
  }

  final out = Archive();
  for (final e in files.entries) {
    out.addFile(ArchiveFile.bytes(e.key, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}

class _SharedStringsTable {
  _SharedStringsTable({
    required this.siXmlBlocks,
    required this.plainTexts,
    required this.header,
    required this.originalCount,
    required this.originalUnique,
  });

  /// Opaque original `<si>…</si>` blobs (preserve rich text).
  final List<String> siXmlBlocks;

  /// Plain text of each [siXmlBlocks] entry (for dedup of new values).
  final List<String> plainTexts;

  /// Opening `<sst …>` tag from the blank (xmlns etc.).
  final String header;

  final int originalCount;
  final int originalUnique;

  int get length => siXmlBlocks.length;

  static _SharedStringsTable parse(String? xml) {
    if (xml == null || xml.isEmpty) {
      return _SharedStringsTable(
        siXmlBlocks: [],
        plainTexts: [],
        header:
            '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="0" uniqueCount="0">',
        originalCount: 0,
        originalUnique: 0,
      );
    }
    final headerMatch = RegExp(r'<sst[^>]*>').firstMatch(xml);
    final header = headerMatch?.group(0) ??
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">';
    final count = int.tryParse(
          RegExp(r'\bcount="(\d+)"').firstMatch(header)?.group(1) ?? '',
        ) ??
        0;
    final unique = int.tryParse(
          RegExp(r'\buniqueCount="(\d+)"').firstMatch(header)?.group(1) ?? '',
        ) ??
        0;

    final siRe = RegExp(r'<si>.*?</si>', dotAll: true);
    final blocks = <String>[];
    final plains = <String>[];
    for (final m in siRe.allMatches(xml)) {
      final block = m.group(0)!;
      blocks.add(block);
      final t = RegExp(r'<t[^>]*>([^<]*)</t>').firstMatch(block);
      plains.add(_xmlUnescape(t?.group(1) ?? ''));
    }
    return _SharedStringsTable(
      siXmlBlocks: blocks,
      plainTexts: plains,
      header: header,
      originalCount: count,
      originalUnique: unique > 0 ? unique : blocks.length,
    );
  }

  int add(String value) {
    final cleaned =
        value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    final existing = plainTexts.indexOf(cleaned);
    if (existing >= 0) return existing;
    final esc = _xmlEscape(cleaned);
    final space =
        (cleaned.startsWith(' ') ||
                cleaned.endsWith(' ') ||
                cleaned.contains('\n'))
            ? ' xml:space="preserve"'
            : '';
    siXmlBlocks.add('<si><t$space>$esc</t></si>');
    plainTexts.add(cleaned);
    return siXmlBlocks.length - 1;
  }

  String toXml() {
    final added = siXmlBlocks.length - originalUnique;
    // Keep Excel's original count semantics: count ≈ total refs, uniqueCount = si.
    final unique = siXmlBlocks.length;
    final count = (originalCount > originalUnique
            ? originalCount + (added > 0 ? added : 0)
            : unique)
        .clamp(unique, 1 << 30);

    var open = header;
    if (RegExp(r'\bcount="\d+"').hasMatch(open)) {
      open = open.replaceFirst(RegExp(r'\bcount="\d+"'), 'count="$count"');
    } else {
      open = open.replaceFirst('<sst', '<sst count="$count"');
    }
    if (RegExp(r'\buniqueCount="\d+"').hasMatch(open)) {
      open = open.replaceFirst(
        RegExp(r'\buniqueCount="\d+"'),
        'uniqueCount="$unique"',
      );
    } else {
      open = open.replaceFirst('<sst', '<sst uniqueCount="$unique"');
    }

    final buf = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(open);
    for (final si in siXmlBlocks) {
      buf.write(si);
    }
    buf.write('</sst>');
    return buf.toString();
  }
}

/// Insert (count-1) clones of [templateRow], shifting later rows and merges.
String _expandSheetDataRows(
  String xml, {
  required int templateRow,
  required int count,
}) {
  if (count <= 1) return xml;
  final extra = count - 1;
  final rowRe = RegExp(
    '<row r="$templateRow"([^>]*)>(.*?)</row>',
    dotAll: true,
  );
  final m = rowRe.firstMatch(xml);
  if (m == null) return xml;
  final attrs = m.group(1) ?? '';
  final body = m.group(2) ?? '';

  final clones = StringBuffer();
  for (var i = 1; i <= extra; i++) {
    final newRow = templateRow + i;
    final newBody = body.replaceAllMapped(
      RegExp('r="([A-Z]+)$templateRow"'),
      (mm) => 'r="${mm.group(1)}$newRow"',
    );
    clones.write('<row r="$newRow"$attrs>$newBody</row>');
  }

  // Temporary marker so renumber pass does not touch the new clones twice.
  const marker = '___CLONE_ROWS___';
  var out = xml.replaceFirst(m.group(0)!, '${m.group(0)!}$marker');

  // Renumber existing rows below template (high → low).
  final existingRows = RegExp(r'<row r="(\d+)"')
      .allMatches(out)
      .map((e) => int.parse(e.group(1)!))
      .where((r) => r > templateRow)
      .toSet()
      .toList()
    ..sort((a, b) => b.compareTo(a));
  for (final r in existingRows) {
    final nr = r + extra;
    out = out.replaceAll('<row r="$r"', '<row r="$nr"');
    out = out.replaceAllMapped(
      RegExp('r="([A-Z]+)$r"'),
      (mm) => 'r="${mm.group(1)}$nr"',
    );
  }

  // Collect merges that live on the template data row so we can clone them.
  final templateMerges = <String>[];
  for (final mm in RegExp(r'<mergeCell ref="([^"]+)"').allMatches(out)) {
    final ref = mm.group(1)!;
    if (_mergeTouchesRow(ref, templateRow)) {
      templateMerges.add(ref);
    }
  }

  // Merge refs: shift any range that starts at/after templateRow+1.
  out = out.replaceAllMapped(RegExp(r'<mergeCell ref="([^"]+)"'), (mm) {
    final ref = mm.group(1)!;
    final shifted = _shiftMergeRef(ref, afterRow: templateRow, delta: extra);
    return '<mergeCell ref="$shifted"';
  });

  // Clone template-row merges onto each inserted data row.
  if (templateMerges.isNotEmpty && extra > 0) {
    final cloneMergeXml = StringBuffer();
    for (var i = 1; i <= extra; i++) {
      final newRow = templateRow + i;
      for (final ref in templateMerges) {
        cloneMergeXml.write(
          '<mergeCell ref="${_retargetMergeToRow(ref, templateRow, newRow)}"/>',
        );
      }
    }
    final mergeClose = RegExp(r'</mergeCells>');
    if (mergeClose.hasMatch(out)) {
      out = out.replaceFirst(mergeClose, '${cloneMergeXml.toString()}</mergeCells>');
      out = _bumpMergeCellsCount(out, extra * templateMerges.length);
    }
  }

  out = out.replaceFirst(marker, clones.toString());
  return out;
}

bool _mergeTouchesRow(String ref, int row) {
  final parts = ref.split(':');
  int? rowOf(String cell) {
    final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(cell);
    return m == null ? null : int.parse(m.group(2)!);
  }

  if (parts.length == 1) return rowOf(parts[0]) == row;
  final a = rowOf(parts[0]);
  final b = rowOf(parts[1]);
  if (a == null || b == null) return false;
  final lo = a < b ? a : b;
  final hi = a < b ? b : a;
  return row >= lo && row <= hi;
}

String _retargetMergeToRow(String ref, int fromRow, int toRow) {
  final parts = ref.split(':');
  String one(String cell) {
    final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(cell);
    if (m == null) return cell;
    final r = int.parse(m.group(2)!);
    if (r != fromRow) return cell;
    return '${m.group(1)}$toRow';
  }

  if (parts.length == 1) return one(parts[0]);
  return '${one(parts[0])}:${one(parts[1])}';
}

String _bumpMergeCellsCount(String xml, int add) {
  if (add <= 0) return xml;
  return xml.replaceFirstMapped(
    RegExp(r'<mergeCells([^>]*)\scount="(\d+)"'),
    (m) {
      final n = int.parse(m.group(2)!) + add;
      return '<mergeCells${m.group(1)} count="$n"';
    },
  );
}

String _shiftMergeRef(String ref, {required int afterRow, required int delta}) {
  // e.g. F32:N32 or A38:E38
  final parts = ref.split(':');
  String shiftOne(String cell) {
    final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(cell);
    if (m == null) return cell;
    final row = int.parse(m.group(2)!);
    if (row <= afterRow) return cell;
    return '${m.group(1)}${row + delta}';
  }

  if (parts.length == 1) return shiftOne(parts[0]);
  return '${shiftOne(parts[0])}:${shiftOne(parts[1])}';
}

String _patchSheetXml(
  String xml,
  Map<String, XlsxCell> cells,
  _SharedStringsTable shared,
) {
  var result = xml;
  final byRow = <int, List<MapEntry<String, XlsxCell>>>{};
  for (final e in cells.entries) {
    byRow.putIfAbsent(_rowOf(e.key), () => []).add(e);
  }

  for (final rowEntry in byRow.entries) {
    final rowNum = rowEntry.key;
    for (final cellEntry in rowEntry.value) {
      result = _upsertCell(result, cellEntry.key, cellEntry.value, shared);
    }
    if (!RegExp('<row r="$rowNum"[^>]*>').hasMatch(result)) {
      result = _insertRow(result, rowNum, rowEntry.value, shared);
    }
  }
  return result;
}

int _rowOf(String ref) {
  final m = RegExp(r'(\d+)$').firstMatch(ref);
  return int.parse(m!.group(1)!);
}

String _colOf(String ref) => ref.replaceAll(RegExp(r'\d+$'), '');

int _colIndex(String col) {
  var n = 0;
  for (final cu in col.codeUnits) {
    n = n * 26 + (cu - 64);
  }
  return n;
}

String _cellXml(
  String ref,
  XlsxCell cell,
  _SharedStringsTable shared, {
  String? style,
}) {
  final sAttr = (style != null && style.isNotEmpty) ? ' s="$style"' : '';
  if (cell.isNumber) {
    final raw = cell.value.replaceAll(',', '.');
    final asDouble = double.tryParse(raw);
    final numVal = asDouble == null
        ? raw
        : (asDouble == asDouble.roundToDouble()
            ? '${asDouble.round()}'
            : asDouble.toString());
    return '<c r="$ref"$sAttr><v>$numVal</v></c>';
  }
  final idx = shared.add(cell.value);
  return '<c r="$ref"$sAttr t="s"><v>$idx</v></c>';
}

String _upsertCell(
  String xml,
  String ref,
  XlsxCell cell,
  _SharedStringsTable shared,
) {
  // Self-closing first. An open-tag regex with [^>]* can match `.../>` and then
  // `(.*?)</c>` swallows following cells — Excel then asks to repair.
  final selfRe = RegExp('<c r="$ref"([^>]*)/>');
  final openRe = RegExp('<c r="$ref"([^>]*?)>(.*?)</c>', dotAll: true);
  final match = selfRe.firstMatch(xml) ?? openRe.firstMatch(xml);
  if (match != null) {
    final attrs = match.group(1) ?? '';
    final styleMatch = RegExp(r'\bs="([^"]*)"').firstMatch(attrs);
    final style = styleMatch?.group(1);
    return xml.replaceFirst(
      match.group(0)!,
      _cellXml(ref, cell, shared, style: style),
    );
  }

  final rowNum = _rowOf(ref);
  final rowRe = RegExp('<row r="$rowNum"([^>]*)>(.*?)</row>', dotAll: true);
  final rowMatch = rowRe.firstMatch(xml);
  if (rowMatch != null) {
    final rowAttrs = rowMatch.group(1) ?? '';
    final rowBody = rowMatch.group(2) ?? '';
    final styleMatch = RegExp(r'\bs="([^"]*)"').firstMatch(rowAttrs);
    final siblingStyle = RegExp(r'\bs="(\d+)"').firstMatch(rowBody)?.group(1) ??
        styleMatch?.group(1);
    final inserted =
        _insertCellSorted(rowBody, ref, cell, shared, siblingStyle);
    return xml.replaceFirst(
      rowMatch.group(0)!,
      '<row r="$rowNum"$rowAttrs>$inserted</row>',
    );
  }

  return _insertRow(xml, rowNum, [MapEntry(ref, cell)], shared);
}

String _insertCellSorted(
  String rowBody,
  String ref,
  XlsxCell cell,
  _SharedStringsTable shared,
  String? style,
) {
  final newCell = _cellXml(ref, cell, shared, style: style);
  final col = _colIndex(_colOf(ref));
  final cellRe =
      RegExp(r'<c r="([A-Z]+)\d+"[^>]*(?:/>|>.*?</c>)', dotAll: true);
  final matches = cellRe.allMatches(rowBody).toList();
  for (final m in matches) {
    final existingCol = _colIndex(m.group(1)!);
    if (col < existingCol) {
      return rowBody.replaceFirst(m.group(0)!, '$newCell${m.group(0)!}');
    }
  }
  return '$rowBody$newCell';
}

String _insertRow(
  String xml,
  int rowNum,
  List<MapEntry<String, XlsxCell>> cells,
  _SharedStringsTable shared,
) {
  final body = StringBuffer();
  final sorted = List<MapEntry<String, XlsxCell>>.from(cells)
    ..sort(
      (a, b) => _colIndex(_colOf(a.key)).compareTo(_colIndex(_colOf(b.key))),
    );
  for (final e in sorted) {
    body.write(_cellXml(e.key, e.value, shared));
  }
  final rowXml = '<row r="$rowNum">$body</row>';

  final nextRowRe = RegExp(r'<row r="(\d+)"');
  for (final m in nextRowRe.allMatches(xml)) {
    final n = int.parse(m.group(1)!);
    if (n > rowNum) {
      return xml.replaceFirst(m.group(0)!, '$rowXml${m.group(0)!}');
    }
  }
  return xml.replaceFirst('</sheetData>', '$rowXml</sheetData>');
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
